import json
import os
import requests
from pathlib import Path
from dotenv import load_dotenv
load_dotenv()

AGENCY_IDS = ["1", "2", "4", "6", "8"]

OUTPUT_DIR = Path("csv")

DAY_TYPES = ["lv", "s", "d"]

def get_routes_file(agency_id: str):
    return f"data/agency{agency_id}_routes.json"

def get_timetables_url(agency_id: str, short_name: str, day_type: str):
    if agency_id == "2":
        return f"https://ctpcj.ro/orare/csv/orar_{short_name}_{day_type}.csv"
    
    # todo pt restul
    return ""


def main():
    for idx in range(len(AGENCY_IDS)):
        agency_id = AGENCY_IDS[idx]

        with open(get_routes_file(agency_id), encoding="utf-8") as f:
            routes = json.load(f)

        short_names = {route["route_short_name"] for route in routes}

        for short in short_names:
            for day in DAY_TYPES:
                url = get_timetables_url(agency_id, short, day)
                out_path = OUTPUT_DIR / f"agency{agency_id}_orar_{short}_{day}.csv"

                try:
                    res = requests.get(url, timeout=10)

                    if res.status_code == 200 and "text/csv" in res.headers.get("Content-Type", ""):
                        lines = [line for line in res.text.splitlines() if line.strip()]
                        out_path.write_text("\n".join(lines), encoding="utf-8")
                        print(f"Saved: {out_path}")
                    else:
                        print(f"Couldn't get: {url} ({res.status_code})")
                except Exception as e:
                    print(f"{e}: {url}")


if __name__ == "__main__":
    main()