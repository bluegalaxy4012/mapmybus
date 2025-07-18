import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart' hide Route;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
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
  late MyAppState _appState;

  final MapController _mapController = MapController();
  StreamSubscription<Position>? _positionStreamSubscription;

  LatLng? _currentPosition;

  List<Stop> _drawnStops = [];
  List<LatLng> _drawnPoints = [];

  bool showMenu = false;
  String selectedRouteName = "";
  String? previousStopName;
  String? nextStopName;
  Vehicle? selectedVehicle;

  // Map<String, double> _stopEtas = {};
  bool _isLoading = false;

  List<Stop> get drawnStops => _drawnStops;

  double _calculateBearing(LatLng start, LatLng end) {
    final double lat1 = start.latitudeInRad;
    final double lon1 = start.longitudeInRad;

    final double lat2 = end.latitudeInRad;
    final double lon2 = end.longitudeInRad;

    final double y = sin(lon2 - lon1) * cos(lat2);
    final double x =
        cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(lon2 - lon1);

    return atan2(y, x);
  }

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
    double minDist = double.infinity;
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
      if (dist < minDist) {
        minDist = dist;
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
    print("WHAT");
    print("Vehicle tapped: ${vehicle.tripId}, route: $routeShortName");

    setState(() {
      selectedVehicle = vehicle;
    });

    setState(() {
      _isLoading = true;
    });
    await _loadMapDetails(vehicle.tripId!);
    setState(() {
      _isLoading = false;
    });

    await Future.delayed(Duration(milliseconds: 10));

    _showMenu(vehicle, routeShortName);
  }

  void requestStopArrivalTimes(Vehicle vehicle) async {
    setState(() {
      _isLoading = true;
    });

    final stopIds = _drawnStops.map((s) => s.stopId).toList();
    if (stopIds.isEmpty) return;

    final Uri uri = Uri.parse('$etasApiUrl${widget.city.agencyId}').replace(
      queryParameters: {
        'trip_id': vehicle.tripId,
        'lat': vehicle.latitude.toString(),
        'lon': vehicle.longitude.toString(),
        'stop_ids': stopIds,
      },
    );

    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final List<dynamic> results = json.decode(response.body);

        for (var data in results) {
          final stopName = _drawnStops
              .firstWhere((s) => s.stopId == data['stop_id'])
              .stopName;

          if (data['message'] == "Success") {
            final fix = DateTime.now().difference(vehicle.timestamp);
            final eta = data['predicted_eta_minutes'] - fix.inSeconds / 60.0;

            final minEta = eta.floor();
            final maxEta = (eta + 1).ceil();

            print("Dureaza intre $minEta si $maxEta minute pana la $stopName");
          } else if (data['message'] ==
              "Vehicle has already passed this stop") {
            print('Vehiculul a trecut deja pe la $stopName');
          } else {
            print('error etas...');
            // handle
          }
        }
      }
    } catch (e) {
      print('error fetching arrival times');
      // handle
    } finally {
      setState(() {
        _isLoading = false;
      });
    }

    // daca era api call per stop
    
    // for (var stop in _drawnStops) {
    //   final Uri uri = Uri.parse(
    //     '${apiUrl}?trip_id=${vehicle.tripId}&lat=${vehicle.latitude}&lon=${vehicle.longitude}&stop_id=${stop.stopId}',
    //   );

    //   // print('req arrival times for stop: ${stop.stopName}, URI: $uri, Vehicle: ${vehicle.label}');

    //   try {
    //     final response = await http.get(uri);
    //     if (response.statusCode == 200) {
    //       final Map<String, dynamic> data = json.decode(response.body);
    //       if (data['message'] == "Success") {
    //         final fix = DateTime.now().difference(vehicle.timestamp);
    //         final eta = data['predicted_eta_minutes'] - fix.inSeconds / 60.0;

    //         print("Dureaza intre ${(eta - 1).floor()} si ${(eta+1).ceil()} minute pana la ${stop.stopName}");
    //         // print('Dureaza cam ${data['predicted_eta_minutes']} minute pana la ${stop.stopName}');
    //       }
    //       else if (data['message'] == "Vehicle has already passed this stop") {
    //         print('Vehiculul a trecut deja pe la ${stop.stopName}');
    //       }
    //     }
    //   }
    //   catch (e) {
    //     print('error fetching arrival times: $e');
    //     // handle
    //   }

    //   await Future.delayed(Duration(milliseconds: 75));
    // }
  }

  void _updateMenuOnVehicleFetch() async {
    if (!mounted || !showMenu || selectedVehicle == null) return;

    final String? vehicleLabel = selectedVehicle!.label;
    if (vehicleLabel == null) return;

    try {
      final vehicle = _appState.vehicles.firstWhere(
        (v) => v.label == vehicleLabel,
      );

      final routeShortName = _appState.getRouteShortName(
        vehicle.routeId!,
        widget.city.agencyId,
      );

      await _onVehicleTap(vehicle, routeShortName);
    } catch (e) {
      // nu mai este vehiculul
      setState(() {
        showMenu = false;
        selectedRouteName = "";
        previousStopName = null;
        nextStopName = null;
        selectedVehicle = null;
        _drawnStops.clear();
        _drawnPoints.clear();
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _getCurrentPosition();
    _startPositionStream();

    _appState = context.read<MyAppState>();

    _appState.fetchVehicles(widget.city.agencyId);
    _appState.startVehicleFetchTimer(widget.city.agencyId);
    _appState.addListener(_updateMenuOnVehicleFetch);
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _appState.removeListener(_updateMenuOnVehicleFetch);
    super.dispose();
  }

  Widget _buildStopMarker(String name) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: Colors.black,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        name,
        style: TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<MyAppState>();

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

              // temporar
              tileUpdateTransformer: TileUpdateTransformers.debounce(
                const Duration(milliseconds: 200),
              ),
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
                    width: 30,
                    height: 30,
                    child: GestureDetector(
                      onTap: () => (ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Statia apasata: ${stop.stopName}'),
                          duration: Duration(milliseconds: 1500),
                          showCloseIcon: true,
                        ),
                      )),
                      child: stop.stopId == _drawnStops.first.stopId
                          ? _buildStopMarker("Start")
                          : stop.stopId == _drawnStops.last.stopId
                          ? _buildStopMarker("End")
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

                double bearing = 0.0;
                bool isSelected =
                    selectedVehicle != null &&
                    v.label == selectedVehicle!.label;

                if (isSelected && _drawnPoints.length > 1) {
                  double minDist = double.infinity;
                  int nextShapePoint = 0;

                  for (int i = 0; i < _drawnPoints.length; i++) {
                    final dist = Geolocator.distanceBetween(
                      v.latitude!,
                      v.longitude!,
                      _drawnPoints[i].latitude,
                      _drawnPoints[i].longitude,
                    );
                    if (dist < minDist) {
                      minDist = dist;
                      nextShapePoint = i;
                    }
                  }

                  if (nextShapePoint < _drawnPoints.length - 1) {
                    LatLng startPoint = _drawnPoints[nextShapePoint];
                    LatLng endPoint = _drawnPoints[nextShapePoint + 1];
                    bearing = _calculateBearing(startPoint, endPoint);
                  }
                }

                return Marker(
                  point: LatLng(v.latitude!, v.longitude!),
                  width: 50,
                  height: 30,
                  child: GestureDetector(
                    onTap: () => _onVehicleTap(v, routeShortName),

                    child: Stack(
                      // mainAxisAlignment: MainAxisAlignment.center,
                      alignment: Alignment.center,
                      children: [
                        if (isSelected)
                          Transform.rotate(
                            angle: bearing,
                            child: Transform.translate(
                              offset: Offset(0, -18),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Icon(
                                    Icons.navigation,
                                    color: Colors.black,
                                    size: 27,
                                  ),

                                  Icon(
                                    Icons.navigation,
                                    color: v.tripId!.endsWith('_0')
                                        ? Colors.green
                                        : Colors.red,
                                    size: 20,
                                  ),
                                ],
                              ),
                            ),
                          ),
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
                              fontSize: isSelected ? 13 : 12,
                              fontWeight: FontWeight.bold,
                              color: isSelected
                                  ? Colors.black
                                  : const Color.fromARGB(255, 48, 48, 48),
                              decoration: isSelected
                                  ? TextDecoration.underline
                                  : TextDecoration.none,
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

        if (_isLoading) Center(child: CircularProgressIndicator()),
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
                      onPressed: () {
                        if (selectedVehicle != null && !_isLoading) {
                          requestStopArrivalTimes(selectedVehicle!);
                        }
                      },
                      child: _isLoading
                          ? SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                color: Theme.of(context).primaryColor,
                              ),
                            )
                          : Text('Estimeaza timpul de sosire la o statie'),
                    ),

                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          showMenu = false;
                          selectedRouteName = "";
                          previousStopName = null;
                          nextStopName = null;
                          selectedVehicle = null;
                        });
                      },
                      child: Text('Inchide'),
                    ),
                  ],
                ),
              ),
            ),
          ),

        //daca e vineri
        if (DateTime.now().weekday == DateTime.friday)
          Positioned(
            bottom: 10,
            right: 10,

            child: Container(
              padding: EdgeInsets.all(8.0),
              decoration: BoxDecoration(
                color: const Color.fromARGB(123, 78, 207, 82),
                borderRadius: BorderRadius.circular(8.0),
              ),

              child: Text(
                'Vinerea Verde',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
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
