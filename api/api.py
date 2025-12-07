from contextlib import asynccontextmanager
import pickle
from datetime import datetime
import numpy as np
import os
from fastapi import FastAPI, HTTPException, Query, status, Body
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse
from typing import List
from dotenv import load_dotenv
from pymongo import MongoClient
from pathlib import Path
import httpx
import logging
import random
import asyncio
import redis

# importam functii utile si constante
from preprocess import (
    load_shapes,
    load_stops,
    project_route as project_onto_route,
    timezone_offset,
    tz,
    ArrivalStatus,
)
from traffic_data import get_timestamp_congestion_index

# incarcam variabilele din .env
load_dotenv()

current_folder = os.path.dirname(os.path.abspath(__file__))
log_path = os.path.join(current_folder, "api.log")

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

fh = logging.FileHandler(log_path)
formatter = logging.Formatter("%(asctime)s [%(levelname)s] %(message)s")
fh.setFormatter(formatter)

logger.addHandler(fh)

# configuri din .env
MONGO_URL = os.getenv("MONGO_URL") or "mongo_fallback_url"
DB_NAME = os.getenv("DB_NAME") or "db_fallback_name"
CSV_DIR = Path("csv")

AGENCY_IDS = ["1", "2", "4", "6", "8"]
EXTERNAL_TIMETABLES_AGENCY_IDS = ["1", "4", "6", "8"]

GHOST_VEHICLE_POSITIONS_CONSIDERED = 50
GHOST_VEHICLE_MAX_COORDINATE_CHANGE = 0.0005  # aprox 40 m

MIN_VALID_EXTERNAL_TIMETABLE_SIZE = 100  # bytes

UNKNOWN_ETA_MINUTES = 999

# cache local pt modele, statii, rute, distante
models_cache = {}
shapes = {}
stop_locs = {}
trip_stops = {}
stop_to_trips = {}
stop_dists_by_trip = {}
stop_distances = {}


@asynccontextmanager
async def lifespan(app: FastAPI):
    # pentru distribuire la toti workerii
    app.state.redis = redis.Redis(host="localhost", port=6379, decode_responses=True)

    logger.info("Application startup: Initializing data...")
    init_data()

    # ca sa fie pe faza serverul si sa aiba date despre vehicule fantoma
    task = asyncio.create_task(fetch_vehicles_periodically())

    yield
    logger.info("Application shutdown: Clearing models cache...")
    models_cache.clear()

    task.cancel()
    await task


app = FastAPI(lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:46353",
        "https://mapmybus.marian.homes",
    ],
    allow_credentials=False,
    allow_methods=["GET", "OPTIONS", "POST"],
    allow_headers=["*"],
)


async def fetch_vehicles_periodically():
    while True:
        await asyncio.sleep(90)

        for agency_id in AGENCY_IDS:
            try:
                await get_vehicles(agency_id)
            except Exception as e:
                logger.error(
                    f"Error fetching vehicles (periodically) for agency {agency_id}: {e}"
                )


def init_data():
    # incarcam formele, statiile si fisierele .pkl

    global shapes, stop_locs, trip_stops, stop_to_trips, stop_dists_by_trip, stop_distances

    for agency_id in AGENCY_IDS:
        logger.info("Loading shapes for agency %s...", agency_id)
        shapes[agency_id] = load_shapes(agency_id)

        logger.info("Loading stops & trip sequences for agency %s...", agency_id)
        stop_locs[agency_id], trip_stops[agency_id] = load_stops(agency_id)

        logger.info("Loading stop_to_trips.pkl for agency %s...", agency_id)
        with open(f"models/agency{agency_id}_stop_to_trips.pkl", "rb") as f:
            stop_to_trips[agency_id] = pickle.load(f)

        logger.info("Loading stop_dists_by_trip.pkl for agency %s...", agency_id)
        with open(f"models/agency{agency_id}_stop_dists_by_trip.pkl", "rb") as f:
            stop_dists_by_trip[agency_id] = pickle.load(f)

        stop_distances[agency_id] = stop_dists_by_trip[agency_id]

        logger.info(
            "Data ready for agency %s: %s shapes, %s stops, %s trips, %s stop->trip mappings",
            agency_id,
            len(shapes[agency_id]),
            len(stop_locs[agency_id]),
            len(trip_stops[agency_id]),
            len(stop_to_trips[agency_id]),
        )


def get_model(agency_id: str, trip_id: str):
    # intoarce modelul kNN pt un anumit trip_id (din cache sau il incarca)

    if (agency_id, trip_id) in models_cache:
        return models_cache[(agency_id, trip_id)]

    path = f"models/agency{agency_id}_{trip_id}_knn.pkl"
    try:
        with open(path, "rb") as f:
            m = pickle.load(f)
            models_cache[(agency_id, trip_id)] = m
            return m
    except FileNotFoundError:
        return None


def get_prediction(agency_id: str, trip_id: str, lat: float, lon: float, stop_id: str):
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
    veh_dist = project_onto_route(lat, lon, shape_data)
    stop_dist = stop_distances.get(agency_id, {}).get(trip_id, {}).get(stop_id)
    if veh_dist is None or stop_dist is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot project vehicle or stop onto route",
        )

    # distanta de-a lungul rutei pana la statie minus pana la vehicul
    delta = stop_dist - veh_dist

    # daca vehiculul a trecut deja statia (cu tot cu timpul de update gtfs trece si daca e la 25 metri)
    if delta < 25:
        return 0.0, ArrivalStatus.PASSED.value

    # daca e aproape, o sa aproximam ca ajunge in urmatorul minut
    # poate 150 pare mult dar cum nu e "fresh" pozitia, are un avantaj si probabil ajunge
    if delta < 150:
        return 0.0, ArrivalStatus.ARRIVING.value

    model = get_model(agency_id, trip_id)
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
        # now pe server e cu 3 ore in urma
        now = datetime.now() + timezone_offset
        historical_time = t[i]

        same_week_day = historical_time.weekday() == now.weekday()
        same_week_period = (historical_time.weekday() < 5 and now.weekday() < 5) or (
            historical_time.weekday() >= 5 and now.weekday() >= 5
        )
        same_day_period = abs(historical_time.hour - now.hour) <= 1

        if same_week_day:
            w += 0.2

        if same_week_period:
            w += 0.4

        if same_day_period:
            w += 0.7

        # ca sa avem cat e "totalul" de ponderi
        total_w += w

        total_eta += (y[i] / c[i]) * w

    if total_w == 0:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No data to make prediction for trip",
        )

    congestion_index = get_timestamp_congestion_index(now)
    eta = (total_eta / total_w) * congestion_index

    return float(eta), ArrivalStatus.ARRIVING.value


# pentru aproximat urmatoarele sosiri la o statie
@app.post("/predict/{agency_id}/arrivals/{stop_id}")
def get_arrivals_for_stop(
    agency_id: str, stop_id: str, vehicle_positions: List[dict] = Body(...)
):
    if agency_id not in AGENCY_IDS:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST)

    trips = stop_to_trips.get(agency_id, {}).get(stop_id, [])
    if not trips:
        return []

    relevant = [v for v in vehicle_positions if v["trip_id"] in trips]

    predictions = []

    for v in relevant:
        try:
            eta_s, msg = get_prediction(
                agency_id, v["trip_id"], v["lat"], v["lon"], stop_id
            )
        except HTTPException as e:
            if (
                e.status_code == status.HTTP_404_NOT_FOUND
                and e.detail == "No data to make prediction for trip"
            ):
                predictions.append(
                    {
                        "trip_id": v["trip_id"],
                        "vehicle_label": v.get("label"),
                        "predicted_eta_minutes": UNKNOWN_ETA_MINUTES,  # valoare mare ca sa fie la final de lista sortata
                        "message": ArrivalStatus.UNKNOWN.value,
                    }
                )

                continue

            else:
                continue

        # fixare la timp pentru ca vehiculele au fost actualizate doar acum ceva timp
        # nu e chiar vehicul, e alta structura deci e ts primit ca Iso8601String nu timestamp
        ts = v.get("ts")

        if ts:
            vehicle_timestamp = datetime.fromisoformat(ts)
            if vehicle_timestamp.tzinfo is None:
                vehicle_timestamp = vehicle_timestamp.replace(tzinfo=tz)
            else:
                vehicle_timestamp = vehicle_timestamp.astimezone(tz)
        else:
            vehicle_timestamp = datetime.now(tz)

        current_time = datetime.now(tz)
        time_difference_seconds = (current_time - vehicle_timestamp).total_seconds()

        if time_difference_seconds >= 180:
            # daca datele sunt mai vechi de 3 minute, nu le ajustam ca probabil e eroare
            updated_eta = eta_s / 60
        else:
            updated_eta = (eta_s - time_difference_seconds) / 60

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


# aproximari eta pentru o locatie de vehicul primita si statiile, normal, de pe ruta sa
@app.get("/predict/{agency_id}")
def predict_endpoint(
    agency_id: str,
    trip_id: str,
    ts: str,
    lat: float,
    lon: float,
    stop_ids: List[str] = Query(...),
):
    logger.info(
        "received prediction request for agency %s, trip %s", agency_id, trip_id
    )

    if agency_id not in AGENCY_IDS:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST)

    results = []
    for stop_id in stop_ids:
        try:
            eta_s, msg = get_prediction(agency_id, trip_id, lat, lon, stop_id)
        except HTTPException as e:
            if (
                e.status_code == status.HTTP_404_NOT_FOUND
                and e.detail == "No data to make prediction for trip"
            ):
                results.append(
                    {
                        "trip_id": trip_id,
                        "stop_id": stop_id,
                        "predicted_eta_minutes": UNKNOWN_ETA_MINUTES,
                        "message": ArrivalStatus.UNKNOWN.value,
                    }
                )
                continue

            else:
                raise e

        if ts:
            vehicle_timestamp = datetime.fromisoformat(ts)
            if vehicle_timestamp.tzinfo is None:
                vehicle_timestamp = vehicle_timestamp.replace(tzinfo=tz)
            else:
                vehicle_timestamp = vehicle_timestamp.astimezone(tz)
        else:
            vehicle_timestamp = datetime.now(tz)

        current_time = datetime.now(tz)
        time_difference_seconds = (current_time - vehicle_timestamp).total_seconds()

        if time_difference_seconds >= 180:
            # daca datele sunt mai vechi de 3 minute, nu le ajustam ca probabil e eroare
            updated_eta = eta_s / 60
        else:
            updated_eta = (eta_s - time_difference_seconds) / 60

        results.append(
            {
                "trip_id": trip_id,
                "stop_id": stop_id,
                "predicted_eta_minutes": round(updated_eta, 2),
                "message": msg,
            }
        )
    return results


@app.get("/routes/{agency_id}")
def get_routes(agency_id: str):
    logger.info("fetching routes for agency %s", agency_id)

    if agency_id not in AGENCY_IDS:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST)

    client = MongoClient(MONGO_URL)
    db = client[DB_NAME]

    routes = list(db[f"agency{agency_id}_routes"].find({}))
    if not routes:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="No routes found"
        )

    result = []
    for route in routes:
        result.append(
            {
                "agency_id": agency_id,
                "route_id": route["route_id"],
                "route_short_name": route["route_short_name"],
                "route_long_name": route["route_long_name"],
                "route_color": route["route_color"],
                "route_type": route["route_type"],
                "route_desc": route.get("route_desc", ""),
            }
        )
    client.close()
    return result


@app.get("/stops/{agency_id}")
def get_stops_for_trip(agency_id: str, trip_id: str = Query(default="")):
    logger.info("fetching stops, agency %s, optional trip %s", agency_id, trip_id)

    if agency_id not in AGENCY_IDS:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST)

    client = MongoClient(MONGO_URL)
    db = client[DB_NAME]

    if not trip_id:
        # returnam toate statiile
        stops = list(db[f"agency{agency_id}_stops"].find({}))

        result = [
            {
                "stop_id": str(stop["stop_id"]),
                "stop_name": stop["stop_name"],
                "stop_lat": stop["stop_lat"],
                "stop_lon": stop["stop_lon"],
                "stop_sequence": 0,
            }
            for stop in stops
        ]

        client.close()
        return result

    # returnam statiile in ordinea aparitiei pe ruta
    trip_stops = list(
        db[f"agency{agency_id}_trip_stops"]
        .find({"trip_id": trip_id})
        .sort("stop_sequence", 1)
    )
    stop_ids = [ts["stop_id"] for ts in trip_stops]
    stops = db[f"agency{agency_id}_stops"].find({"stop_id": {"$in": stop_ids}})
    stop_dict = {s["stop_id"]: s for s in stops}

    result = []
    for ts in trip_stops:
        stop = stop_dict.get(ts["stop_id"])
        if stop:
            result.append(
                {
                    "stop_id": str(stop["stop_id"]),
                    "stop_name": stop["stop_name"],
                    "stop_lat": stop["stop_lat"],
                    "stop_lon": stop["stop_lon"],
                    "stop_sequence": ts["stop_sequence"],
                }
            )
    client.close()
    return result


@app.get("/shapes/{agency_id}")
def get_shapes_for_trip(agency_id: str, shape_id: str):
    logger.info("fetching shapes for shape_id %s, agency %s", shape_id, agency_id)

    if agency_id not in AGENCY_IDS:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST)

    client = MongoClient(MONGO_URL)
    db = client[DB_NAME]

    shapes = (
        db[f"agency{agency_id}_shapes"]
        .find({"shape_id": shape_id})
        .sort("shape_pt_sequence", 1)
    )
    result = [
        {
            "shape_id": shape_id,
            "shape_pt_lat": s["shape_pt_lat"],
            "shape_pt_lon": s["shape_pt_lon"],
            "shape_pt_sequence": s["shape_pt_sequence"],
        }
        for s in shapes
    ]
    client.close()
    return result


@app.get("/trips/{agency_id}")
def get_trip_ids_for_route(agency_id: str, stop_id: str = Query(...)):
    logger.info("fetching trip ids for agency %s, stop_id %s", agency_id, stop_id)

    if agency_id not in AGENCY_IDS:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST)

    trip_ids = stop_to_trips.get(agency_id, {}).get(stop_id, [])

    result = [tid for tid in trip_ids]

    return result


def get_random_api_key():
    idx = random.randint(1, 5)
    return os.getenv(f"API_KEY_{idx}")


@app.get("/vehicles/{agency_id}")
async def get_vehicles(agency_id: str):
    logger.info("fetching vehicles for agency %s", agency_id)

    if agency_id not in AGENCY_IDS:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST)

    headers = {
        "X-Agency-Id": agency_id,
        "Accept": "application/json",
        "X-API-KEY": get_random_api_key(),
    }
    async with httpx.AsyncClient() as client:
        response = await client.get(
            f"{os.getenv('BASE_URL')}/vehicles", headers=headers, timeout=10
        )

    if response.status_code != status.HTTP_200_OK:
        raise HTTPException(status_code=response.status_code, detail=response.text)

    vehicles = response.json()
    valid_vehicles = []

    # filtram vehiculele inutile si adaugam coord primei si ultimei statii pentru calcule mai rapide in frontend
    for vehicle in vehicles:
        trip_id = vehicle.get("trip_id")
        latitude = vehicle.get("latitude")
        longitude = vehicle.get("longitude")
        label = vehicle.get("label")
        ts = vehicle.get("timestamp")
        vehicle["is_ghost"] = False

        if trip_id and latitude and longitude and label and ts:
            vehicle_timestamp = datetime.fromisoformat(ts)
            if vehicle_timestamp.tzinfo is None:
                vehicle_timestamp = vehicle_timestamp.replace(tzinfo=tz)
            else:
                vehicle_timestamp = vehicle_timestamp.astimezone(tz)

            current_time = datetime.now(tz)
            time_difference_seconds = (current_time - vehicle_timestamp).total_seconds()

            if time_difference_seconds > 180:
                continue

            # pot folosi asta ca am statiile per trip in acest dictionar
            stops_ids = list(stop_distances.get(agency_id, {}).get(trip_id, {}).keys())
            if stops_ids:

                # e necesar try pentru ca s-a intamplat sa se schimbe date despre traseu
                try:
                    first_stop = stop_locs[agency_id][stops_ids[0]]
                    last_stop = stop_locs[agency_id][stops_ids[-1]]
                except KeyError:
                    continue

                vehicle["first_stop_lat"] = first_stop[0]
                vehicle["first_stop_lon"] = first_stop[1]

                vehicle["last_stop_lat"] = last_stop[0]
                vehicle["last_stop_lon"] = last_stop[1]

                valid_vehicles.append(vehicle)

    for v in valid_vehicles:
        # ca sa verificam care sunt fantoma (stau afk) folosim un dictionar cu redis
        redis_key = f"{agency_id}:{v.get('label')}"
        positions = app.state.redis.lrange(redis_key, 0, -1)
        positions = [
            (float(lat), float(lon))
            for lat, lon in (pos.split(",") for pos in positions)
        ]

        new_position = (v.get("latitude"), v.get("longitude"))

        if (
            positions
            and sum(abs(a - b) for a, b in zip(positions[-1], new_position))
            > GHOST_VEHICLE_MAX_COORDINATE_CHANGE
        ):
            app.state.redis.delete(redis_key)

        if len(positions) < GHOST_VEHICLE_POSITIONS_CONSIDERED:
            app.state.redis.rpush(redis_key, f"{new_position[0]},{new_position[1]}")

        v["is_ghost"] = len(positions) >= GHOST_VEHICLE_POSITIONS_CONSIDERED

    return valid_vehicles


def get_external_timetable_urls(agency_id: str, route_short_name: str, day_type: str):
    # nu prea bine facut

    match agency_id:
        case "1":
            # iasi
            return [
                f"https://iasitimetable.tranzy.ai/pdfs/track-{route_short_name.lower()}.pdf"
            ]
        case "4":
            # chisinau
            return [f"https://www.autourban.md/index.php?page=orare&tip=all"]
        case "6":
            # botosani
            return [
                f"https://www1.primariabt.ro/pdf/diverse/transport/microbus+autobus.pdf"
            ]
        case "8":
            # timisoara
            return [
                f"https://stpt.ro/{route_short_name.lower()}-2/",
                f"https://stpt.ro/{route_short_name.lower()}/",
            ]
        case _:
            return []


# intoarce orarul csv pt o ruta+zi
@app.get("/timetables/{agency_id}")
async def get_timetable(
    agency_id: str,
    route_short_name: str = Query(...),
    day_type: str = Query(..., enum=["lv", "s", "d"]),
):
    logger.info(
        "fetching timetable for agency %s, route %s, day type %s",
        agency_id,
        route_short_name,
        day_type,
    )

    if agency_id not in AGENCY_IDS:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST)

    if day_type not in ["lv", "s", "d"]:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST)

    if agency_id not in EXTERNAL_TIMETABLES_AGENCY_IDS:
        file_path = (
            CSV_DIR / f"agency{agency_id}_orar_{route_short_name}_{day_type}.csv"
        )
        if not file_path.exists():
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND, detail="Timetable not found"
            )

        return FileResponse(file_path, media_type="text/csv", filename=file_path.name)
    else:
        urls = get_external_timetable_urls(
            agency_id=agency_id, route_short_name=route_short_name, day_type=day_type
        )

        async with httpx.AsyncClient() as client:
            for url in urls:
                response = await client.get(url, timeout=3)

                if (
                    response.status_code == status.HTTP_200_OK
                    and len(response.content) >= MIN_VALID_EXTERNAL_TIMETABLE_SIZE
                ):
                    return JSONResponse({"url": url})

        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Timetable not found"
        )
