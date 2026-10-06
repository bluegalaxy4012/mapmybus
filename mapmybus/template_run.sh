```bash
#!/bin/bash

WEB_PORT="YOUR_WEB_PORT"
API_BASE_URL="https://your-api-domain.example/api"
MAP_API_KEY="YOUR_MAP_API_KEY"

flutter run -d chrome \
  --web-port="$WEB_PORT" \
  --dart-define="STOPS_API_URL=$API_BASE_URL/stops" \
  --dart-define="TRIPS_API_URL=$API_BASE_URL/trips" \
  --dart-define="SHAPES_API_URL=$API_BASE_URL/shapes" \
  --dart-define="VEHICLES_API_URL=$API_BASE_URL/vehicles" \
  --dart-define="TIMETABLES_API_URL=$API_BASE_URL/timetables" \
  --dart-define="ROUTES_API_URL=$API_BASE_URL/routes" \
  --dart-define="ETAS_API_URL=$API_BASE_URL/predict" \
  --dart-define="ARRIVALS_API_URL=$API_BASE_URL/arrivals" \
  --dart-define="WEATHER_API_URL=$API_BASE_URL/weather" \
  --dart-define="REACHABLE_API_URL=$API_BASE_URL/reachable" \
  --dart-define="MAP_API_KEY=$MAP_API_KEY"
```
