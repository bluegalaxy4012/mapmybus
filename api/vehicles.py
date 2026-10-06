import asyncio
import json
import os
from datetime import datetime

import httpx
from redis.asyncio import Redis

from core import (
    logger,
    LOCAL_TZ,
    AGENCY_IDS,
    WORKER_ID,
    VEHICLE_REFRESH_SECONDS,
    VEHICLE_CACHE_TTL,
    GHOST_STATIONARY_SECONDS,
    GHOST_MAX_COORD_CHANGE,
    stop_locs,
    stop_names,
    stop_distances,
    get_random_api_key,
)
from weather import refresh_weather


async def refresh_loop(redis: Redis):
    while True:
        try:
            # doar un worker face fetch-ul
            got_lock = await redis.set(
                "lock:vehicle_refresh",
                WORKER_ID,
                nx=True,
                ex=(VEHICLE_REFRESH_SECONDS * 9) // 10,
            )

            if got_lock:
                for agency_id in AGENCY_IDS:
                    try:
                        await refresh_agency_vehicles(redis, agency_id)
                    except Exception as e:
                        logger.error("refresh failed for agency %s: %s", agency_id, e)

            # weather se face in afara lockului, weather_state e per-process
            # si fiecare worker isi tine propriul state
            await refresh_weather()
        except asyncio.CancelledError:
            raise
        except Exception as e:
            logger.error("refresh_loop error: %s", e)

        await asyncio.sleep(VEHICLE_REFRESH_SECONDS)


async def refresh_agency_vehicles(redis: Redis, agency_id: str):
    headers = {
        "X-Agency-Id": agency_id,
        "Accept": "application/json",
        "X-API-KEY": get_random_api_key(),
    }
    async with httpx.AsyncClient() as client:
        r = await client.get(
            f"{os.getenv('BASE_URL')}/vehicles", headers=headers, timeout=10
        )
    if r.status_code != 200:
        logger.warning("upstream %s for agency %s", r.status_code, agency_id)
        return

    now = datetime.now(LOCAL_TZ)
    valid = []

    for v in r.json():
        trip_id, lat, lon = v.get("trip_id"), v.get("latitude"), v.get("longitude")
        label, ts = v.get("label"), v.get("timestamp")

        if not (trip_id and lat is not None and lon is not None and label and ts):
            continue

        vts = datetime.fromisoformat(ts.replace("Z", "+00:00")).astimezone(LOCAL_TZ)
        if (now - vts).total_seconds() > 180:
            continue
        stops_ids = list(stop_distances.get(agency_id, {}).get(trip_id, {}).keys())
        if not stops_ids:
            continue
        try:
            first_stop = stop_locs[agency_id][stops_ids[0]]
            last_stop = stop_locs[agency_id][stops_ids[-1]]
        except KeyError:
            continue
        v["first_stop_lat"], v["first_stop_lon"] = first_stop
        v["last_stop_lat"], v["last_stop_lon"] = last_stop
        v["first_stop_name"] = stop_names[agency_id].get(stops_ids[0], "")
        v["last_stop_name"] = stop_names[agency_id].get(stops_ids[-1], "")
        v["is_ghost"] = False

        valid.append(v)

    await _update_ghosts(redis, agency_id, valid, now)

    await redis.set(f"vehicles:{agency_id}", json.dumps(valid), ex=VEHICLE_CACHE_TTL)


async def _update_ghosts(redis: Redis, agency_id: str, vehicles: list, now: datetime):
    # ghost = nu s-a miscat mai mult de X  metri de Y minute
    ts_now = now.timestamp()
    keys = [f"ghost:{agency_id}:{v['label']}".strip() for v in vehicles]

    pipe = redis.pipeline()
    for k in keys:
        pipe.hgetall(k)
    states = await pipe.execute()
    pipe = redis.pipeline()

    for v, k, st in zip(vehicles, keys, states):
        lat, lon = float(v["latitude"]), float(v["longitude"])
        if st:
            moved = (
                abs(lat - float(st["lat"])) + abs(lon - float(st["lon"]))
                > GHOST_MAX_COORD_CHANGE
            )
            since = ts_now if moved else float(st["since"])
        else:
            since = ts_now
        v["is_ghost"] = (ts_now - since) >= GHOST_STATIONARY_SECONDS
        pipe.hset(k, mapping={"lat": lat, "lon": lon, "since": since})
        pipe.expire(k, GHOST_STATIONARY_SECONDS * 2)

    await pipe.execute()


async def _cached_vehicle_positions(redis: Redis, agency_id: str):
    cached = await redis.get(f"vehicles:{agency_id}")
    vehicles = json.loads(cached or "[]")
    return [
        {
            "trip_id": v["trip_id"],
            "lat": v["latitude"],
            "lon": v["longitude"],
            "label": v.get("label"),
            "ts": v.get("timestamp"),
        }
        for v in vehicles
        if not v.get("is_ghost")
    ]
