import json
import re

AGENCY_IDS = ["1", "2", "4", "6", "8"]


def sort_key(name):
    name = name.upper()
    m = re.match(r"^(\d+)([^0-9\s]*)$", name)
    if m:
        return (0, int(m.group(1)), m.group(2))
    m = re.match(r"^([^0-9\s]+)(\d+)([^0-9\s]*)$", name)
    if m:
        return (1, m.group(1), int(m.group(2)), m.group(3))
    return (2, name)


def main():
    for agency_id in AGENCY_IDS:
        with open(f"data/agency{agency_id}_routes.json", "r+", encoding="utf-8") as f:
            routes = json.load(f)
            for r in routes:
                r["route_short_name"] = r["route_short_name"].upper().strip()

            routes.sort(key=lambda r: sort_key(r["route_short_name"]))

            f.seek(0)
            json.dump(routes, f)
            f.truncate()
        print(f"Sorted routes for agency {agency_id}")


if __name__ == "__main__":
    main()
