from contextlib import asynccontextmanager
from datetime import datetime
from functools import lru_cache
from typing import List
import asyncio

import httpx
import redis.asyncio as aioredis
from fastapi import FastAPI, HTTPException, Query, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse, Response
from pymongo import MongoClient

from preprocess import ArrivalStatus
from weather import get_cached_weather

from core import (
    logger,
    LOCAL_TZ,
    MONGO_URL,
    DB_NAME,
    DEV_FRONTEND_URL,
    CSV_DIR,
    AGENCY_IDS,
    EXTERNAL_TIMETABLES_AGENCY_IDS,
    MIN_VALID_EXTERNAL_TIMETABLE_SIZE,
    UNKNOWN_ETA_MINUTES,
    models_cache,
    stop_locs,
    trip_stops,
    stop_to_trips,
    stop_names,
    route_short_names,
    init_data,
)
from vehicles import (
    refresh_loop,
    refresh_agency_vehicles,
    _cached_vehicle_positions,
)

from predictions import get_prediction, compute_arrivals, get_eta_message


@asynccontextmanager
async def lifespan(app: FastAPI):
    # pentru distribuire la toti workerii
    app.state.redis = aioredis.Redis(host="localhost", port=6379, decode_responses=True)
    app.state.mongo = MongoClient(MONGO_URL, maxPoolSize=20)
    app.state.db = app.state.mongo[DB_NAME]

    logger.info("Application startup: Initializing data...")
    init_data()

    task = asyncio.create_task(refresh_loop(app.state.redis))
    yield

    task.cancel()
    try:
        await task
    except asyncio.CancelledError:
        pass

    logger.info("Application shutdown: Clearing models cache...")

    models_cache.clear()
    app.state.mongo.close()
    await app.state.redis.aclose()


app = FastAPI(lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        DEV_FRONTEND_URL,
        "https://mapmybus.40004444.xyz",
    ],
    allow_credentials=False,
    allow_methods=["GET", "OPTIONS", "POST"],
    allow_headers=["*"],
)


@app.get("/weather/{agency_id}")
async def get_weather(agency_id: str):
    if agency_id not in AGENCY_IDS:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST)

    return await get_cached_weather(agency_id)


@app.get("/vehicles/{agency_id}")
async def get_vehicles(agency_id: str):
    if agency_id not in AGENCY_IDS:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST)

    cached = await app.state.redis.get(f"vehicles:{agency_id}")

    if cached is None:
        await refresh_agency_vehicles(app.state.redis, agency_id)
        cached = await app.state.redis.get(f"vehicles:{agency_id}")

    return Response(content=cached or "[]", media_type="application/json")


# pentru aproximat urmatoarele sosiri la o statie
@app.get("/arrivals/{agency_id}")
async def get_arrivals_for_stop(agency_id: str, stop_id: str):
    logger.info("fetching arrivals for agency %s, stop %s", agency_id, stop_id)

    if agency_id not in AGENCY_IDS:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST)

    positions = await _cached_vehicle_positions(
        app.state.redis, agency_id
    )  # deja exclude fantomele
    return await compute_arrivals(agency_id, stop_id, positions)


@app.get("/widgets/{agency_id}")
async def get_widget_stops(agency_id: str, stop_id: str):
    if agency_id not in AGENCY_IDS:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST)

    # nu supraincarcam widgetul
    predictions = await get_arrivals_for_stop(agency_id, stop_id)
    next_five_arrivals = predictions[:5]

    formatted_arrivals = []

    for arrival in next_five_arrivals:
        formatted_arrivals.append(
            {
                "route_short_name": route_short_names.get(agency_id, {}).get(
                    arrival["trip_id"].split("_")[0], ""
                ),
                "eta_message": get_eta_message(arrival["predicted_eta_minutes"]),
            }
        )

    return {
        "stop_name": stop_names.get(agency_id, {}).get(stop_id, ""),
        "arrivals": formatted_arrivals,
        "ts": datetime.now(LOCAL_TZ).isoformat(),
    }


@app.get("/widgets/{agency_id}/apiwidget/{stop_id}")
async def get_apiwidget(
    agency_id: str,
    stop_id: str,
):
    if agency_id not in AGENCY_IDS:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST)

    predictions = await get_arrivals_for_stop(
        agency_id,
        stop_id,
    )

    next_five_arrivals = predictions[:5]

    stop_name = stop_names.get(agency_id, {}).get(stop_id, "")

    rows = [
        {
            "key": stop_name or stop_id,
            "color": "main",
        }
    ]

    for arrival in next_five_arrivals:
        route = route_short_names.get(agency_id, {}).get(
            arrival["trip_id"].split("_")[0],
            "",
        )

        eta = get_eta_message(arrival["predicted_eta_minutes"])

        rows.append(
            {
                "key": route or "?",
                "value": eta or "?",
            }
        )

    rows.append(
        {
            "key": "",
        }
    )

    rows.append(
        {
            "key": "Actualizat",
            "value": datetime.now(LOCAL_TZ).strftime("%H:%M"),
        }
    )

    return rows


# aproximari eta pentru o locatie de vehicul primita si statiile, normal, de pe ruta sa
@app.get("/predict/{agency_id}")
async def predict_endpoint(
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

    # unele trasee trec prin aceeasi statie de mai multe ori (de ex rute ciclice), deci ca sa transmitem la a cata trecere printr-o
    # anumita statie suntem ,altfel o sa suprascriem timpii pentru o statie cu a doua trecere prin ea
    seen_stop_counts = {}

    for stop_id in stop_ids:
        appearance_index = seen_stop_counts.get(stop_id, 0)
        seen_stop_counts[stop_id] = appearance_index + 1

        try:
            eta_s, msg = await get_prediction(
                agency_id,
                trip_id,
                lat,
                lon,
                stop_id,
                appearance_index,
            )
        except HTTPException as e:
            results.append(
                {
                    "trip_id": trip_id,
                    "stop_id": stop_id,
                    "predicted_eta_minutes": UNKNOWN_ETA_MINUTES,
                    "message": ArrivalStatus.UNKNOWN.value,
                }
            )
            continue
        except Exception as e:
            logger.error("get_prediction failed for %s/%s: %s", trip_id, stop_id, e)
            results.append(
                {
                    "trip_id": trip_id,
                    "stop_id": stop_id,
                    "predicted_eta_minutes": UNKNOWN_ETA_MINUTES,
                    "message": ArrivalStatus.UNKNOWN.value,
                }
            )
            continue

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

    # client = MongoClient(MONGO_URL)
    # db = client[DB_NAME]
    db = app.state.db

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
    # client.close()
    return result


@app.get("/stops/{agency_id}")
def get_stops_for_trip(agency_id: str, trip_id: str = Query(default="")):
    logger.info("fetching stops, agency %s, optional trip %s", agency_id, trip_id)

    if agency_id not in AGENCY_IDS:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST)

    # client = MongoClient(MONGO_URL)
    # db = client[DB_NAME]
    db = app.state.db

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

        # client.close()
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
    # client.close()
    return result


@app.get("/shapes/{agency_id}")
def get_shapes_for_trip(agency_id: str, shape_id: str):
    logger.info("fetching shapes for shape_id %s, agency %s", shape_id, agency_id)

    if agency_id not in AGENCY_IDS:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST)

    # client = MongoClient(MONGO_URL)
    # db = client[DB_NAME]
    db = app.state.db

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
    # client.close()
    return result


@app.get("/trips/{agency_id}")
def get_trip_ids_for_route(agency_id: str, stop_id: str = Query(...)):
    logger.info("fetching trip ids for agency %s, stop_id %s", agency_id, stop_id)

    if agency_id not in AGENCY_IDS:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST)

    trip_ids = stop_to_trips.get(agency_id, {}).get(stop_id, [])

    result = [tid for tid in trip_ids]

    return result


MAX_DIRECT_STOPS = 45


@lru_cache(maxsize=4096)
def _reachable(agency_id: str, stop_id: str):
    trips = stop_to_trips.get(agency_id, {}).get(stop_id, [])
    acc = {}

    for trip_id in trips:
        seq = trip_stops.get(agency_id, {}).get(trip_id)
        if not seq or stop_id not in seq:
            continue
        idx = seq.index(stop_id)
        short = route_short_names.get(agency_id, {}).get(trip_id.split("_")[0], "?")

        for offset, sid in enumerate(seq[idx + 1 :], start=1):
            if offset > MAX_DIRECT_STOPS or sid == stop_id:
                break
            entry = acc.setdefault(sid, {})
            prev = entry.get(short)
            if prev is None or prev["stops_away"] > offset:
                entry[short] = {"stops_away": offset, "trip_id": trip_id}

    out = []
    for sid, routes in acc.items():
        loc = stop_locs.get(agency_id, {}).get(sid)
        if not loc:
            continue
        out.append(
            {
                "stop_id": sid,
                "stop_name": stop_names.get(agency_id, {}).get(sid, sid),
                "stop_lat": loc[0],
                "stop_lon": loc[1],
                "routes": sorted(
                    ({"route_short_name": k, **v} for k, v in routes.items()),
                    key=lambda r: r["stops_away"],
                ),
            }
        )
    out.sort(key=lambda s: s["routes"][0]["stops_away"])
    return out[:80]


@app.get("/reachable/{agency_id}/{stop_id}")
def get_reachable_stops(agency_id: str, stop_id: str):
    if agency_id not in AGENCY_IDS:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST)
    return _reachable(agency_id, stop_id)


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
        # case "8":
        #     # timisoara
        #     return [
        #         f"https://stpt.ro/{route_short_name.lower()}-2/",
        #         f"https://stpt.ro/{route_short_name.lower()}/",
        #     ]
        case "10":
            # constanta
            return [f"https://www.ctbus.ro/#ProgramCurse"]

        case _:
            return []


# intoarce orarul csv pt o ruta+zi
@app.get("/timetables/{agency_id}")
async def get_timetable(
    agency_id: str,
    route_short_name: str = Query(...),
    route_id: str = Query(...),
    day_type: str = Query(..., enum=["lv", "s", "d"]),
):
    logger.info(
        "fetching timetable for agency %s, route %s (%s), day type %s",
        agency_id,
        route_short_name,
        route_id,
        day_type,
    )

    if agency_id not in AGENCY_IDS:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST)

    if day_type not in ["lv", "s", "d"]:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST)

    if "/" in route_short_name or "/" in route_id:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST)

    file_paths = [
        CSV_DIR
        / f"agency{agency_id}_route{route_id}_orar_{route_short_name}_{day_type}.csv",
        CSV_DIR / f"agency{agency_id}_orar_{route_short_name}_{day_type}.csv",
    ]

    for file_path in file_paths:
        if not file_path.exists():
            continue

        return FileResponse(file_path, media_type="text/csv", filename=file_path.name)

    if agency_id in EXTERNAL_TIMETABLES_AGENCY_IDS:
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
