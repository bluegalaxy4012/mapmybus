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
import 'package:mapmybus/widgets/stop_arrivals_table.dart';
import 'package:mapmybus/widgets/stop_marker.dart';
import 'package:mapmybus/widgets/stops_page.dart';
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
  // main
  final MapController _mapController = MapController();
  late final VehiclesProvider _vehicleProvider;
  String? _currentAgencyId;

  // user position
  StreamSubscription<Position>? _positionStreamSubscription;
  Position? _currentPosition;

  // map drawings
  List<Stop> _drawnStops = [];
  List<LatLng> _drawnPoints = [];
  List<Vehicle> _validVehicles = [];
  List<Vehicle> _visibleVehicles = [];

  // vehicle menu
  bool showMenu = false;
  String selectedRouteName = "";
  String? previousStopName;
  String? nextStopName;
  Vehicle? selectedVehicle;
  bool? isSelectedVehicleOnRoute;
  bool? isSelectedVehicleAtEnds;

  // state for etas and stop arrivals
  String? _lastVehicleLabel;

  DateTime? _lastEtaFetchTime;
  List<EtaDisplayInfo> _currentEtaDisplayInfo = [];

  List<StopArrivalDisplayInfo> _arrivalsDisplayInfo = [];
  Stop? _selectedStop;

  // some display state
  bool _isLoading = false;
  bool _showStopNames = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final cityProvider = context.watch<CityProvider>();
    final newAgencyId = getAgencyIdForCity(cityProvider.city);

    if (newAgencyId != _currentAgencyId) {
      _currentAgencyId = newAgencyId;

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _initRoutes(newAgencyId);
        await _initVehicles(newAgencyId);
      });
    }
  }

  // user position related
  Future<void> _getCurrentPosition() async {
    try {
      Position position = await determinePosition();

      if (mounted) {
        setState(() {
          _currentPosition = position;
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
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          (Position? position) {
            if (position != null && mounted) {
              setState(() {
                _currentPosition = position;
              });
            }
          },
        );
  }

  void _centerMapOnCurrentPosition() {
    if (_currentPosition != null) {
      _mapController.move(
        LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        widget.city.initialZoom,
      );
    } else {
      log.w("Current position unavailable");
    }
  }
  //

  @override
  void initState() {
    super.initState();

    _initUserPosition();
  }

  void _initUserPosition() {
    _getCurrentPosition();
    _startPositionStream();
  }

  Future<void> _initVehicles(String agencyId) async {
    _vehicleProvider = context.read<VehiclesProvider>();
    _vehicleProvider.removeListener(_updateMenuOnVehicleFetch);

    await _vehicleProvider.startVehicleFetchTimer(agencyId);
    _vehicleProvider.addListener(_updateMenuOnVehicleFetch);
  }

  Future<void> _initRoutes(String agencyId) async {
    final routesProvider = context.read<RoutesProvider>();
    final result = await routesProvider.init(agencyId);

    switch (result) {
      case Failure():
        if (mounted) {
          showSimpleSnackbar(
            context,
            "Nu s-au putut incarca datele, incearca sa repornesti aplicatia",
          );
        }
        break;

      default:
        break;
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
    });
  }

  bool _isVehicleAtEnds(Vehicle vehicle) {
    final firstStop = _drawnStops.first;
    final lastStop = _drawnStops.last;

    final distToFirstStop = Geolocator.distanceBetween(
      vehicle.latitude!,
      vehicle.longitude!,
      firstStop.latitude,
      firstStop.longitude,
    );

    final distToLastStop = Geolocator.distanceBetween(
      vehicle.latitude!,
      vehicle.longitude!,
      lastStop.latitude,
      lastStop.longitude,
    );

    return distToFirstStop < Constants.stopEndsRadius ||
        distToLastStop < Constants.stopEndsRadius;
  }

  bool _isVehicleOnRoute(Vehicle vehicle) {
    double minDist = double.infinity;

    for (final point in _drawnPoints) {
      final dist = Geolocator.distanceBetween(
        vehicle.latitude!,
        vehicle.longitude!,
        point.latitude,
        point.longitude,
      );

      if (dist < minDist) {
        minDist = dist;
      }
    }

    return minDist < Constants.routeProximityRadius;
  }

  Future<void> _onVehicleTap(Vehicle vehicle, String? routeShortName) async {
    setState(() {
      selectedVehicle = vehicle;
    });

    if (_lastVehicleLabel != vehicle.label) {
      _currentEtaDisplayInfo.clear();

      // sa nu dam load iar la mapDetails sau tabel de etas
      _lastVehicleLabel = vehicle.label;

      setState(() {
        _isLoading = true;
      });
      await _loadMapDetails(vehicle.tripId!);
      setState(() {
        _isLoading = false;
      });
    }

    await Future.delayed(Duration(milliseconds: 10));

    if (_drawnPoints.isEmpty || _drawnStops.isEmpty) return;

    bool isVehicleOnRoute = _isVehicleOnRoute(vehicle);
    bool isVehicleAtEnds = _isVehicleAtEnds(vehicle);

    setState(() {
      isSelectedVehicleOnRoute = isVehicleOnRoute;
      isSelectedVehicleAtEnds = isVehicleAtEnds;
    });

    await _showMenu(vehicle, routeShortName);
  }

  void _updateMenuOnVehicleFetch() async {
    if (!mounted || !showMenu || selectedVehicle == null) return;

    final routeProvider = context.read<RoutesProvider>();

    final String vehicleLabel = selectedVehicle!.label;

    try {
      final vehicle = _vehicleProvider.vehicles.firstWhere(
        (v) => v.label == vehicleLabel,
      );

      final routeShortName = routeProvider.getRouteShortNameFromRouteId(
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
        isSelectedVehicleOnRoute = null;
        isSelectedVehicleAtEnds = null;
        _drawnStops.clear();
        _drawnPoints.clear();
      });
    }
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

        final String etaMessage = getEtaMessage(eta);

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
        _lastEtaFetchTime = DateTime.now();
      });
    }
  }

  void _onStopTap(Stop stop) async {
    if (_isLoading) return;

    showSimpleSnackbar(
      context,
      "Statia apasata: ${stop.stopName}. Se incarca urmatoarele sosiri...",
    );

    setState(() {
      _isLoading = true;
      _arrivalsDisplayInfo.clear();
      _selectedStop = stop;

      // reset la vehicul
      showMenu = false;
      selectedRouteName = "";
      previousStopName = null;
      nextStopName = null;
      selectedVehicle = null;
      isSelectedVehicleOnRoute = null;
      isSelectedVehicleAtEnds = null;
    });

    setState(() {
      _arrivalsDisplayInfo = [StopArrivalDisplayInfo("-", "-")];
    });

    final routeProvider = context.read<RoutesProvider>();
    final db = context.read<DbService>();

    final positions = _validVehicles
        .map(
          (v) => {
            'trip_id': v.tripId!,
            'lat': v.latitude!,
            'lon': v.longitude!,
            'label': v.label,
          },
        )
        .toList();

    final result = await db.getSoonArrivalsForStop(
      widget.city.agencyId,
      stop.stopId,
      positions,
      n: Constants.maxArrivalsCount,
    );

    switch (result) {
      case Success(data: final arrivals):
        List<StopArrivalDisplayInfo> arrivalsDisplayInfo = [];

        for (final arrival in arrivals) {
          if (arrival.tripId.isEmpty) continue;

          final routeShortName = routeProvider.getRouteShortNameFromTripId(
            arrival.tripId,
            widget.city.agencyId,
          );

          final String etaMessage = getEtaMessage(arrival.etaMinutes);

          arrivalsDisplayInfo.add(
            StopArrivalDisplayInfo(routeShortName ?? "?", etaMessage),
          );
        }

        if (arrivalsDisplayInfo.isEmpty) {
          if (mounted) {
            showSimpleSnackbar(
              context,
              "Nu exista inca vehicule care au pornit spre statia ${stop.stopName}",
            );
          }
        } else {
          setState(() {
            _selectedStop = stop;
            _arrivalsDisplayInfo = arrivalsDisplayInfo;
          });
        }

        break;

      case Failure():
        if (mounted) {
          showSimpleSnackbar(
            context,
            "Eroare la obtinerea sosirilor in statia ${stop.stopName}",
          );
        }

        setState(() {
          _selectedStop = stop;
        });

        break;
    }

    setState(() {
      _isLoading = false;
    });
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

    _validVehicles = vehicleProvider.vehicles
        .where(
          (v) =>
              v.latitude != null &&
              v.longitude != null &&
              v.routeId != null &&
              v.tripId != null &&
              dateTimeNow.difference(v.timestamp).inMinutes <= 3,
        )
        .toList();

    _visibleVehicles = _validVehicles
        .where((v) => visibleRoutesIds.contains(v.routeId!))
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
              userAgentPackageName: 'com.marian.mapmybus',

              tileUpdateTransformer: TileUpdateTransformers.debounce(
                const Duration(milliseconds: 300),
              ),
            ),

            if (_drawnPoints.isNotEmpty) _shapePointsLayer(),

            if (_drawnStops.isNotEmpty) _stopsLayer(),

            if (_currentPosition != null) _userPositionLayer(),

            _vehiclesLayer(routeProvider),

            if (_selectedStop != null) _selectedStopLayer(),
          ],
        ),

        Positioned(
          bottom: 5,
          left: 5,
          child: Text(
            Constants.copyrightText,
            style: TextStyle(fontSize: 10, color: Colors.black),
          ),
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

        Positioned(
          top: 110,
          right: 10,
          child: FloatingActionButton(
            heroTag: "searchStopButton",
            tooltip: "Cauta o statie",
            mini: true,
            child: const Icon(Icons.search),
            onPressed: () async {
              final selectedStop = await Navigator.push<Stop>(
                context,
                MaterialPageRoute(builder: (_) => StopsPage(city: widget.city)),
              );

              if (selectedStop != null) {
                if (!context.mounted) return;

                setState(() {
                  _isLoading = true;
                });

                // better alternative ? sa astept vehicle fetchul
                await Future.delayed(const Duration(milliseconds: 1200));

                if (!context.mounted) return;

                setState(() {
                  _isLoading = false;
                });

                if (_validVehicles.isEmpty) {
                  showSimpleSnackbar(
                    context,
                    "Trebuie sa ai minim un vehicul la favorite pentru a vedea sosirile",
                  );
                } else {
                  _onStopTap(selectedStop);
                }
              }
            },
          ),
        ),

        Positioned(
          top: 160,
          right: 10,
          child: FloatingActionButton(
            heroTag: "toggleStopNamesButton",
            tooltip: "Arata/ascunde numele statiilor",
            mini: true,
            child: const Icon(Icons.text_fields),
            onPressed: () {
              setState(() {
                _showStopNames = !_showStopNames;
              });
            },
          ),
        ),

        //daca e vineri verde
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

        if (_isLoading) Center(child: CircularProgressIndicator()),

        if (showMenu)
          VehicleMenu(
            agencyId: widget.city.agencyId,
            selectedRouteName: selectedRouteName,
            previousStopName: previousStopName,
            nextStopName: nextStopName,

            isLoading: _isLoading,

            selectedVehicle: selectedVehicle,
            isSelectedVehicleOnRoute: isSelectedVehicleOnRoute,
            isSelectedVehicleAtEnds: isSelectedVehicleAtEnds,

            etasInfo: _currentEtaDisplayInfo,
            lastEtaFetchTime: _lastEtaFetchTime,

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
                isSelectedVehicleOnRoute = null;
                isSelectedVehicleAtEnds = null;

                _currentEtaDisplayInfo.clear();
                _lastVehicleLabel = null;
                _lastEtaFetchTime = null;
              });
            },
          ),

        if (_arrivalsDisplayInfo.isNotEmpty && _selectedStop != null)
          StopArrivalsTable(
            arrivals: _arrivalsDisplayInfo,
            stopName: _selectedStop!.stopName,
            onClose: () {
              setState(() {
                _arrivalsDisplayInfo.clear();
                _selectedStop = null;
              });
            },
          ),
      ],
    );
  }

  MarkerLayer _selectedStopLayer() {
    return MarkerLayer(
      markers: [
        Marker(
          width: 50,
          height: 50,
          alignment: Alignment.topCenter,
          point: LatLng(_selectedStop!.latitude, _selectedStop!.longitude),
          child: IgnorePointer(
            child: const Icon(Icons.place, color: Colors.orange, size: 50),
          ),
        ),
      ],
    );
  }

  MarkerLayer _vehiclesLayer(RoutesProvider routeProvider) {
    return MarkerLayer(
      markers: _visibleVehicles.map((v) {
        final routeShortName = routeProvider.getRouteShortNameFromRouteId(
          v.routeId!,
          widget.city.agencyId,
        );

        double bearing = 0.0;
        bool isSelected =
            selectedVehicle != null && v.label == selectedVehicle!.label;

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
    );
  }

  MarkerLayer _userPositionLayer() {
    if (_currentPosition == null) {
      return MarkerLayer(markers: []);
    }

    final latLng = LatLng(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
    );
    double heading = _currentPosition!.heading;

    return MarkerLayer(
      markers: [
        Marker(
          point: latLng,

          width: 40,
          height: 40,
          child: Stack(
            alignment: Alignment.center,

            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.lightBlue,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.blueGrey, width: 2),
                ),
              ),

              if (heading != 0.0) // invalid de obicei
                Transform.rotate(
                  angle: heading * (pi / 180),

                  child: Transform.translate(
                    offset: const Offset(0, -10),
                    child: const Icon(
                      Icons.navigation,
                      color: Colors.blue,
                      size: 20,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  MarkerLayer _stopsLayer() {
    return MarkerLayer(
      markers: _drawnStops.expand((stop) {
        final bool isStart = stop.stopId == _drawnStops.first.stopId;
        final bool isEnd = stop.stopId == _drawnStops.last.stopId;

        final bool isStopMarker = isStart || isEnd;

        final double iconSize = isStopMarker ? 36 : 24;

        return [
          if (_showStopNames)
            Marker(
              point: LatLng(stop.latitude - 0.0001, stop.longitude),
              width: 150,
              height: 20,
              alignment: Alignment.topCenter,

              child: Text(
                stop.stopName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color.fromARGB(255, 85, 85, 85),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),

          Marker(
            point: LatLng(stop.latitude, stop.longitude),
            width: iconSize,
            height: iconSize,
            alignment: isStopMarker ? Alignment.center : Alignment.topCenter,

            child: GestureDetector(
              onTap: () => _onStopTap(stop),

              child: isStart
                  ? StopMarker(name: "Start")
                  : isEnd
                  ? StopMarker(name: "End")
                  : const Icon(
                      Icons.place,
                      color: Color.fromARGB(255, 68, 137, 216),
                      size: 24,
                    ),
            ),
          ),
        ];
      }).toList(),
    );
  }

  PolylineLayer<Object> _shapePointsLayer() {
    return PolylineLayer(
      polylines: [
        Polyline(
          points: _drawnPoints,
          color: const Color.fromARGB(95, 127, 125, 255),
          strokeWidth: 4.0,
        ),
      ],
    );
  }
}
