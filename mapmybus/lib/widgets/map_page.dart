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
      final stops = dbService.getStopsForTrip(tripId);
      final shape = dbService.getShape(tripId);

      //to add desenat pe harta
    } catch (e) {
      print('error loading visualization for trip $tripId: $e');
    }
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
                    onTap: () => _loadMapDetails(v.tripId!),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
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
            // if ()
            PolylineLayer(
              polylines: [
                Polyline(
                  points: [],
                  color: Colors.lightBlueAccent,
                  strokeWidth: 4.0,
                ),
              ],
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
