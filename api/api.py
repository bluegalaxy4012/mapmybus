from contextlib import asynccontextmanager
import pickle
from datetime import datetime
import numpy as np
import os
from fastapi import FastAPI, HTTPException, Query, status, Body
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from typing import List
from dotenv import load_dotenv
from pymongo import MongoClient
from pathlib import Path
import httpx
import logging
import random

# importam functii utile si constante din preprocess
from preprocess import (
    load_shapes,
    load_stops,
    project_route as project_onto_route,
    hour_congestion_index,
    weekend_index,
    timezone_offset,
)

# incarcam variabilele din .env
load_dotenv()

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger(__name__)

# configuri din .env
MONGO_URL = os.getenv("MONGO_URL")
DB_NAME = os.getenv("DB_NAME")
CSV_DIR = Path("csv")

AGENCY_IDS = ["1", "2", "4", "6", "8"]

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
    logger.info("Application startup: Initializing data...")
    init_data()
    yield
    logger.info("Application shutdown: Clearing models cache...")
    models_cache.clear()

app = FastAPI(lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:46353",
        # "http://localhost:8901",
        "https://mapmybus.marian.homes",
    ],
    allow_credentials=False,
    allow_methods=["GET", "OPTIONS", "POST"],
    allow_headers=["*"],
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
            agency_id, len(shapes[agency_id]), len(stop_locs[agency_id]), len(trip_stops[agency_id]), len(stop_to_trips[agency_id])
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

    md = get_model(agency_id, trip_id)
    shp = shapes.get(agency_id, {}).get(trip_id)
    if md is None or shp is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No data to make prediction for trip")

    # proiectam vehiculul pe ruta, statia avem deja
    veh_d = project_onto_route(lat, lon, shp)
    stop_d = stop_distances.get(agency_id, {}).get(trip_id, {}).get(stop_id)
    if veh_d is None or stop_d is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Cannot project vehicle or stop onto route")

    # daca vehiculul a trecut deja statia
    if stop_d <= veh_d:
        return 0.0, "Passed"

    # daca e aproape, o sa aproximam ca ajunge in urmatorul minut
    delta = stop_d - veh_d
    if delta < 125:
        return 0.0, "Success"

    # incarcam knn-ul si vecinii
    X, y, c = md["X"], md["y"], md["c"]
    nbrs = md["nbrs"]
    feat = np.array([[veh_d, delta]])
    _, idxs = nbrs.kneighbors(feat)

    # calculam media ponderata a eta-urilor istorice apropiate
    # cele mai apropiate de vehicul au o influenta mai mare, ca poate se schimba cum e drumul
    # imparte cu congestion index ca sa avem un fel de normalizare, si la final o sa inmultim cu congestion index-ul curent
    total_w = 0.0
    total_eta = 0.0

    for i in idxs[0]:
        hist_d = X[i, 0]
        pdist = abs(veh_d - hist_d)

        # print(f"point {i}: hist_d={hist_d}, pdist={pdist}, delta={delta}")


        # functie de calculat ponderea, daca e la mai putin de 50m, pondere mare, intre 50 si 200m mai mica
        # peste 200m mai bine nu consideram ca e inaccurate
        if pdist <= 50:
            w = 0.8 + 0.2 * (1 - pdist / 50)
        elif pdist <= 200:
            w = 0.7 - (0.6 * ((pdist - 50) / 150))
        else:
            continue
        
        # ca sa avem cat e "totalul" de ponderi
        total_w += w
        
        total_eta += (y[i] / c[i]) * w

    if total_w == 0:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No data to make prediction for trip")

    # now pe server e cu 3 ore in urma
    now = datetime.now() + timezone_offset
    cong = hour_congestion_index[now.hour] if now.weekday() < 5 else weekend_index[now.hour]
    eta = (total_eta / total_w) * cong

    return float(eta), "Success"

# pentru aproximat urmatoarele sosiri la o statie
@app.post("/predict/{agency_id}/arrivals/{stop_id}")
def get_arrivals_for_stop(agency_id: str, stop_id: str, vehicle_positions: List[dict] = Body(...), n: int = 5):
    if agency_id not in AGENCY_IDS:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST)

    trips = stop_to_trips.get(agency_id, {}).get(stop_id, [])
    if not trips:
        return []

    relevant = [v for v in vehicle_positions if v["trip_id"] in trips]

    predictions = []
    for v in relevant:
        try:
            eta_s, msg = get_prediction(agency_id, v["trip_id"], v["lat"], v["lon"], stop_id)

            if msg == "Success":
                predictions.append({
                    "trip_id": v["trip_id"],
                    "vehicle_label": v.get("label"),
                    "predicted_eta_minutes": round(eta_s / 60, 2),
                    "message": msg
                })
        except HTTPException:
            continue

    predictions.sort(key=lambda x: x["predicted_eta_minutes"])
    return predictions[:n]

# aproximari eta pentru o locatie de vehicul primita si statiile, normal, de pe ruta sa
@app.get("/predict/{agency_id}")
def predict_endpoint(agency_id: str, trip_id: str, lat: float, lon: float, stop_ids: List[str] = Query(...)):
    logger.info("received prediction request for agency %s, trip %s", agency_id, trip_id)
    
    if agency_id not in AGENCY_IDS:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST)
    
    results = []
    for stop_id in stop_ids:
        eta, message = get_prediction(agency_id, trip_id, lat, lon, stop_id)
        results.append({
            "trip_id": trip_id,
            "stop_id": stop_id,
            "predicted_eta_minutes": round(eta / 60, 2),
            "message": message
        })
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
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No routes found")
    
    result = []
    for route in routes:
        result.append({
            "agency_id": agency_id,
            "route_id": route["route_id"],
            "route_short_name": route["route_short_name"],
            "route_long_name": route["route_long_name"],
            "route_color": route["route_color"],
            "route_type": route["route_type"],
            "route_desc": route.get("route_desc", "")
        })
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
        
        result = [{
            "stop_id": str(stop["stop_id"]),
            "stop_name": stop["stop_name"],
            "stop_lat": stop["stop_lat"],
            "stop_lon": stop["stop_lon"],
            "stop_sequence": 0,
        } for stop in stops]

        client.close()
        return result

    # returnam statiile in ordinea aparitiei pe ruta
    trip_stops = list(db[f"agency{agency_id}_trip_stops"].find({"trip_id": trip_id}).sort("stop_sequence", 1))
    stop_ids = [ts["stop_id"] for ts in trip_stops]
    stops = db[f"agency{agency_id}_stops"].find({"stop_id": {"$in": stop_ids}})
    stop_dict = {s["stop_id"]: s for s in stops}
    
    result = []
    for ts in trip_stops:
        stop = stop_dict.get(ts["stop_id"])
        if stop:
            result.append({
                "stop_id": str(stop["stop_id"]),
                "stop_name": stop["stop_name"],
                "stop_lat": stop["stop_lat"],
                "stop_lon": stop["stop_lon"],
                "stop_sequence": ts["stop_sequence"]
            })
    client.close()
    return result

@app.get("/shapes/{agency_id}")
def get_shapes_for_trip(agency_id: str, shape_id: str):
    logger.info("fetching shapes for shape_id %s, agency %s", shape_id, agency_id)
    
    if agency_id not in AGENCY_IDS:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST)
    
    client = MongoClient(MONGO_URL)
    db = client[DB_NAME]
    
    shapes = db[f"agency{agency_id}_shapes"].find({"shape_id": shape_id}).sort("shape_pt_sequence", 1)
    result = [
        {   
            "shape_id": shape_id,
            "shape_pt_lat": s["shape_pt_lat"],
            "shape_pt_lon": s["shape_pt_lon"],
            "shape_pt_sequence": s["shape_pt_sequence"]
        }
        for s in shapes
    ]
    client.close()
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
        "X-API-KEY": get_random_api_key()
    }
    async with httpx.AsyncClient() as client:
        response = await client.get(f"{os.getenv('BASE_URL')}/vehicles", headers=headers, timeout=10)
    
    if response.status_code == status.HTTP_200_OK:
        return response.json()
    
    raise HTTPException(status_code=response.status_code, detail=response.text)


# intoarce orarul csv pt o ruta+zi
@app.get("/timetables/{agency_id}")
def get_timetable(agency_id: str, route_short_name: str = Query(...), day_type: str = Query(..., enum=["lv", "s", "d"])):
    logger.info("fetching timetable for agency %s, route %s, day type %s", agency_id, route_short_name, day_type)
    
    if agency_id not in AGENCY_IDS:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST)

    if day_type not in ["lv", "s", "d"]:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST)
    
    file_path = CSV_DIR / f"agency{agency_id}_orar_{route_short_name}_{day_type}.csv"
    if not file_path.exists():
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Timetable not found")
    
    return FileResponse(file_path, media_type="text/csv", filename=file_path.name)