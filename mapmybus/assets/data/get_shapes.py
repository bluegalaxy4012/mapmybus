import requests
import json
import time
from concurrent.futures import ThreadPoolExecutor
import dotenv
import os



dotenv.load_dotenv()


BASE_URL = "https://api.tranzy.ai/v1/opendata"
HEADERS = {
    "X-Agency-Id": "2",
    "Accept": "application/json",
    "X-API-KEY": os.getenv("API_KEY")
}



def fetch_stop_times():
    response = requests.get(f"{BASE_URL}/stop_times", headers=HEADERS)
    if response.status_code == 200:
        return response.json()
    else:
        print(f"Failed to fetch stop_times: {response.status_code}")
        return []

def fetch_shapes_for_trip(trip_id):
    time.sleep(0.5)
    response = requests.get(f"{BASE_URL}/shapes", headers=HEADERS, params={"shape_id": trip_id})
    if response.status_code == 200:
        points = [
            {
                "shape_id": trip_id,
                "shape_pt_lat": point["shape_pt_lat"],
                "shape_pt_lon": point["shape_pt_lon"],
                "shape_pt_sequence": point["shape_pt_sequence"]
            } for point in response.json()
        ]
        return {"shape_id": trip_id, "points": points}
    else:
        print(f"Failed to fetch shapes for trip_id {trip_id}: {response.status_code}")
        return {"shape_id": trip_id, "points": []}

def main():
    print("Fetching stop_times...")
    stop_times = fetch_stop_times()
    print(f"Fetched {len(stop_times)} stop_times")
    
    trip_ids = set(st['trip_id'] for st in stop_times)
    print(f"Found {len(trip_ids)} unique trip_ids")
    
    all_shapes = []
    print("Fetching shapes...")
    with ThreadPoolExecutor(max_workers=2) as executor:
        futures = [executor.submit(fetch_shapes_for_trip, trip_id) for trip_id in trip_ids]
        for future in futures:
            shape = future.result()
            print(f"Fetched {len(shape['points'])} shape points for trip_id {shape['shape_id']}")
            if shape['points']:
                all_shapes.append(shape)
    
    print(f"Total shapes collected: {len(all_shapes)} with {sum(len(shape['points']) for shape in all_shapes)} points")
    
    with open('shapes.json', 'w') as f:
        json.dump(all_shapes, f, indent=2)
    print("Done, shapes.json")

if __name__ == "__main__":
    main()
