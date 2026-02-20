import requests
from dotenv import load_dotenv
import os
import json

load_dotenv()

BASE_URL = os.getenv("BASE_URL")
HEADERS = {
    "X-Agency-Id": "2",
    "Accept": "application/json",
    "X-API-KEY": os.getenv("DEV_API_KEY"),
}

AGENCY_IDS = ["1", "2", "4", "6"]


def fetch_routes(agency_id: str):
    HEADERS["X-Agency-Id"] = agency_id
    r = requests.get(f"{BASE_URL}/routes", headers=HEADERS)
    if r.status_code == 200:
        return r.json()
    print(f"Failed to fetch routes: {r.status_code}")
    return []


def fetch_stops(agency_id: str):
    HEADERS["X-Agency-Id"] = agency_id
    r = requests.get(f"{BASE_URL}/stops", headers=HEADERS)
    if r.status_code == 200:
        return r.json()
    print(f"Failed to fetch stops: {r.status_code}")
    return []


def fetch_trip_stops(agency_id: str):
    HEADERS["X-Agency-Id"] = agency_id
    r = requests.get(f"{BASE_URL}/stop_times", headers=HEADERS)
    if r.status_code == 200:
        return r.json()
    print(f"Failed to fetch trip stops: {r.status_code}")
    return []


def main():
    for agency_id in AGENCY_IDS:
        with open(f"data/agency{agency_id}_routes.json", "w") as f:
            routes = fetch_routes(agency_id)
            json.dump(routes, f)
            print(f"Saved {len(routes)} routes to agency{agency_id}_routes.json")

        with open(f"data/agency{agency_id}_stops.json", "w") as f:
            stops = fetch_stops(agency_id)
            json.dump(stops, f)
            print(f"Saved {len(stops)} stops to agency{agency_id}_stops.json")

        with open(f"data/agency{agency_id}_trip_stops.json", "w") as f:
            trip_stops = fetch_trip_stops(agency_id)
            json.dump(trip_stops, f)
            print(
                f"Saved {len(trip_stops)} trip stops to agency{agency_id}_trip_stops.json"
            )


if __name__ == "__main__":
    main()
