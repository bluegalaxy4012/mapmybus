import 'dart:async';

import 'package:flutter/material.dart' hide Route;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mapmybus/db_service.dart';
import 'package:mapmybus/providers/routes_provider.dart';
import 'package:mapmybus/providers/vehicles_provider.dart';
import 'package:mapmybus/utils.dart';
import 'package:mapmybus/widgets/stop_marker.dart';
import 'package:mapmybus/widgets/vehicle_marker.dart';
import 'package:mapmybus/widgets/vehicle_menu.dart';
import 'package:provider/provider.dart';
// import '../main.dart';
import '../models.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key, required this.city});

  final CityConfig city;

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _getCurrentPosition();
    _startPositionStream();

    // _appState = context.read<MyAppState>();
    final vehicleProvider = context.read<VehiclesProvider>();

    vehicleProvider.fetchVehiclesAndNotify(widget.city.agencyId);
    vehicleProvider.addListener(_updateMenuOnVehicleFetch);
    vehicleProvider.startVehicleFetchTimer(widget.city.agencyId);
  }

  // late MyAppState _appState;

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

  bool _isLoading = false;

  List<Stop> get drawnStops => _drawnStops;

  Future<void> _getCurrentPosition() async {
    try {
      Position position = await determinePosition();
      if (mounted) {
        setState(() {
          _currentPosition = LatLng(position.latitude, position.longitude);
        });
      }
    } catch (e) {
      log.e('Error getting current position: $e');
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
      log.w('Current position unavailable');
    }
  }

  Future<void> _loadMapDetails(String tripId) async {
    final dbService = context.read<DbService>();

      final resultStops = await dbService.getStopsForTrip(
        tripId,
        widget.city.agencyId,
      );

      if (!mounted) return;

      switch (resultStops) {
        case Success(data: final stops):
          _drawnStops = stops;
          break;

        case Failure(exception: final e):
          log.e('Failed to fetch stops for trip $tripId: $e');

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Nu s-au putut obtine statiile pentru acest traseu'),
              duration: Duration(seconds: 2),
              showCloseIcon: true,
            ),
          );
          return;
      }


      final resultShape = await dbService.getShape(
        tripId,
        widget.city.agencyId,
      ); 

      if (!mounted) return;

      switch (resultShape) {
        case Success(data: final shapePoints):
          _drawnPoints = shapePoints
              .map((point) => LatLng(point.latitude, point.longitude))
              .toList();
          break;

        case Failure(exception: final e):
          log.e('Failed to fetch shape for trip $tripId: $e');
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Nu s-au putut obtine punctele pentru acest traseu'),
              duration: Duration(seconds: 2),
              showCloseIcon: true,
            ),
          );
          return;
      }

      if (mounted) {
        setState(() {});
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

    try {
    final dbService = context.read<DbService>();

    final stopIds = _drawnStops.map((s) => s.stopId).toList();
    if (stopIds.isEmpty) return;


      final result = await dbService.getEtas(
        vehicle,
        stopIds,
        widget.city.agencyId,
      );

      if (!mounted) return;

      switch (result) {
        case Success(data: final results):
          if (results.isEmpty) {
            log.w('No ETAs found for vehicle ${vehicle.label}');
            return;
          }
          _handleEtas(results, vehicle);
          break;

        case Failure(exception: final e):
          log.e('Failed to fetch ETAs: $e');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Nu s-au putut obtine timpii de sosire'),
              duration: Duration(seconds: 2),
              showCloseIcon: true,
            ),
          );
          return;

      }
    }
    finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _handleEtas(List<Eta> results, Vehicle vehicle) {
    for (var data in results) {
      final stopName = _drawnStops
          .firstWhere((s) => s.stopId == data.stopId)
          .stopName;
    
      if (data.message == "Success") {
        final fix = DateTime.now().difference(vehicle.timestamp);
        final eta = data.predictedEtaMinutes - fix.inSeconds / 60.0;
    
        final minEta = eta.floor();
        final maxEta = (eta + 1).ceil();
    
        // momentan neafisate
        log.i("Dureaza intre $minEta si $maxEta minute pana la $stopName");
      } else if (data.message == "Vehicle has already passed this stop") {
        log.i('Vehiculul a trecut deja pe la $stopName');
      } else {
        log.w('Something wrong while getting etas...');
        // handle
      }
    }
  }

  void _updateMenuOnVehicleFetch() async {
    if (!mounted || !showMenu || selectedVehicle == null) return;

    final vehicleProvider = context.read<VehiclesProvider>();
    final routeProvider = context.read<RoutesProvider>();

    final String vehicleLabel = selectedVehicle!.label;

    try {
      final vehicle = vehicleProvider.vehicles.firstWhere(
        (v) => v.label == vehicleLabel,
      );

      final routeShortName = routeProvider.getRouteShortName(
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
  void dispose() {
    _positionStreamSubscription?.cancel();
    context.read<VehiclesProvider>().removeListener(_updateMenuOnVehicleFetch);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // final appState = context.watch<MyAppState>();
    final vehicleProvider = context.watch<VehiclesProvider>();
    final routeProvider = context.watch<RoutesProvider>();

    var visibleRoutesIds = routeProvider.favoriteRouteIds;
    final visibleVehicles = vehicleProvider.vehicles
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
              urlTemplate: mapTileProviderUrl,
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
                          ? StopMarker("Start")
                          : stop.stopId == _drawnStops.last.stopId
                          ? StopMarker("End")
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
                final routeShortName = routeProvider.getRouteShortName(
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
                    bearing = calculateBearing(startPoint, endPoint);
                  }
                }

                return Marker(
                  point: LatLng(v.latitude!, v.longitude!),
                  width: 50,
                  height: 40,
                  child: VehicleMarker(
                    v: v,
                    routeShortName: routeShortName,
                    isSelected: isSelected,
                    bearing: bearing,
                    onTap: () => _onVehicleTap(v, routeShortName),
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
            tooltip: "Centreaza pe locatia ta",
            mini: true,
            onPressed: _centerMapOnCurrentPosition,
            child: const Icon(Icons.my_location),
          ),
        ),

        Positioned(
          top: 80,
          right: 30,
          child: FloatingActionButton(
            tooltip: "Sterge traseul desenat",
            mini: true,
            child: const Icon(Icons.clear_all),
            onPressed: () {
              if (selectedVehicle != null) return;

              setState(() {
                _drawnStops.clear();
                _drawnPoints.clear();
              });
            },
          ),
        ),

        if (_isLoading) Center(child: CircularProgressIndicator()),
        if (showMenu)
          VehicleMenu(
            agencyId: widget.city.agencyId,
            selectedRouteName: selectedRouteName,
            previousStopName: previousStopName,
            nextStopName: nextStopName,
            isLoading: _isLoading,
            selectedVehicle: selectedVehicle,
            onRequestStopArrivalTimes: () {
              if (selectedVehicle != null && !_isLoading) {
                requestStopArrivalTimes(selectedVehicle!);
              }
            },
            onClose: () {
              setState(() {
                showMenu = false;
                selectedRouteName = "";
                previousStopName = null;
                nextStopName = null;
                selectedVehicle = null;
              });
            },
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
            copyrightText,
            style: TextStyle(fontSize: 12, color: Colors.black),
          ),
        ),
      ],
    );
  }
}
