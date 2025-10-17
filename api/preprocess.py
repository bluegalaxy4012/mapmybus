import json
import logging
import os
import pickle
from datetime import datetime, timedelta
from geopy.distance import geodesic
from collections import defaultdict
import numpy as np
from sklearn.neighbors import NearestNeighbors
from traffic_data import get_timestamp_congestion_index
from enum import Enum

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)

timezone_offset = timedelta(hours=3)  # totul e utc in datele colectate, romania are +3h

# constante de configurare
MIN_FEATURES_PER_TRIP = 125
MAX_ETA_SECONDS = 3000
NEIGHBORS_CONSIDERED = 12
MAX_OFFROUTE_DIST = 140
MAX_GAP_SECONDS = 125
MIN_GAP_SECONDS = 9

STOP_ENDS_RADIUS = 120
MIN_JOURNEY_POINTS = 8
MIN_STATIONARY_DIST = 10

AGENCY_IDS = ["1", "2", "4", "6", "8"]

VEHICLE_TRAIN_DATA_PATHS = ["vehicle_jsons/set1", "vehicle_jsons/set2", "vehicle_jsons/set3"]

# clase utile
class ArrivalStatus(str, Enum):
    ARRIVING = "arriving"
    PASSED = "passed"

def load_shapes(agency_id: str, path="data/agency{agency_id}_shapes.json"):
    # incarca coord punctelor de pe trasee
    pts_by_id = defaultdict(list)
    for p in json.load(open(path.format(agency_id=agency_id))):
        pts_by_id[p["shape_id"]].append(p)
    shapes = {}

    for sid, pts in pts_by_id.items():
        pts.sort(key=lambda x: x["shape_pt_sequence"])
        coords = [(p["shape_pt_lat"], p["shape_pt_lon"]) for p in pts]
        cum = [0.0]
        for a, b in zip(coords, coords[1:]):
            cum.append(cum[-1] + geodesic(a, b).meters)
        shapes[sid] = {"pts": coords, "cum_dist": cum}

    logger.info("loaded %d shapes, agency %s", len(shapes), agency_id)
    return shapes

def load_stops(agency_id: str, path_trip_stops="data/agency{agency_id}_trip_stops.json", path_stops="data/agency{agency_id}_stops.json"):
    # incarca coord statiilor si legaturile lor cu rutele
    stop_loc = {str(s["stop_id"]):(s["stop_lat"], s["stop_lon"]) for s in json.load(open(path_stops.format(agency_id=agency_id)))}
    trips_to_stops = defaultdict(list)
    for r in json.load(open(path_trip_stops.format(agency_id=agency_id))):
        trips_to_stops[r["trip_id"]].append((str(r["stop_id"]), r["stop_sequence"]))
    for tid in trips_to_stops:
        trips_to_stops[tid].sort(key=lambda x:x[1])
    logger.info("loaded stops for %d trips, agency %s", len(trips_to_stops), agency_id)
    return stop_loc, {tid:[sid for sid,_ in lst] for tid,lst in trips_to_stops.items()}

def project_route(lat, lon, shp):
    # proiecteaza un punct pe ruta, returnand distanta cumulata aproximativa, si daca nu e aproape de ruta, returneaza None
    # practic incearca sa-i dea snap la ruta ca de obicei gps-ul din ele nu e perfect precis, in rest merge din punct in punct

    # index, distanta, proportia pe segment
    best = (None, float("inf"), 0.0)

    pts, cum = shp["pts"], shp["cum_dist"]
    for i in range(len(pts)-1):
        p1, p2 = pts[i], pts[i+1]
        dx, dy = p2[0]-p1[0], p2[1]-p1[1]

        # daca p1 si p2 sunt identice
        if dx==0 and dy==0:
            t, proj = 0, p1

        else:
            # proiectia punctului pe segmentul p1 p2
            dot = (lat-p1[0])*dx + (lon-p1[1])*dy
            t = max(0, min(1, dot/(dx*dx+dy*dy)))
            proj = (p1[0]+dx*t, p1[1]+dy*t)

        d = geodesic((lat,lon), proj).meters
        if d < best[1]:
            best = (i, d, t)
    idx, dist_off, t = best

    # daca nu s-a gasit un punct apropiat de ruta, returneaza None
    if idx is None or dist_off > MAX_OFFROUTE_DIST:
        return None
    
    # returneaza distanta cumulata pe ruta pana la punctul proiectat (suma partiala + proportia pe segment * lungimea segmentului)
    return cum[idx] + t*(cum[idx+1]-cum[idx])

def split_journeys(history):
    # separa istoricul vehiculului in calatorii distincte
    history.sort(key=lambda x:(x["label"], x["ts"]))
    curr = [history[0]]

    # parcurgem istoricul unui vehicul dupa timestamp (luam dupa label ca de obicei nu se schimba in timpul unei zile)
    for prev, nxt in zip(history, history[1:]):
        dt = (nxt["ts"]-prev["ts"]).total_seconds()

        # daca s-a schimbat eticheta sau a trecut prea mult timp, incepem o noua calatorie
        if prev["label"]!=nxt["label"] or dt>MAX_GAP_SECONDS:
            yield curr
            curr = [nxt]

        # daca s-a updatat si a trecut un timp rezonabil(ca sa nu le luam pe cele fantoma), adaugam la calatoria asta
        elif dt>=MIN_GAP_SECONDS:
            curr.append(nxt)
    
    # asa returnam eficient fiecare calatorie, cu return ar fi lista mare pt RAM
    yield curr

if __name__=="__main__":
    os.makedirs("models", exist_ok=True)

    for agency_id in AGENCY_IDS:
        logger.info("processing agency %s", agency_id)

        # incarcam punctele de pe trasee, statiile si legaturile lor cu rutele
        shapes, stop_loc, trips_to_stops = load_shapes(agency_id), *load_stops(agency_id)
        stop_to_trips = defaultdict(set)
        stop_dists_by_trip = defaultdict(dict)
        history = defaultdict(list)

        logger.info("loading vehicle data for agency %s", agency_id)

        # incarcam datele vehiculelor in miscare, filtrand un pic 

        for path in VEHICLE_TRAIN_DATA_PATHS:
            if not os.path.exists(f"{path}/agency{agency_id}_data_vehicles.json"):
                logger.warning("no vehicle data found for agency %s in path %s, skip", agency_id, path)
                continue

            with open(os.path.join(path, f"agency{agency_id}_data_vehicles.json")) as f:
                for snap in json.load(f):
                    for v in snap.get("data", []):
                        if v.get("trip_id") and v.get("label") and v.get("latitude") and v.get("longitude") and v.get("timestamp") and v.get("speed"):
                            history[v["trip_id"]].append({
                                "label": v["label"],
                                "ts": datetime.fromisoformat(v["timestamp"].replace('Z','')),
                                "lat": v["latitude"],
                                "lon": v["longitude"]
                            })

        logger.info("loaded history for %d trips, agency %s", len(history), agency_id)


        for trip_id, recs in history.items():
            shp = shapes.get(trip_id)
            stops = trips_to_stops.get(trip_id)
            if not shp or not stops:
                continue

            # calculam distantele proiectate pentru fiecare statie
            for sid in stops:
                d = project_route(*stop_loc[sid], shp)
                if d is not None:
                    stop_dists_by_trip[trip_id][sid] = d
                    stop_to_trips[sid].add(trip_id)

            # in X vom pune distanta proiectata pe ruta, distanta pana la statia curenta
            # in Y vom pune timpul estimat de sosire
            # in C vom pune indicele de congestie in functie de ora si ziua sapt
            X, Y, C = [], [], []

            for journey in split_journeys(recs):
                if len(journey) <= MIN_JOURNEY_POINTS:
                    continue

                filtered = []
                # filtram punctele stationare de la capete, vehicule fantoma

                for pt in journey:
                    pd = project_route(pt['lat'], pt['lon'], shp)

                    if pd is None:
                        continue

                    # aici practic verificam vehiculul aprox stationar aproape de capetele rutei
                    end_dist = shp['cum_dist'][-1] - pd
                    if filtered:
                        prev = filtered[-1]
                        if geodesic((prev['lat'], prev['lon']), (pt['lat'], pt['lon'])).meters < MIN_STATIONARY_DIST:
                            if pd < STOP_ENDS_RADIUS or end_dist < STOP_ENDS_RADIUS:
                                continue

                    pt['_pd'] = pd
                    filtered.append(pt)

                # generam date de invatare pentru ETA
                # timpul adevarat de sosire il calculam mergand prin calatorie si cautand urmatorul punct apropiat de statia curenta
                # scadem cateva secunde in caz ca l-a depasit
                for pt in filtered:
                    pd = pt['_pd']

                    for sid, sd in stop_dists_by_trip[trip_id].items():
                        if sd <= pd:
                            continue

                        arr = None

                        for nxt in filtered:
                            if nxt['ts'] > pt['ts']:
                                dstop = geodesic((nxt['lat'], nxt['lon']), stop_loc[sid]).meters
                                if dstop < MAX_OFFROUTE_DIST:
                                    arr = nxt['ts'] - timedelta(seconds=dstop/4)
                                    break

                        if not arr:
                            continue

                        eta = (arr-pt['ts']).total_seconds()

                        if 0 < eta <= MAX_ETA_SECONDS:
                            X.append([pd, sd-pd])
                            Y.append(eta)
                            adjusted_ts = pt['ts'] + timezone_offset

                            # idx, hr = pt['ts'].weekday(), pt['ts'].hour
                            idx, hr = adjusted_ts.weekday(), adjusted_ts.hour

                            congestion_index = get_timestamp_congestion_index(adjusted_ts)
                            C.append(congestion_index)

            # verificam daca sunt destule puncte pentru a salva modelul
            if len(X) < MIN_FEATURES_PER_TRIP:
                logger.warning("skipping trip %s: only %d points, agency %s", trip_id, len(X), agency_id)
                continue

            X, Y, C = map(np.array, (X, Y, C))

            # antrenam un knn, salvam
            nbrs = NearestNeighbors(n_neighbors=NEIGHBORS_CONSIDERED).fit(X)

            pickle.dump({"nbrs": nbrs, "X": X, "y": Y, "c": C},
                        open(f"models/agency{agency_id}_{trip_id}_knn.pkl", "wb"))
            
            logger.info("saved model %s with %d pts, agency %s", trip_id, len(X), agency_id)

        # salvam datele auxiliare pt lookup-uri O(1)

        with open(f"models/agency{agency_id}_stop_to_trips.pkl","wb") as f:
            pickle.dump(dict(stop_to_trips), f)
        with open(f"models/agency{agency_id}_stop_dists_by_trip.pkl","wb") as f:
            pickle.dump(dict(stop_dists_by_trip), f)

        logger.info("done: %d stops->trips, %d trips->stop-dists, agency %s", len(stop_to_trips), len(stop_dists_by_trip), agency_id)

