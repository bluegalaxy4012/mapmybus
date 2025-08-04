import requests
import json
import time
from datetime import datetime
import os
from dotenv import load_dotenv

load_dotenv()

VEHICLES_API_URL = os.getenv("BASE_URL", "") + "/vehicles"
API_KEY = os.getenv("DEV_API_KEY", "")
AGENCY_IDS = [1, 2, 4, 6, 8]
FETCH_ALL_AGENCIES_INTERVAL_SECONDS = 20
DELAY_BETWEEN_AGENCIES_SECONDS = 1

def fetch_and_append_vehicle_data():
    while True:
        current_utc_time = datetime.now().isoformat(timespec='seconds') 

        for agency_id in AGENCY_IDS:
            output_file = f"agency{agency_id}_data_vehicles.json"
            
            if not os.path.exists(output_file):
                with open(output_file, 'w') as f:
                    json.dump([], f)

            headers = {
                "X-Agency-Id": str(agency_id),
                "Accept": "application/json",
                "X-API-KEY": API_KEY
            }

            try:
                response = requests.get(VEHICLES_API_URL, headers=headers, timeout=5)

                # exceptie skip
                response.raise_for_status()

                data = response.json()

                new_entry = {
                    "date": current_utc_time,
                    "data": data
                }

                with open(output_file, 'r+') as f:
                    file_content = f.read()
                    existing_data = json.loads(file_content)
                    existing_data.append(new_entry)

                    f.seek(0)
                    json.dump(existing_data, f)
                    f.truncate()


            except Exception:
                pass

            time.sleep(DELAY_BETWEEN_AGENCIES_SECONDS)

        print("cycle done")
        time.sleep(FETCH_ALL_AGENCIES_INTERVAL_SECONDS)


if __name__ == "__main__":
    fetch_and_append_vehicle_data()
