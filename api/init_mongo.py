import pandas as pd
from pymongo import MongoClient
from dotenv import load_dotenv
import os

load_dotenv()

AGENCY_IDS = ["1", "2", "4", "6"]
MONGO_URL = os.getenv("MONGO_URL") or "mongo_fallback_url"
DB_NAME = os.getenv("DB_NAME") or "db_fallback_name"


def get_routes_file(agency_id: str):
    return f"data/agency{agency_id}_routes.json"


def get_stops_file(agency_id: str):
    return f"data/agency{agency_id}_stops.json"


def get_trip_stops_file(agency_id: str):
    return f"data/agency{agency_id}_trip_stops.json"


def get_shapes_file(agency_id: str):
    return f"data/agency{agency_id}_shapes.json"


def init_mongo():
    client = MongoClient(MONGO_URL)
    db = client[DB_NAME]

    for agency_id in AGENCY_IDS:
        routes_collection = db[f"agency{agency_id}_routes"]
        stops_collection = db[f"agency{agency_id}_stops"]
        trip_stops_collection = db[f"agency{agency_id}_trip_stops"]
        shapes_collection = db[f"agency{agency_id}_shapes"]

        routes_df = pd.read_json(
            get_routes_file(agency_id),
            dtype={
                "route_id": int,
                "route_short_name": str,
                "route_long_name": str,
                "route_color": str,
                "route_type": int,
                "route_desc": str,
            },
        )

        if "agency_id" in routes_df.columns:
            routes_df.drop(columns=["agency_id"], inplace=True)

        routes_collection.drop()

        routes_collection.insert_many(routes_df.to_dict("records"))
        routes_collection.create_index("route_id", unique=True)
        routes_collection.create_index("route_short_name")

        print(
            f"Inserted routes for agency {agency_id}, count: {routes_collection.count_documents({})}"
        )

        stops_df = pd.read_json(
            get_stops_file(agency_id),
            dtype={
                "stop_id": int,
                "stop_lat": float,
                "stop_lon": float,
                "stop_name": str,
            },
        )
        stops_collection.drop()

        stops_collection.insert_many(stops_df.to_dict("records"))
        stops_collection.create_index("stop_id", unique=True)

        print(
            f"Inserted stops for agency {agency_id}, count: {stops_collection.count_documents({})}"
        )

        trip_stops_df = pd.read_json(
            get_trip_stops_file(agency_id),
            dtype={"trip_id": str, "stop_id": int, "stop_sequence": int},
        )
        trip_stops_collection.drop()

        trip_stops_collection.insert_many(trip_stops_df.to_dict("records"))
        trip_stops_collection.create_index("trip_id")
        trip_stops_collection.create_index("stop_id")

        print(
            f"Inserted trip stops for agency {agency_id}, count: {trip_stops_collection.count_documents({})}"
        )

        shapes_df = pd.read_json(
            get_shapes_file(agency_id),
            dtype={
                "shape_id": str,
                "shape_pt_lat": float,
                "shape_pt_lon": float,
                "shape_pt_sequence": int,
            },
        )
        shapes_collection.drop()

        shapes_collection.insert_many(shapes_df.to_dict("records"))
        shapes_collection.create_index("shape_id")
        shapes_collection.create_index("shape_pt_sequence")

        print(
            f"Inserted shapes for agency {agency_id}, count: {shapes_collection.count_documents({})}"
        )


if __name__ == "__main__":
    init_mongo()
