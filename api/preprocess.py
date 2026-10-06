import json
import logging
import math
import os
import pickle
import sqlite3
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo
from bisect import bisect_right
from collections import defaultdict
import numpy as np
from sklearn.neighbors import NearestNeighbors
from traffic_data import get_timestamp_congestion_index
from enum import Enum

current_folder = os.path.dirname(os.path.abspath(__file__))
log_path = os.path.join(current_folder, "preprocess.log")

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

fh = logging.FileHandler(log_path)
formatter = logging.Formatter("%(asctime)s [%(levelname)s] %(message)s")
fh.setFormatter(formatter)

logger.addHandler(fh)

LOCAL_TZ = ZoneInfo("Europe/Bucharest")

# constante de configurare
MIN_SAMPLES_PER_TRIP = 600
MAX_SAMPLES_PER_PORTION = 5000
MAX_ETA_SECONDS = 5400
NEIGHBORS_CONSIDERED = 70
MAX_OFFROUTE_DIST = 140
MAX_GAP_SECONDS = 125
MIN_GAP_SECONDS = 9

STOP_ENDS_RADIUS = 120
MIN_JOURNEY_POINTS = 8
MIN_STATIONARY_DIST = 12

MIN_PROJECTED_PROGRESS_METERS = 2.0
MAX_PROJECTED_SPEED_MPS = 25.0

AGENCY_IDS = ["1", "2", "4", "6", "10"]

VEHICLE_TRAIN_DATA_PATHS = [
    "vehicle_jsons/set4",
]


class ArrivalStatus(str, Enum):
    ARRIVING = "arriving"
    PASSED = "passed"
    UNKNOWN = "unknown"


EARTH_RADIUS = 6_371_000.0


def haversine(lat1, lon1, lat2, lon2) -> float:
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = (
        math.sin(dlat / 2) ** 2
        + math.cos(math.radians(lat1))
        * math.cos(math.radians(lat2))
        * math.sin(dlon / 2) ** 2
    )
    return EARTH_RADIUS * 2 * math.asin(math.sqrt(a))


def subsample(X, Y, C, T):
    bins = defaultdict(list)

    for i, ts in enumerate(T):
        if ts.weekday() < 5:
            day_type = 0
        elif ts.weekday() == 5:
            day_type = 1
        else:
            day_type = 2

        bins[(day_type, ts.hour)].append(i)

    selected_indices = []
    for indices in bins.values():
        if len(indices) <= MAX_SAMPLES_PER_PORTION:
            selected_indices.extend(indices)
        else:
            selected_indices.extend(
                np.random.choice(indices, MAX_SAMPLES_PER_PORTION, replace=False)
            )

    selected_indices = np.array(sorted(selected_indices))
    return (
        X[selected_indices],
        Y[selected_indices],
        C[selected_indices],
        T[selected_indices],
    )


def load_shapes(agency_id: str, path="data/agency{agency_id}_shapes.json"):
    # incarca coord punctelor de pe trasee
    route_points_by_id = defaultdict(list)
    for sp in json.load(open(path.format(agency_id=agency_id))):
        route_points_by_id[sp["shape_id"]].append(sp)
    shapes = {}

    for shape_id, route_points in route_points_by_id.items():
        route_points.sort(key=lambda x: x["shape_pt_sequence"])
        coords = [(sp["shape_pt_lat"], sp["shape_pt_lon"]) for sp in route_points]
        cumulative_distances = [0.0]
        for a, b in zip(coords, coords[1:]):
            cumulative_distances.append(
                cumulative_distances[-1] + haversine(a[0], a[1], b[0], b[1])
            )
        shapes[shape_id] = {"pts": coords, "cum_dist": cumulative_distances}

    logger.info("loaded %d shapes, agency %s", len(shapes), agency_id)
    return shapes


def load_stops(
    agency_id: str,
    path_trip_stops="data/agency{agency_id}_trip_stops.json",
    path_stops="data/agency{agency_id}_stops.json",
):
    # incarca coord statiilor si legaturile lor cu rutele
    stop_positions = {
        str(s["stop_id"]): (s["stop_lat"], s["stop_lon"])
        for s in json.load(open(path_stops.format(agency_id=agency_id)))
    }

    trips_to_stops = defaultdict(list)
    for ts in json.load(open(path_trip_stops.format(agency_id=agency_id))):
        trips_to_stops[ts["trip_id"]].append((str(ts["stop_id"]), ts["stop_sequence"]))
    for tid in trips_to_stops:
        trips_to_stops[tid].sort(key=lambda x: x[1])  # sortam dupa secventa pe ruta

    logger.info("loaded stops for %d trips, agency %s", len(trips_to_stops), agency_id)
    return stop_positions, {
        tid: [sid for sid, _ in stop_sequence_list]
        for tid, stop_sequence_list in trips_to_stops.items()
    }


def project_route(lat, lon, shape_data, start_index=0):
    # proiecteaza un punct pe ruta, returnand distanta cumulata aproximativa, si daca nu e aproape de ruta, returneaza None
    # practic incearca sa-i dea snap la ruta ca de obicei gps-ul din ele nu e perfect precis, in rest merge din punct in punct
    # start index e pentru optimizare, ca sa nu caute de la inceput tot timpul

    # index, distanta, proportia pe segment
    best = (None, float("inf"), 0.0)

    route_points, cumulative_distances = shape_data["pts"], shape_data["cum_dist"]

    # de siguranta
    if start_index >= len(route_points) - 1:
        start_index = len(route_points) - 2

    for i in range(start_index, len(route_points) - 1):
        p1, p2 = route_points[i], route_points[i + 1]
        dx, dy = p2[0] - p1[0], p2[1] - p1[1]

        # daca p1 si p2 sunt identice
        if dx == 0 and dy == 0:
            t, proj = 0, p1

        else:
            # proiectia punctului pe segmentul p1 p2
            dot = (lat - p1[0]) * dx + (lon - p1[1]) * dy
            t = max(0, min(1, dot / (dx * dx + dy * dy)))
            proj = (p1[0] + dx * t, p1[1] + dy * t)

        d = haversine(lat, lon, proj[0], proj[1])
        if d < best[1]:
            best = (i, d, t)

        # asta optimizeaza si face, la rutele care se intorc prin aceleasi statii
        # diferentierea (impreuna cu ideea de start index) intre ele posibila
        if d < 10:
            break

    idx, dist_off, t = best

    # daca nu s-a gasit un punct apropiat de ruta, returneaza None
    if idx is None or dist_off > MAX_OFFROUTE_DIST:
        return None

    # returneaza distanta cumulata pe ruta pana la punctul proiectat (suma partiala + proportia pe segment * lungimea segmentului)
    cum_dist = cumulative_distances[idx] + t * (
        cumulative_distances[idx + 1] - cumulative_distances[idx]
    )

    return (cum_dist, idx)


def split_journeys(history):
    if not history:
        return

    # separa istoricul vehiculului in calatorii distincte
    history.sort(key=lambda x: (x["label"], x["ts"]))
    curr = [history[0]]

    # vrem sa ne raportam la ultimul punct pastrat
    last_kept = history[0]

    # parcurgem istoricul unui vehicul dupa timestamp (luam dupa label ca de obicei nu se schimba in timpul unei zile)
    for nxt in history[1:]:
        dt = (nxt["ts"] - last_kept["ts"]).total_seconds()

        if last_kept["label"] != nxt["label"] or dt > MAX_GAP_SECONDS:
            if curr:
                yield curr

            curr = [nxt]
            last_kept = nxt
            continue

        # daca s-a updatat si a trecut un timp rezonabil(ca sa nu le luam pe cele fantoma), adaugam la calatoria asta
        if dt >= MIN_GAP_SECONDS:
            curr.append(nxt)
            last_kept = nxt

    # cu return ar fi lista mare pt RAM
    if curr:
        yield curr


def build_history_db(agency_id: str, db_path: str):
    con = sqlite3.connect(db_path)
    con.execute(
        """
        CREATE TABLE IF NOT EXISTS records (
            trip_id TEXT,
            label   TEXT,
            ts      TEXT,
            lat     REAL,
            lon     REAL
        )
    """
    )
    con.execute("CREATE INDEX IF NOT EXISTS idx_trip ON records(trip_id)")

    for path in VEHICLE_TRAIN_DATA_PATHS:
        file_path = os.path.join(path, f"agency{agency_id}_data_vehicles.jsonl")

        if not os.path.exists(file_path):
            logger.warning(
                "no vehicle data found for agency %s in path %s, skip",
                agency_id,
                path,
            )
            continue

        with open(file_path, encoding="utf-8") as f:
            buf = []

            for line_nr, line in enumerate(f, 1):
                line = line.strip()

                if not line:
                    continue

                try:
                    snap = json.loads(line)
                except json.JSONDecodeError:
                    logger.warning(
                        "invalid JSONL at %s line %d, skip",
                        file_path,
                        line_nr,
                    )
                    continue

                for v in snap.get("data", []):
                    if (
                        v.get("trip_id")
                        and v.get("label")
                        and v.get("latitude")
                        and v.get("longitude")
                        and v.get("timestamp")
                        and v.get("speed") is not None
                    ):
                        try:
                            ts = datetime.fromisoformat(
                                v["timestamp"].replace("Z", "+00:00")
                            )
                        except ValueError:
                            logger.warning(
                                "invalid timestamp %r at %s line %d, skip",
                                v.get("timestamp"),
                                file_path,
                                line_nr,
                            )
                            continue

                        buf.append(
                            (
                                v["trip_id"],
                                v["label"],
                                ts.isoformat(),
                                v["latitude"],
                                v["longitude"],
                            )
                        )

                if len(buf) >= 50_000:
                    con.executemany("INSERT INTO records VALUES (?,?,?,?,?)", buf)
                    con.commit()
                    buf.clear()

            if buf:
                con.executemany("INSERT INTO records VALUES (?,?,?,?,?)", buf)
                con.commit()

    con.close()


if __name__ == "__main__":
    os.makedirs("models", exist_ok=True)

    for agency_id in AGENCY_IDS:
        logger.info("processing agency %s", agency_id)

        # incarcam punctele de pe trasee, statiile si legaturile lor cu rutele
        shapes = load_shapes(agency_id)
        stop_loc, trips_to_stops = load_stops(agency_id)

        stop_to_trips = defaultdict(set)
        stop_dists_by_trip = defaultdict(dict)
        stop_dists_by_trip_api = defaultdict(lambda: defaultdict(list))

        logger.info("loading vehicle data for agency %s", agency_id)

        db_path = os.path.join(current_folder, f"history_agency{agency_id}.db")

        if os.path.exists(db_path):
            os.remove(db_path)

        build_history_db(agency_id, db_path)

        con = sqlite3.connect(db_path)

        trip_ids = [
            r[0] for r in con.execute("SELECT DISTINCT trip_id FROM records").fetchall()
        ]

        logger.info("loaded history for %d trips, agency %s", len(trip_ids), agency_id)

        for trip_id in trip_ids:
            rows = con.execute(
                "SELECT label, ts, lat, lon FROM records WHERE trip_id = ?",
                (trip_id,),
            ).fetchall()

            recs = [
                {
                    "label": r[0],
                    "ts": datetime.fromisoformat(r[1]),
                    "lat": r[2],
                    "lon": r[3],
                }
                for r in rows
            ]

            shape_data = shapes.get(trip_id)
            stops = trips_to_stops.get(trip_id)
            if not shape_data or not stops:
                continue

            # calculam distantele proiectate pentru fiecare statie
            # trebuie sa retinem cum parcurgem ruta pentru ca e posibil ca doua statii sa fie foarte
            # apropiate ca distanta in linie dreapta, dar sa fie de fapt departe pe traseu
            last_idx = 0
            for sid in stops:
                if sid not in stop_loc:
                    continue

                # uneori apare in spate din cauza erorii gps
                search_start_index = max(0, last_idx - 2)
                pr = project_route(
                    *stop_loc[sid], shape_data, start_index=search_start_index
                )

                if pr is None:
                    continue

                cum_dist, idx = pr
                if cum_dist is None or idx is None:
                    continue

                if idx >= last_idx:
                    last_idx = idx
                    stop_dists_by_trip[trip_id][sid] = cum_dist
                    stop_dists_by_trip_api[trip_id][sid].append(cum_dist)
                    stop_to_trips[sid].add(trip_id)

            # in X vom pune distanta proiectata pe ruta, distanta pana la statia curenta
            # in Y vom pune timpul estimat de sosire
            # in C vom pune indicele de congestie in functie de ora si ziua sapt
            # in T vom pune timestampul real, pentru ca ponderarea sa se faca pe momente cat mai "asemanatoare"
            X, Y, C, T = [], [], [], []

            # sortare dupa distanta pe ruta, pentru a putea merge in ordine si sa nu cautam mereu de la inceput statia urmatoare
            sorted_stop_items = sorted(
                stop_dists_by_trip[trip_id].items(),
                key=lambda item: item[1],
            )

            if not sorted_stop_items:
                continue

            sorted_stop_ids = [sid for sid, _ in sorted_stop_items]
            sorted_stop_dists = [dist for _, dist in sorted_stop_items]

            for journey in split_journeys(recs):
                if len(journey) <= MIN_JOURNEY_POINTS:
                    continue

                filtered = []
                # filtram punctele stationare de la capete, vehicule fantoma

                for pt in journey:
                    pr = project_route(pt["lat"], pt["lon"], shape_data)

                    if pr is None:
                        continue

                    projected_dist, idx = pr

                    if projected_dist is None or idx is None:
                        continue

                    # aici practic verificam vehiculul aprox stationar aproape de capetele rutei
                    end_dist = shape_data["cum_dist"][-1] - projected_dist
                    if filtered:
                        prev = filtered[-1]
                        if (
                            haversine(prev["lat"], prev["lon"], pt["lat"], pt["lon"])
                            < MIN_STATIONARY_DIST
                        ):
                            if (
                                projected_dist < STOP_ENDS_RADIUS
                                or end_dist < STOP_ENDS_RADIUS
                            ):
                                continue

                    pt["_pd"] = projected_dist
                    filtered.append(pt)

                # generam date de invatare pentru ETA
                # timpul adevarat de sosire il calculam mergand prin calatorie si cautand urmatorul
                # punct apropiat de statia curenta scadem o interpolare a timpului daca a depasit

                # mai intai detectam momentul de sosire in fiecare statie
                if len(filtered) < 2:
                    continue

                arrival_by_stop = {}

                for prev_pt, next_pt in zip(filtered, filtered[1:]):
                    prev_pd = prev_pt["_pd"]
                    next_pd = next_pt["_pd"]

                    delta_pd = next_pd - prev_pd
                    dt_seconds = (next_pt["ts"] - prev_pt["ts"]).total_seconds()

                    if delta_pd <= MIN_PROJECTED_PROGRESS_METERS:
                        continue

                    # nu interpolam peste diferente temporale dubioase
                    if dt_seconds <= 0 or dt_seconds > MAX_GAP_SECONDS:
                        continue

                    projected_speed = delta_pd / dt_seconds

                    # un fallback de siguranta pt erori de gps
                    if projected_speed > MAX_PROJECTED_SPEED_MPS:
                        continue

                    # cautam doar statiile a caror distanta pe ruta
                    # a fost traversata intre prev_pt si next_pt
                    left = bisect_right(sorted_stop_dists, prev_pd)
                    right = bisect_right(sorted_stop_dists, next_pd)

                    for stop_idx in range(left, right):
                        sid = sorted_stop_ids[stop_idx]

                        if sid in arrival_by_stop:
                            continue

                        stop_dist = sorted_stop_dists[stop_idx]

                        ratio = (stop_dist - prev_pd) / delta_pd

                        # tot fallback
                        if not (0.0 <= ratio <= 1.0):
                            continue

                        arr = prev_pt["ts"] + timedelta(seconds=dt_seconds * ratio)

                        arrival_by_stop[sid] = arr

                # pentru statiile pe care interpolarea nu le-a prins, mult mai probabil sa se intample mai la final de ruta
                last_third = filtered[len(filtered) * 2 // 3 :]

                for stop_idx in range(len(sorted_stop_ids) - 1, -1, -1):
                    sid = sorted_stop_ids[stop_idx]
                    if sid in arrival_by_stop:
                        break

                    stop_coord = stop_loc[sid]

                    for pt in reversed(last_third):
                        if (
                            haversine(
                                pt["lat"], pt["lon"], stop_coord[0], stop_coord[1]
                            )
                            < MAX_OFFROUTE_DIST
                        ):
                            arrival_by_stop[sid] = pt["ts"]
                            break

                for pt in filtered:
                    projected_dist = pt["_pd"]

                    first_future_stop_idx = bisect_right(
                        sorted_stop_dists,
                        projected_dist,
                    )

                    for stop_idx in range(
                        first_future_stop_idx,
                        len(sorted_stop_items),
                    ):
                        sid = sorted_stop_ids[stop_idx]
                        stop_dist = sorted_stop_dists[stop_idx]

                        arr = arrival_by_stop.get(sid)

                        if arr is None or arr <= pt["ts"]:
                            continue

                        eta = (arr - pt["ts"]).total_seconds()

                        if 0 < eta <= MAX_ETA_SECONDS:
                            X.append(
                                [
                                    projected_dist,
                                    stop_dist - projected_dist,
                                ]
                            )
                            Y.append(eta)

                            # timestampul ramane UTC in pt["ts"],
                            # dar pt features locale convertim la ora Romaniei
                            local_ts = pt["ts"].astimezone(LOCAL_TZ)

                            congestion_index = get_timestamp_congestion_index(local_ts)

                            C.append(congestion_index)
                            T.append(local_ts)

            # verificam daca sunt destule puncte pentru a salva modelul
            if len(X) < MIN_SAMPLES_PER_TRIP:
                logger.warning(
                    "skipping trip %s: only %d points, agency %s",
                    trip_id,
                    len(X),
                    agency_id,
                )
                continue

            X, Y, C, T = map(np.array, (X, Y, C, T))

            # ideea aici e ca avem (imaginar) 72 de "portiuni" , 3 tipuri de zi X 24 de ore, si daca avem peste un prag de puncte, ales
            # astfel incat ar reiesi ca cel putin una este prea populata, reducem din portiunile prea populate
            # nu avem nevoie de zeci de mii de puncte pentru (de ex.) miercuri la ora 19
            if len(X) > MAX_SAMPLES_PER_PORTION * 72:
                X, Y, C, T = subsample(X, Y, C, T)

            # antrenam un knn, salvam
            nbrs = NearestNeighbors(n_neighbors=NEIGHBORS_CONSIDERED).fit(X)

            pickle.dump(
                {"nbrs": nbrs, "X": X, "y": Y, "c": C, "t": T},
                open(f"models/agency{agency_id}_{trip_id}_knn.pkl", "wb"),
            )

            logger.info(
                "saved model %s with %d route_points, agency %s",
                trip_id,
                len(X),
                agency_id,
            )

        con.close()
        os.remove(db_path)

        # salvam datele auxiliare pt lookup-uri O(1)

        with open(f"models/agency{agency_id}_stop_to_trips.pkl", "wb") as f:
            pickle.dump(dict(stop_to_trips), f)
        with open(f"models/agency{agency_id}_stop_dists_by_trip.pkl", "wb") as f:
            pickle.dump(dict(stop_dists_by_trip_api), f)

        logger.info(
            "done: %d stops->trips, %d trips->stop-dists, agency %s",
            len(stop_to_trips),
            len(stop_dists_by_trip),
            agency_id,
        )
