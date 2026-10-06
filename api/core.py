import random
import os
import logging
from zoneinfo import ZoneInfo
from dotenv import load_dotenv
from pathlib import Path
import sys
import uuid
from collections import OrderedDict
import asyncio
import json
import pickle


from preprocess import (
    load_shapes,
    load_stops,
)


load_dotenv()

gunicorn_error_logger = logging.getLogger("gunicorn.error")

logger = logging.getLogger(__name__)

if "gunicorn" in sys.modules:
    logger.handlers = gunicorn_error_logger.handlers
    logger.setLevel(gunicorn_error_logger.level)
else:
    # local dev
    logging.basicConfig(level=logging.INFO)
    logger.setLevel(logging.INFO)


LOCAL_TZ = ZoneInfo("Europe/Bucharest")


MONGO_URL = os.getenv("MONGO_URL") or "mongo_fallback_url"
DEV_FRONTEND_URL = os.getenv("DEV_FRONTEND_URL") or "http://localhost:3000"
DB_NAME = os.getenv("DB_NAME") or "db_fallback_name"
CSV_DIR = Path("csv")
OPENROUTER_API_KEY = os.getenv("OPENROUTER_API_KEY")
OPENROUTER_MODEL = os.getenv("OPENROUTER_MODEL", "openai/gpt-4o-mini")


AGENCY_IDS = ["1", "2", "4", "6", "10"]
EXTERNAL_TIMETABLES_AGENCY_IDS = ["1", "4", "6", "10"]

VEHICLE_REFRESH_SECONDS = 20
VEHICLE_CACHE_TTL = 120
GHOST_STATIONARY_SECONDS = 15 * 60  # stationar 15 min => fantoma
GHOST_MAX_COORD_CHANGE = 0.0005  # aprox 40 m
WORKER_ID = uuid.uuid4().hex

MIN_VALID_EXTERNAL_TIMETABLE_SIZE = 100  # bytes

UNKNOWN_ETA_MINUTES = 999

MAX_CACHED_MODELS = 40

# cache local pt modele, statii, rute, distante
models_cache = OrderedDict()
models_cache_lock = asyncio.Lock()
shapes = {}
stop_locs = {}
trip_stops = {}
stop_to_trips = {}
stop_dists_by_trip = {}
stop_distances = {}
stop_names: dict[str, dict[str, str]] = {}
route_short_names: dict[str, dict[str, str]] = {}


def get_random_api_key():
    idx = random.randint(1, 5)
    return os.getenv(f"API_KEY_{idx}")


def init_data():
    # incarcam formele, statiile si fisierele .pkl

    global shapes, stop_locs, trip_stops, stop_to_trips, stop_dists_by_trip, stop_distances

    for agency_id in AGENCY_IDS:
        logger.info("Loading shapes for agency %s...", agency_id)
        shapes[agency_id] = load_shapes(agency_id)

        logger.info("Loading stops & trip sequences for agency %s...", agency_id)
        stop_locs[agency_id], trip_stops[agency_id] = load_stops(agency_id)

        with open(f"data/agency{agency_id}_stops.json", encoding="utf-8") as f:
            stop_names[agency_id] = {
                str(s["stop_id"]): s["stop_name"] for s in json.load(f)
            }

        with open(f"data/agency{agency_id}_routes.json", encoding="utf-8") as f:
            route_short_names[agency_id] = {
                str(r["route_id"]): r["route_short_name"] for r in json.load(f)
            }

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


async def get_model(agency_id: str, trip_id: str):
    # intoarce modelul kNN pt un anumit trip_id (din cache sau il incarca)
    key = (agency_id, trip_id)

    async with models_cache_lock:
        if key in models_cache:
            models_cache.move_to_end(key)
            return models_cache[key]

    path = f"models/agency{agency_id}_{trip_id}_knn.pkl"
    try:
        with open(path, "rb") as f:
            m = pickle.load(f)
    except FileNotFoundError:
        return None

    async with models_cache_lock:
        models_cache[key] = m
        if len(models_cache) > MAX_CACHED_MODELS:
            models_cache.popitem(last=False)
    return m
