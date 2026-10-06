from datetime import datetime
import numpy as np
from fastapi import HTTPException, status
import math

from preprocess import (
    project_route as project_onto_route,
    ArrivalStatus,
)
from traffic_data import get_timestamp_congestion_index

from core import (
    logger,
    LOCAL_TZ,
    UNKNOWN_ETA_MINUTES,
    stop_to_trips,
    shapes,
    stop_distances,
    get_model,
)


def get_eta_message(eta):
    if eta == UNKNOWN_ETA_MINUTES:
        return "? min"

    # doar in caz de erori cu nr negative care nu ar trebui sa apara
    min_eta = max(0, math.floor(eta - 0.5))
    max_eta = min(60, max(1, math.ceil(eta + 1)))

    eta_message = f"{min_eta} - {max_eta} min"

    if max_eta > 35 or min_eta > 30:
        eta_message = ">30 min"

    return eta_message


async def get_prediction(
    agency_id: str,
    trip_id: str,
    lat: float,
    lon: float,
    stop_id: str,
    stop_appearance_index: int | None = None,
):
    # face efectiv predictia ETA pt un vehicul aflat pe ruta

    # validam formatul trip_id si lat/lon
    if trip_id.count("_") != 1:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST)
    if not (10 <= lat <= 50 and 10 <= lon <= 50):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST)

    shape_data = shapes.get(agency_id, {}).get(trip_id)
    if shape_data is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Cannot get shapes for trip"
        )

    # proiectam vehiculul pe ruta, statia avem deja
    pr = project_onto_route(lat, lon, shape_data)
    if pr is None or pr[0] is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot project vehicle onto route",
        )

    veh_dist, _ = pr

    stop_dist_candidates = (
        stop_distances.get(agency_id, {}).get(trip_id, {}).get(stop_id)
    )
    if stop_dist_candidates is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot project stop onto route",
        )

    if isinstance(stop_dist_candidates, list):
        if stop_appearance_index is not None and stop_appearance_index < len(
            stop_dist_candidates
        ):
            stop_dist = stop_dist_candidates[stop_appearance_index]
        else:
            future_stop_dist = [
                dist for dist in stop_dist_candidates if dist >= veh_dist + 25
            ]
            if not future_stop_dist:
                return 0.0, ArrivalStatus.PASSED.value

            stop_dist = min(future_stop_dist)
    else:
        stop_dist = stop_dist_candidates

    # distanta de-a lungul rutei pana la statie minus pana la vehicul
    delta = stop_dist - veh_dist

    # daca vehiculul a trecut deja statia (cu tot cu timpul de update gtfs trece si daca e la 25 metri)
    if delta < 25:
        return 0.0, ArrivalStatus.PASSED.value

    # daca e aproape, o sa aproximam ca ajunge in urmatorul minut
    # poate 130m pare mult dar cum nu e "fresh" pozitia, are un avantaj si probabil ajunge
    if delta < 130:
        return 0.0, ArrivalStatus.ARRIVING.value

    model = await get_model(agency_id, trip_id)
    if model is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No data to make prediction for trip",
        )

    # incarcam knn-ul si vecinii
    X, y, c, t = model["X"], model["y"], model["c"], model["t"]
    nbrs = model["nbrs"]
    feat = np.array([[veh_dist, delta]])
    _, idxs = nbrs.kneighbors(feat)

    # calculam media ponderata a eta-urilor istorice apropiate
    # cele mai apropiate de vehicul au o influenta mai mare, ca poate se schimba cum e drumul
    # imparte cu congestion index ca sa avem un fel de normalizare, si la final o sa inmultim cu congestion index-ul curent
    total_w = 0.0
    total_eta = 0.0

    now = datetime.now(LOCAL_TZ)

    for i in idxs[0]:
        historical_dist = X[i, 0]
        projected_dist = abs(veh_dist - historical_dist)

        # print(f"point {i}: hist_d={hist_d}, pdist={pdist}, delta={delta}")

        # functie de calculat ponderea, daca e la mai putin de 50m, pondere mare, intre 50 si 200m mai mica
        # peste 200m mai bine nu consideram ca e inaccurate
        if projected_dist <= 50:
            w = 0.8 + 0.2 * (1 - projected_dist / 50)
        elif projected_dist <= 200:
            w = 0.7 - (0.6 * ((projected_dist - 50) / 150))
        else:
            continue

        # bonus pentru puncte din perioade similare
        historical_time = t[i]

        same_week_day = historical_time.weekday() == now.weekday()
        same_week_period = (historical_time.weekday() < 5 and now.weekday() < 5) or (
            historical_time.weekday() >= 5 and now.weekday() >= 5
        )
        same_day_time_period = abs(historical_time.hour - now.hour) <= 1

        time_factor = 1.0
        if same_week_day:
            time_factor *= 1.1

        if same_week_period:
            time_factor *= 1.2

        if same_day_time_period:
            time_factor *= 1.4

        # ca sa avem cat e "totalul" de ponderi
        w *= time_factor
        total_w += w

        total_eta += (y[i] / c[i]) * w

    if total_w == 0:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No data to make prediction for trip",
        )

    congestion_index = get_timestamp_congestion_index(now)
    # prefer sa dau doar avertisment decat sa presupun ca o sa cauzeze intarzieri
    # weather_mult = weather_state.get(agency_id, {}).get("eta_multiplier", 1.0)
    eta = (total_eta / total_w) * congestion_index

    return float(eta), ArrivalStatus.ARRIVING.value


async def compute_arrivals(agency_id: str, stop_id: str, vehicle_positions: list[dict]):
    trips = stop_to_trips.get(agency_id, {}).get(stop_id, [])
    if not trips:
        return []

    relevant = [v for v in vehicle_positions if v["trip_id"] in trips]
    predictions = []

    for v in relevant:
        try:
            eta_s, msg = await get_prediction(
                agency_id, v["trip_id"], v["lat"], v["lon"], stop_id
            )
        except HTTPException as e:
            predictions.append(
                {
                    "trip_id": v["trip_id"],
                    "vehicle_label": v.get("label"),
                    "predicted_eta_minutes": UNKNOWN_ETA_MINUTES,
                    "message": ArrivalStatus.UNKNOWN.value,
                }
            )
            continue
        except Exception as e:
            logger.error("get_prediction failed for %s: %s", v["trip_id"], e)
            predictions.append(
                {
                    "trip_id": v["trip_id"],
                    "vehicle_label": v.get("label"),
                    "predicted_eta_minutes": UNKNOWN_ETA_MINUTES,
                    "message": ArrivalStatus.UNKNOWN.value,
                }
            )
            continue

        # fixare la timp pentru ca vehiculele au fost actualizate doar acum ceva timp
        # nu e chiar vehicul, e alta structura deci e ts primit ca Iso8601String nu timestamp
        ts = v.get("ts")

        if ts:
            vehicle_timestamp = datetime.fromisoformat(
                ts.replace("Z", "+00:00")
            ).astimezone(LOCAL_TZ)
        else:
            vehicle_timestamp = datetime.now(LOCAL_TZ)

        current_time = datetime.now(LOCAL_TZ)
        time_difference_seconds = (current_time - vehicle_timestamp).total_seconds()

        if time_difference_seconds >= 180:
            # daca datele sunt mai vechi de 3 minute, nu le ajustam ca probabil e eroare
            updated_eta = eta_s / 60
        else:
            updated_eta = max(0.0, eta_s - time_difference_seconds) / 60

        if msg == ArrivalStatus.ARRIVING.value:
            predictions.append(
                {
                    "trip_id": v["trip_id"],
                    "vehicle_label": v.get("label"),
                    "predicted_eta_minutes": round(updated_eta, 2),
                    "message": msg,
                }
            )

    predictions.sort(key=lambda x: x["predicted_eta_minutes"])
    return predictions
