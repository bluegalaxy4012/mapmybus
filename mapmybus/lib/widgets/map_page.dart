import 'dart:async';

import 'package:flutter/material.dart' hide Route;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../models.dart';

Future<Position> _determinePosition() async {
  bool serviceEnabled;
  LocationPermission permission;

  serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    return Future.error('Location services are disabled.');
  }

  permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      return Future.error('Location permissions are denied');
    }
  }

  if (permission == LocationPermission.deniedForever) {
    return Future.error(
      'Location permissions are permanently denied, we cannot request permissions.',
    );
  }

  return await Geolocator.getCurrentPosition(
    // locationSettings: LocationSettings(
    //   accuracy: LocationAccuracy.high,
    //   distanceFilter: 3,
    // ),
  );
}

class MapPage extends StatefulWidget {
  const MapPage({super.key, required this.city});

  final CityConfig city;

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final MapController _mapController = MapController();
  StreamSubscription<Position>? _positionStreamSubscription;

  LatLng? _currentPosition;

  List<Stop> _drawnStops = [];
  List<LatLng> _drawnPoints = [];

  bool showMenu = false;
  String selectedRouteName = "";
  String? previousStopName;
  String? nextStopName;

  List<Stop> get drawnStops => _drawnStops;

  Future<void> _getCurrentPosition() async {
    try {
      Position position = await _determinePosition();
      if (mounted) {
        setState(() {
          _currentPosition = LatLng(position.latitude, position.longitude);
        });
      }
    } catch (e) {
      print('error: $e');
      // handle
    }
  }

  void _startPositionStream() {
    final LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 3,
    );
    _positionStreamSubscription =
        Geolocator.getPositionStream(
          locationSettings: locationSettings,
        ).listen((Position? position) {
          print(
            position == null
                ? 'Unknown'
                : '${position.latitude.toString()}, ${position.longitude.toString()}',
          );

          if (position != null && mounted) {
            setState(() {
              _currentPosition = LatLng(position.latitude, position.longitude);
            });
          }
        });
  }

  void _centerMapOnCurrentPosition() {
    if (_currentPosition != null) {
      _mapController.move(_currentPosition!, widget.city.initialZoom);
    } else {
      print('current position unavailable');
    }
  }

  Future<void> _loadMapDetails(String tripId) async {
    final dbService = context.read<MyAppState>().dbService;

    try {
      // final stops = dbService.getStopsForTrip(tripId);
      // final shape = dbService.getShape(tripId);

      _drawnStops = await dbService.getStopsForTrip(tripId);
      var drawnShape = await dbService.getShape(tripId);

      _drawnPoints = drawnShape
          .map((p) => LatLng(p.latitude, p.longitude))
          .toList();

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('error loading visualization for trip $tripId: $e');
    }
  }

  void _showMenu(Vehicle vehicle, String? routeShortName) {
    if (routeShortName == null || _drawnStops.isEmpty) {
      return;
    }

    // presupunand ca nu exista statii la care e mai rapid sa cobori cu N inainte si sa mergi pe jos decat sa stai
    double minDistance = double.infinity;
    Stop? previousStop, nextStop;

    Stop closestStop = _drawnStops.first;
    int index = 0;

    for (int i = 0; i < _drawnStops.length; i++) {
      Stop stop = _drawnStops[i];

      double dist = Geolocator.distanceBetween(
        vehicle.latitude!,
        vehicle.longitude!,
        stop.latitude,
        stop.longitude,
      );
      if (dist < minDistance) {
        minDistance = dist;
        closestStop = stop;
        index = i;
      }
    }

    double dist1 = Geolocator.distanceBetween(
      drawnStops.first.latitude,
      drawnStops.first.longitude,
      closestStop.latitude,
      closestStop.longitude,
    );

    double dist2 = Geolocator.distanceBetween(
      drawnStops.first.latitude,
      drawnStops.first.longitude,
      vehicle.latitude!,
      vehicle.longitude!,
    );

    if (dist1 >= dist2) {
      nextStop = closestStop;
      previousStop = index > 0 ? _drawnStops[index - 1] : null;
    } else {
      previousStop = closestStop;
      nextStop = index < _drawnStops.length - 1 ? _drawnStops[index + 1] : null;
    }

    setState(() {
      showMenu = true;
      selectedRouteName = routeShortName;
      previousStopName = previousStop?.stopName ?? '-';
      nextStopName = nextStop?.stopName ?? '-';
    });
  }

  Future<void> _onVehicleTap(Vehicle vehicle, String? routeShortName) async {
    await _loadMapDetails(vehicle.tripId!);
    _showMenu(vehicle, routeShortName);
  }

  @override
  void initState() {
    super.initState();
    _getCurrentPosition();
    _startPositionStream();
    context.read<MyAppState>().fetchVehicles(widget.city.agencyId);
    context.read<MyAppState>().startVehicleFetchTimer(widget.city.agencyId);
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();

    var visibleRoutesIds = appState.favoriteRouteIds;
    final visibleVehicles = appState.vehicles
        .where(
          (v) =>
              v.latitude != null &&
              v.longitude != null &&
              v.routeId != null &&
              v.tripId != null &&
              visibleRoutesIds.contains(v.routeId!),
        )
        .toList();

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: widget.city.center,
            initialZoom: widget.city.initialZoom,
            maxZoom: widget.city.maxZoom,
            minZoom: widget.city.minZoom,
            interactionOptions: InteractionOptions(
              flags:
                  InteractiveFlag.drag |
                  InteractiveFlag.flingAnimation |
                  InteractiveFlag.doubleTapZoom |
                  InteractiveFlag.scrollWheelZoom |
                  InteractiveFlag.pinchZoom,
            ),
            cameraConstraint: CameraConstraint.contain(
              bounds: widget.city.bounds,
            ),
          ),

          children: [
            TileLayer(
              urlTemplate:
                  "https://{s}.basemaps.cartocdn.com/rastertiles/light_all/{z}/{x}/{y}.png",
              userAgentPackageName: 'com.mapmybus.app',
            ),

            if (_drawnPoints.isNotEmpty)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _drawnPoints,
                    color: const Color.fromARGB(95, 127, 125, 255),
                    strokeWidth: 4.0,
                  ),
                ],
              ),

            if (_drawnStops.isNotEmpty)
              MarkerLayer(
                markers: _drawnStops.map((stop) {
                  return Marker(
                    point: LatLng(stop.latitude, stop.longitude),
                    width: 25,
                    height: 25,
                    child: GestureDetector(
                      onTap: () => (ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Statia apasata: ${stop.stopName}'),
                          duration: Duration(milliseconds: 1500),
                          showCloseIcon: true,
                        ),
                      )),
                      child: stop.stopId == _drawnStops.first.stopId
                          ? Icon(Icons.circle, color: Colors.green, size: 30)
                          : stop.stopId == _drawnStops.last.stopId
                          ? Icon(Icons.circle, color: Colors.red, size: 30)
                          : Icon(
                              Icons.place,
                              color: const Color.fromARGB(255, 68, 137, 216),
                              size: 20,
                            ),
                    ),
                  );
                }).toList(),
              ),

            if (_currentPosition != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: _currentPosition!,
                    width: 40,
                    height: 40,
                    child: Icon(Icons.location_on, color: Colors.red, size: 40),
                  ),
                ],
              ),

            MarkerLayer(
              markers: visibleVehicles.map((v) {
                final routeShortName = appState.getRouteShortName(
                  v.routeId!,
                  widget.city.agencyId,
                );
                return Marker(
                  point: LatLng(v.latitude!, v.longitude!),
                  width: 50,
                  height: 30,
                  child: GestureDetector(
                    onTap: () => _onVehicleTap(v, routeShortName),

                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),

                          decoration: BoxDecoration(
                            color: v.tripId!.endsWith('_0')
                                ? Colors.green
                                : Colors.red,
                            // color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.black),
                          ),

                          child: Text(
                            routeShortName ?? 'Unknown',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),

        Positioned(
          top: 30,
          right: 30,
          child: FloatingActionButton(
            mini: true,
            onPressed: _centerMapOnCurrentPosition,
            child: const Icon(Icons.my_location),
          ),
        ),

        Positioned(
          top: 80,
          right: 30,
          child: FloatingActionButton(
            mini: true,
            child: const Icon(Icons.clear_all),
            onPressed: () => {
              _drawnStops.clear(),
              _drawnPoints.clear(),
              setState(() {}),
            },
          ),
        ),

        if (showMenu)
          Positioned(
            left: 10,
            top: 10,
            child: Material(
              elevation: 4.0,
              borderRadius: BorderRadius.circular(8.0),
              child: Container(
                padding: EdgeInsets.all(12.0),
                color: Colors.white,
                child: Column(
                  spacing: 15.0,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Detalii traseu: Linia $selectedRouteName',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),

                    Text('Statia anterioara: $previousStopName'),

                    Text('Statia urmatoare: $nextStopName'),

                    ElevatedButton(
                      onPressed: () {},
                      child: Text('Afiseaza orar'),
                    ),

                    ElevatedButton(
                      onPressed: () {},
                      child: Text('Estimeaza timpul de sosire la o statie'),
                    ),

                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          showMenu = false;
                        });
                      },
                      child: Text('Inchide'),
                    ),
                  ],
                ),
              ),
            ),
          ),

        Positioned(
          bottom: 10,
          left: 10,
          child: Text(
            '© OpenStreetMap contributors, © CARTO',
            style: TextStyle(fontSize: 12, color: Colors.black),
          ),
        ),
      ],
    );
  }
}
