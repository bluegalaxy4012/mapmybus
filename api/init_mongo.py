import pandas as pd
from pymongo import MongoClient, TEXT, ASCENDING
from dotenv import load_dotenv
import os

load_dotenv()

MONGO_URL = os.getenv("MONGO_URL")
DB_NAME = os.getenv("DB_NAME")
ROUTES_FILE = os.getenv("ROUTES_FILE")
STOPS_FILE = os.getenv("STOPS_FILE")
TRIP_STOPS_FILE = os.getenv("TRIP_STOPS_FILE")
SHAPES_FILE = os.getenv("SHAPES_FILE")

def init_mongo():
    client = MongoClient(MONGO_URL)
    db = client[DB_NAME]

    db.stops.drop()
    db.trip_stops.drop()
    db.shapes.drop()
    db.routes.drop()

    if db.routes.count_documents({}) == 0:
        routes_df = pd.read_json(os.getenv("ROUTES_FILE"), dtype={
            'agency_id': str,
            'route_id': int,
            'route_short_name': str,
            'route_long_name': str,
            'route_color': str,
            'route_type': int,
            'route_desc': str
        })

        db.routes.insert_many(routes_df.to_dict('records'))
        db.routes.create_index("route_id", unique=True)
        db.routes.create_index([("agency_id", TEXT), ("route_short_name", TEXT)])
        print(f"inserted routes, count {db.routes.count_documents({})}")


    if db.stops.count_documents({}) == 0:
        stops_df = pd.read_json(STOPS_FILE, dtype={
            'stop_id': int,
            'stop_lat': float,
            'stop_lon': float,
            'stop_name': str
        })
        db.stops.insert_many(stops_df.to_dict('records'))
        db.stops.create_index([("stop_id", TEXT)], unique=True)
        print(f"inserted stops, count {db.stops.count_documents({})}")


    if db.trip_stops.count_documents({}) == 0:
        trip_stops_df = pd.read_json(TRIP_STOPS_FILE, dtype={
            'trip_id': str,
            'stop_id': int,
            'stop_sequence': int
        })
        db.trip_stops.insert_many(trip_stops_df.to_dict('records'))
        db.trip_stops.create_index([("trip_id", TEXT)])
        db.trip_stops.create_index([("stop_id", ASCENDING)])
        print(f"inserted trip stops, count {db.trip_stops.count_documents({})}")


    if db.shapes.count_documents({}) == 0:
        shapes_df = pd.read_json(SHAPES_FILE, dtype={
            'shape_id': str,
            'shape_pt_lat': float,
            'shape_pt_lon': float,
            'shape_pt_sequence': int
        })
        db.shapes.insert_many(shapes_df.to_dict('records'))
        db.shapes.create_index([("shape_id", TEXT)])
        db.shapes.create_index([("shape_pt_sequence", ASCENDING)])
        print(f"inserted shapes, count {db.shapes.count_documents({})}")

if __name__ == "__main__":
    init_mongo()