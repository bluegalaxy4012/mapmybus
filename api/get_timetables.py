import json
import os
import requests
from pathlib import Path
from dotenv import load_dotenv
load_dotenv()

ROUTES_FILE = os.getenv("ROUTES_FILE")
OUTPUT_DIR = Path("csv")

DAY_TYPES = ["lv", "s", "d"]

with open(ROUTES_FILE, encoding="utf-8") as f:
    routes = json.load(f)

short_names = {route["route_short_name"] for route in routes}

for short in short_names:
    for day in DAY_TYPES:
        url = f"https://ctpcj.ro/orare/csv/orar_{short}_{day}.csv"
        out_path = OUTPUT_DIR / f"orar_{short}_{day}.csv"

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
