import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Route;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mapmybus/db_service.dart';
import 'package:mapmybus/providers/city_provider.dart';
import 'package:mapmybus/providers/routes_provider.dart';
import 'package:mapmybus/providers/vehicles_provider.dart';
import 'package:mapmybus/utils.dart';
import 'package:mapmybus/widgets/simple_snackbar.dart';
import 'package:mapmybus/widgets/stop_marker.dart';
import 'package:mapmybus/widgets/vehicle_marker.dart';
import 'package:mapmybus/widgets/vehicle_menu.dart';
import 'package:provider/provider.dart';

import '../models.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key, required this.city});

  final CityConfig city;

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final MapController _mapController = MapController();
  late final VehiclesProvider _vehicleProvider;

  @override
  void initState() {
    super.initState();

    _initUserPosition();
  }

  void _initUserPosition() {
    _getCurrentPosition();
    _startPositionStream();
  }

  String? _currentAgencyId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final cityProvider = context.watch<CityProvider>();
    final newAgencyId = getAgencyIdForCity(cityProvider.city);

    // print("OLDE agencyId: $_currentAgencyId, NEW agencyId: $newAgencyId");

    if (newAgencyId != _currentAgencyId) {
      _currentAgencyId = newAgencyId;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _initRoutes(newAgencyId);
        _initVehicles(newAgencyId);
      });
    }
  }

  Future<void> _initVehicles(String agencyId) async {
    _vehicleProvider = context.read<VehiclesProvider>();
    _vehicleProvider.removeListener(_updateMenuOnVehicleFetch);

    await _vehicleProvider.startVehicleFetchTimer(agencyId);
    _vehicleProvider.addListener(_updateMenuOnVehicleFetch);
  }

  Future<void> _initRoutes(String agencyId) async {
    final routesProvider = context.read<RoutesProvider>();
    routesProvider.init(agencyId);
  }

  StreamSubscription<Position>? _positionStreamSubscription;

  LatLng? _currentPosition;

  List<Stop> _drawnStops = [];
  List<LatLng> _drawnPoints = [];

  bool showMenu = false;
  String selectedRouteName = "";
  String? previousStopName;
  String? nextStopName;
  Vehicle? selectedVehicle;

  List<EtaDisplayInfo> _currentEtaDisplayInfo = [];

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
      log.e("Error getting current position: $e");

      if (mounted) {
        showSimpleSnackbar(context, "Nu s-a putut obtine locatia");
      }
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
      log.w("Current position unavailable");
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
        log.e("Failed to fetch stops for trip $tripId: $e");

        showSimpleSnackbar(
          context,
          "Nu s-au putut obtine detaliile pentru acest traseu",
        );

        return;
    }

    final resultShape = await dbService.getShape(tripId, widget.city.agencyId);

    if (!mounted) return;

    switch (resultShape) {
      case Success(data: final shapePoints):
        _drawnPoints = shapePoints
            .map((point) => LatLng(point.latitude, point.longitude))
            .toList();
        break;

      case Failure(exception: final e):
        log.e("Failed to fetch shape for trip $tripId: $e");

        showSimpleSnackbar(
          context,
          "Nu s-au putut obtine detaliile pentru acest traseu",
        );
        return;
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _showMenu(Vehicle vehicle, String? routeShortName) async {
    if (routeShortName == null || _drawnStops.isEmpty) {
      return;
    }

    final infoMap = VehicleStopsInfo(
      latitude: vehicle.latitude!,
      longitude: vehicle.longitude!,
      stops: _drawnStops,
    );

    final result = await compute(computeClosestStops, infoMap);

    if (!mounted) return;

    setState(() {
      showMenu = true;
      selectedRouteName = routeShortName;
      previousStopName = result['previous'] ?? '-';
      nextStopName = result['next'] ?? '-';
      _currentEtaDisplayInfo = [];
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

    await _showMenu(vehicle, routeShortName);
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
          // nu ar trebui
          if (results.isEmpty) {
            log.w("No ETAs found for vehicle ${vehicle.label}");
            return;
          }

          _handleEtas(results, vehicle);
          break;

        case Failure(exception: final e):
          log.e("Failed to fetch ETAs: $e");

          showSimpleSnackbar(context, "Nu s-au putut obtine timpii de sosire");
          return;
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _handleEtas(List<Eta> results, Vehicle vehicle) {
    final etas = <EtaDisplayInfo>[];

    for (final data in results) {
      final stopName = _drawnStops
          .firstWhere((s) => s.stopId == data.stopId)
          .stopName;

      if (data.message == "Success") {
        final fix = DateTime.now().difference(vehicle.timestamp);
        final eta = data.predictedEtaMinutes - fix.inSeconds / 60.0;

        // doar in caz de erori cu nr negative care nu ar trebui sa apara
        final minEta = max(0, eta.floor());
        final maxEta = min(60, max(0, (eta + 1).ceil()));

        String etaMessage = "$minEta - $maxEta min";

        if (maxEta > 25 || minEta > 20) {
          etaMessage = ">20 min";
        }

        etas.add(EtaDisplayInfo(stopName: stopName, etaMessage: etaMessage));
      } else if (data.message == "Vehicle has already passed this stop") {
        etas.add(EtaDisplayInfo(stopName: stopName, etaMessage: "Trecut"));
      } else {
        log.w('Unexpected error while getting etas');

        if (mounted) {
          showSimpleSnackbar(context, "Eroare la obtinerea timpii de sosire");
        }
      }
    }

    if (mounted) {
      setState(() {
        _currentEtaDisplayInfo = etas;
      });
    }
  }

  void _updateMenuOnVehicleFetch() async {
    if (!mounted || !showMenu || selectedVehicle == null) return;

    final routeProvider = context.read<RoutesProvider>();

    final String vehicleLabel = selectedVehicle!.label;

    try {
      final vehicle = _vehicleProvider.vehicles.firstWhere(
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
    _vehicleProvider.removeListener(_updateMenuOnVehicleFetch);
    _vehicleProvider.stopVehicleFetchTimer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vehicleProvider = context.watch<VehiclesProvider>();
    final routeProvider = context.watch<RoutesProvider>();

    final visibleRoutesIds = routeProvider.favoriteRouteIdsSet;
    final dateTimeNow = DateTime.now();

    final visibleVehicles = vehicleProvider.vehicles
        .where(
          (v) =>
              v.latitude != null &&
              v.longitude != null &&
              v.routeId != null &&
              v.tripId != null &&
              dateTimeNow.difference(v.timestamp).inMinutes <= 3 &&
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
              urlTemplate: Constants.mapTileProviderUrl,
              userAgentPackageName: 'com.mapmybus.app',

              tileUpdateTransformer: TileUpdateTransformers.debounce(
                const Duration(milliseconds: 300),
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
                      onTap: () => showSimpleSnackbar(
                        context,
                        "Statia apasata: ${stop.stopName}",
                      ),
                      child: stop.stopId == _drawnStops.first.stopId
                          ? StopMarker(name: "Start")
                          : stop.stopId == _drawnStops.last.stopId
                          ? StopMarker(name: "End")
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
          top: 10,
          right: 10,
          child: FloatingActionButton(
            heroTag: "centerButton",
            tooltip: "Centreaza pe locatia ta",
            mini: true,
            onPressed: _centerMapOnCurrentPosition,
            child: const Icon(Icons.my_location),
          ),
        ),

        Positioned(
          top: 60,
          right: 10,
          child: FloatingActionButton(
            heroTag: "clearButton",
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
            etasInfo: _currentEtaDisplayInfo,

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
                "Vinerea Verde",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ),

        Positioned(
          bottom: 5,
          left: 5,
          child: Text(
            Constants.copyrightText,
            style: TextStyle(fontSize: 10, color: Colors.black),
          ),
        ),
      ],
    );
  }
}
