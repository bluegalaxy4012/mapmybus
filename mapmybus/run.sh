#!/bin/bash


flutter run -d chrome \
  --dart-define=ETAS_API_URL=https://mmb.marian.homes/predict \
  --dart-define=STOPS_API_URL=https://mmb.marian.homes/stops \
  --dart-define=SHAPES_API_URL=https://mmb.marian.homes/shapes \
  --dart-define=VEHICLES_API_URL=https://mmb.marian.homes/vehicles \
  --dart-define=TIMETABLES_API_URL=https://mmb.marian.homes/timetables \
  --dart-define=ROUTES_API_URL=https://mmb.marian.homes/routes
