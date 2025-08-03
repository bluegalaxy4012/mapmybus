# de rulat zilnic pe la 4 dimineata

import subprocess

print("Refreshing used data...\n")

print("-initializing folders-\n")
subprocess.run(["python", "init_folders.py"])

print("-getting shapes-\n")
subprocess.run(["python", "get_shapes.py"])

print("-getting routes, stops, trip_stops-\n")
subprocess.run(["python", "get_other_jsons.py"])

print("-sorting routes-\n")
subprocess.run(["python", "sort_routes.py"])

print("-getting timetables-\n")
subprocess.run(["python", "get_timetables.py"])

print("-reinitializing mongo with everything-\n")
subprocess.run(["python", "init_mongo.py"])

print("Done")
