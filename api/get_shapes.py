import requests
import time
from concurrent.futures import ThreadPoolExecutor
from dotenv import load_dotenv
import os
import json

load_dotenv()

BASE_URL = os.getenv("BASE_URL")
HEADERS = {
    "X-Agency-Id": "2",
    "Accept": "application/json",
    "X-API-KEY": os.getenv("DEV_API_KEY")
}

def fetch_stop_times():
    r = requests.get(f"{BASE_URL}/stop_times", headers=HEADERS)
    if r.status_code == 200:
        return r.json()
    print(f"Failed to fetch stop_times: {r.status_code}")
    return []

def fetch_shapes_for_trip(trip_id):
    time.sleep(0.7)
    r = requests.get(f"{BASE_URL}/shapes", headers=HEADERS, params={"shape_id": trip_id})
    if r.status_code == 200:
        return [{
            "shape_id": trip_id,
            "shape_pt_lat": p["shape_pt_lat"],
            "shape_pt_lon": p["shape_pt_lon"],
            "shape_pt_sequence": p["shape_pt_sequence"]
        } for p in r.json()]
    print(f"Failed to fetch shapes for trip_id {trip_id}: {r.status_code}")
    return []

def main():
    stop_times = fetch_stop_times()
    trip_ids = set(st['trip_id'] for st in stop_times)
    all_shapes = []
    
    # anti-429
    with ThreadPoolExecutor(max_workers=2) as executor:
        futures = [executor.submit(fetch_shapes_for_trip, tid) for tid in trip_ids]
        for future in futures:
            points = future.result()
            if points:
                all_shapes.extend(points)
    with open('data/shapes.json', 'w') as f:
        json.dump(all_shapes, f)
    print(f"Saved {len(all_shapes)} shape points to shapes.json")

if __name__ == "__main__":
    main()

