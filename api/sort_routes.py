import json
import re

def sort_key(name):
    m = re.match(r'^(\d+)([A-Za-z]*)$', name)
    if m:
        return (0, int(m.group(1)), m.group(2) or '')
    m = re.match(r'^([A-Za-z]+)(\d+)([A-Za-z]*)$', name)
    if m:
        return (1, m.group(1), int(m.group(2)), m.group(3) or '')
    return (2, name)

with open('data/routes.json', 'r+', encoding='utf-8') as f:
    routes = json.load(f)
    routes.sort(key=lambda r: sort_key(r["route_short_name"]))
    
    f.seek(0)
    json.dump(routes, f)
    f.truncate()

print("Sorted routes")
