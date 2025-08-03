import requests
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

def fetch_routes():
    r = requests.get(f"{BASE_URL}/routes", headers=HEADERS)
    if r.status_code == 200:
        return r.json()
    print(f"Failed to fetch routes: {r.status_code}")
    return []

def fetch_stops():
    r = requests.get(f"{BASE_URL}/stops", headers=HEADERS)
    if r.status_code == 200:
        return r.json()
    print(f"Failed to fetch stops: {r.status_code}")
    return []

def fetch_trip_stops():
    r = requests.get(f"{BASE_URL}/stop_times", headers=HEADERS)
    if r.status_code == 200:
        return r.json()
    print(f"Failed to fetch trip stops: {r.status_code}")
    return []

def main():
    with open('data/routes.json', 'w') as f:
        routes = fetch_routes()
        json.dump(routes, f)
        print(f"Saved {len(routes)} routes to routes.json")
    with open('data/stops.json', 'w') as f:
        stops = fetch_stops()
        json.dump(stops, f)
        print(f"Saved {len(stops)} stops to stops.json")
    with open('data/trip_stops.json', 'w') as f:
        trip_stops = fetch_trip_stops()
        json.dump(trip_stops, f)
        print(f"Saved {len(trip_stops)} trip stops to trip_stops.json")

if __name__ == "__main__":
    main()