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
import 'package:mapmybus/widgets/stop_markers.dart';
import 'package:mapmybus/widgets/stops_page.dart';
import 'package:mapmybus/widgets/user_location_marker.dart';
import 'package:mapmybus/widgets/vehicle_marker.dart';
import 'package:mapmybus/widgets/vehicle_menu.dart';
import 'package:permission_handler/permission_handler.dart';
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
  List<Stop> _drawnStopsNearby = [];
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
  DateTime? _stopArrivalsCreateTime;
  List<String> _routeShortNamesForStop = [];

  // for better localization of vehicles
  List<double> _shapeCumDistances = [];
  final List<StopDistanceInfo> _stopsDistanceInfo = [];

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
    if (defaultTargetPlatform == TargetPlatform.android) {
      Permission.location.request();
    }

    final LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 20,
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
      showSimpleSnackbar(context, "Locatia ta nu este disponibila momentan");
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
      setState(() {
        if (_stopsDistanceInfo.isEmpty || _shapeCumDistances.isEmpty) {
          _precomputeDistances();
        }
      });
    }
  }

  // cateva metode de mai jos se bazeaza pe faptul ca sunt apelate doar in contextul
  // in care avem un vehicul selectat si lucram cu datele deja incarcate despre traseu

  void _precomputeDistances() {
    if (_drawnStops.isEmpty || _drawnPoints.isEmpty) return;

    _shapeCumDistances = List<double>.filled(
      _drawnPoints.length,
      0,
      growable: true,
    );

    for (int i = 1; i < _drawnPoints.length; i++) {
      _shapeCumDistances[i] =
          _shapeCumDistances[i - 1] +
          Geolocator.distanceBetween(
            _drawnPoints[i - 1].latitude,
            _drawnPoints[i - 1].longitude,
            _drawnPoints[i].latitude,
            _drawnPoints[i].longitude,
          );
    }

    // nu chiar exact dar mai mult mai safe decat sa presupunem ca e neintortochiat traseul
    int shapePointStartIndex = 0;

    for (final stop in _drawnStops) {
      double minDist = double.infinity;
      int closestPointIndex = shapePointStartIndex;

      for (int i = shapePointStartIndex; i < _drawnPoints.length; i++) {
        final dist = Geolocator.distanceBetween(
          stop.latitude,
          stop.longitude,
          _drawnPoints[i].latitude,
          _drawnPoints[i].longitude,
        );

        if (dist < minDist) {
          minDist = dist;
          closestPointIndex = i;
        }
      }

      shapePointStartIndex = closestPointIndex;

      _stopsDistanceInfo.add(
        StopDistanceInfo(
          stop: stop,
          distanceAlongRoute: _shapeCumDistances[closestPointIndex],
        ),
      );
    }
  }

  Future<void> _showMenu(Vehicle vehicle, String? routeShortName) async {
    if (routeShortName == null || _drawnStops.isEmpty) {
      return;
    }

    final infoMap = VehicleStopsInfo(
      latitude: vehicle.latitude!,
      longitude: vehicle.longitude!,
      stopsDistanceInfo: _stopsDistanceInfo,
      shapePoints: _drawnPoints,
      shapeCumDistances: _shapeCumDistances,
    );

    final adjacentStops = await compute(computeClosestStops, infoMap);

    if (!mounted) return;

    setState(() {
      showMenu = true;
      selectedRouteName = routeShortName;
      previousStopName = adjacentStops['previous'] ?? "-";
      nextStopName = adjacentStops['next'] ?? "-";
    });
  }

  bool _isVehicleAtFirstEnd(Vehicle vehicle) {
    final distToFirstStop = Geolocator.distanceBetween(
      vehicle.latitude!,
      vehicle.longitude!,
      vehicle.firstStopLatitude!,
      vehicle.firstStopLongitude!,
    );

    return distToFirstStop < Constants.stopEndsRadius;
  }

  bool _isVehicleAtLastEnd(Vehicle vehicle) {
    final distToLastStop = Geolocator.distanceBetween(
      vehicle.latitude!,
      vehicle.longitude!,
      vehicle.lastStopLatitude!,
      vehicle.lastStopLongitude!,
    );

    return distToLastStop < Constants.stopEndsRadius;
  }

  bool _isVehicleAtEnds(Vehicle vehicle) {
    return _isVehicleAtFirstEnd(vehicle) || _isVehicleAtLastEnd(vehicle);
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
      _stopsDistanceInfo.clear();
      _shapeCumDistances.clear();

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

      if (vehicle.isGhost) {
        throw Exception("Ghost vehicle has to be ignored");
      }

      await _onVehicleTap(vehicle, routeShortName);
    } catch (e) {
      // nu mai este vehiculul
      setState(() {
        showMenu = false;
        selectedRouteName = "";
        previousStopName = null;
        nextStopName = null;
        selectedVehicle = null;
        _lastVehicleLabel = null;
        isSelectedVehicleOnRoute = null;
        isSelectedVehicleAtEnds = null;

        _drawnStops.clear();
        _drawnStopsNearby.clear();
        _drawnPoints.clear();
        _stopsDistanceInfo.clear();
        _shapeCumDistances.clear();
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

      if (data.message == ArrivalStatus.arriving.name ||
          data.message == ArrivalStatus.unknown.name) {
        final String etaMessage = getEtaMessage(data.predictedEtaMinutes);

        etas.add(EtaDisplayInfo(stopName: stopName, etaMessage: etaMessage));
      } else if (data.message == ArrivalStatus.passed.name) {
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

  Future<double> getNextDepartureTimeDifference(
    String agencyId,
    String routeShortName,
    String direction,
  ) async {
    if (!Constants.agencyIdsWithWorkingTimetables.contains(agencyId)) {
      return 0;
    }

    if (direction != "0" && direction != "1") {
      return 0;
    }

    final dbService = context.read<DbService>();
    const days = {"Luni - Vineri": "lv", "Sambata": "s", "Duminica": "d"};
    DateTime currentTime = DateTime.now();
    double nextDeparture;

    for (final entry in days.entries) {
      final result = await dbService.getTimetable(
        agencyId,
        routeShortName,
        entry.value,
      );

      switch (result) {
        case Success(data: final rows):
          nextDeparture = _findNextDepartureTimeDifference(
            rows.sublist(5),
            currentTime,
            direction,
          );

          // scadem 10 de secunde ca de obicei pleaca mai rapid din statie decat orarul
          return max(0, nextDeparture - 10);
        case Failure(exception: final _):
          break;
      }
    }
    return 0;
  }

  double _findNextDepartureTimeDifference(
    List<List<String>> timetableRows,
    DateTime currentTime,
    String direction,
  ) {
    DateTime? nextDeparture;

    for (final row in timetableRows) {
      String departureTimeString = direction == "0" ? row[0] : row[1];

      if (departureTimeString.isEmpty) continue;

      //uneori contine niste stelute sau spatii, nu stiu de ce dar le eliminam
      departureTimeString = departureTimeString.replaceAll("*", " ").trim();
      DateTime departureTime;

      try {
        departureTime = DateTime(
          currentTime.year,
          currentTime.month,
          currentTime.day,
          int.parse(departureTimeString.split(":")[0]),
          int.parse(departureTimeString.split(":")[1]),
        );
      } catch (_) {
        continue;
      }

      if (departureTime.isAfter(currentTime)) {
        if (nextDeparture == null || departureTime.isBefore(nextDeparture)) {
          nextDeparture = departureTime;
        }
      }
    }

    // return the difference in seconds between nextDeparture and currentTime
    if (nextDeparture == null) return 0;
    return nextDeparture.difference(currentTime).inSeconds.toDouble();
  }

  void _onStopTap(Stop stop) async {
    if (_isLoading) return;

    if (_validVehicles.isEmpty) {
      showSimpleSnackbar(
        context,
        "Trebuie sa ai minim un vehicul la favorite pentru a vedea sosirile",
      );

      return;
    }

    showSimpleSnackbar(
      context,
      "Statia apasata: ${stop.stopName}. Se incarca urmatoarele sosiri...",
    );

    setState(() {
      _isLoading = true;
      _arrivalsDisplayInfo.clear();
      _selectedStop = stop;
      _stopArrivalsCreateTime = null;

      // reset la vehicul
      showMenu = false;
      selectedRouteName = "";
      previousStopName = null;
      nextStopName = null;
      selectedVehicle = null;
      _lastVehicleLabel = null;
      isSelectedVehicleOnRoute = null;
      isSelectedVehicleAtEnds = null;
    });

    setState(() {
      _arrivalsDisplayInfo = [StopArrivalDisplayInfo("-", "-", false)];
    });

    final routeProvider = context.read<RoutesProvider>();
    final db = context.read<DbService>();

    // ignoram cele fantoma
    final positions = _validVehicles
        .where((v) => !v.isGhost)
        .map(
          (v) => {
            'trip_id': v.tripId!,
            'lat': v.latitude!,
            'lon': v.longitude!,
            'label': v.label,
            'ts': v.timestamp.toIso8601String(),
          },
        )
        .toList();

    if (!mounted) return;

    // gasim si vehiculele care trec prin statie
    final tripIdsResult = await context.read<DbService>().getTripIdsForStop(
      stop.stopId,
      widget.city.agencyId,
    );

    switch (tripIdsResult) {
      case Success(data: final tripIds):
        _routeShortNamesForStop.clear();

        for (final tripId in tripIds) {
          final routeShortName = routeProvider.getRouteShortNameFromTripId(
            tripId,
            widget.city.agencyId,
          );

          if (routeShortName != null &&
              !_routeShortNamesForStop.contains(routeShortName)) {
            _routeShortNamesForStop.add(routeShortName);
          }

          _routeShortNamesForStop.sort(compareRouteNames);
        }
        break;

      case Failure(exception: final e):
        log.e("Failed to fetch trip IDs for stop ${stop.stopId}: $e");

        if (mounted) {
          showSimpleSnackbar(
            context,
            "Eroare la obtinerea vehiculelor care trec prin statia ${stop.stopName}",
          );
        }

        _routeShortNamesForStop.clear();
        break;
    }

    final result = await db.getSoonArrivalsForStop(
      widget.city.agencyId,
      stop.stopId,
      positions,
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

          final bool isVehicleAtFirstEnd = _isVehicleAtFirstEnd(
            _validVehicles.firstWhere((v) => v.label == arrival.vehicleLabel),
          );

          // adunam cat ia sa porneasca de la capat de linie (din orar)
          // momentan merge doar pentru cluj
          double nextRoutingTimeDifference = 0;
          if (isVehicleAtFirstEnd) {
            nextRoutingTimeDifference = await getNextDepartureTimeDifference(
              widget.city.agencyId,
              routeShortName ?? "",
              arrival.tripId.endsWith("_0") ? "0" : "1",
            );
          }

          final String etaMessage = getEtaMessage(
            arrival.etaMinutes + nextRoutingTimeDifference / 60,
          );

          arrivalsDisplayInfo.add(
            StopArrivalDisplayInfo(
              routeShortName ?? "?",
              etaMessage,
              isVehicleAtFirstEnd,
            ),
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
          arrivalsDisplayInfo.sort(
            (a, b) => compareEtaMessages(a.etaMessage, b.etaMessage),
          );

          setState(() {
            _stopArrivalsCreateTime = DateTime.now();
            _selectedStop = stop;
            _routeShortNamesForStop = _routeShortNamesForStop;
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

    _validVehicles = vehicleProvider.vehicles;

    _visibleVehicles = _validVehicles
        .where((v) => visibleRoutesIds.contains(v.routeId!) && !v.isGhost)
        .toList();

    /*
    print("Skipped ${_validVehicles
        .where((v) => visibleRoutesIds.contains(v.routeId!))
        .length - _visibleVehicles.length} ghost vehicles");
    */

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

            if (_drawnStops.isNotEmpty || _drawnStopsNearby.isNotEmpty)
              _stopsLayer(),

            if (_currentPosition != null) _userPositionLayer(),

            _vehiclesLayer(routeProvider),

            if (_selectedStop != null) _selectedStopLayer(),
          ],
        ),

        Positioned(
          bottom: 5,
          left: 5,
          child: const Text(
            Constants.copyrightText,
            style: TextStyle(fontSize: 10, color: Colors.black),
          ),
        ),

        Positioned(
          top: 20,
          right: 110,
          child: FloatingActionButton(
            heroTag: "centerButton",
            tooltip: "Centreaza pe locatia ta",
            mini: true,
            onPressed: _centerMapOnCurrentPosition,
            child: const Icon(Icons.my_location),
          ),
        ),

        Positioned(
          top: 20,
          right: 60,
          child: FloatingActionButton(
            heroTag: "clearButton",
            tooltip: "Sterge desenele de pe harta",
            mini: true,
            child: const Icon(Icons.cleaning_services_outlined),
            onPressed: () {
              if (selectedVehicle != null) {
                setState(() {
                  _drawnStopsNearby.clear();
                });

                showSimpleSnackbar(
                  context,
                  "Inchide meniul vehiculului inainte de a sterge traseul",
                );

                return;
              }

              setState(() {
                _drawnStops.clear();
                _drawnStopsNearby.clear();
                _drawnPoints.clear();
                _stopsDistanceInfo.clear();
                _shapeCumDistances.clear();
              });
            },
          ),
        ),

        Positioned(
          top: 20,
          right: 10,
          child: FloatingActionButton(
            heroTag: "searchStopButton",
            tooltip: "Cauta o statie si vezi urmatoarele sosiri",
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
          top: 70,
          right: 60,
          child: FloatingActionButton(
            heroTag: "showNearbyStopsButton",
            tooltip: "Afiseaza statiile din jurul tau",
            mini: true,
            child: const Icon(Icons.multiple_stop_outlined),
            onPressed: () async {
              if (_currentPosition == null) {
                showSimpleSnackbar(
                  context,
                  "Locatia ta nu este disponibila momentan",
                );
                return;
              }

              final dbService = context.read<DbService>();
              final nearbyStopsResult = await dbService.getNearbyStops(
                widget.city.agencyId,
                _currentPosition!,
                Constants.nearbyStopsRadius,
              );

              switch (nearbyStopsResult) {
                case Success(data: final nearbyStops):
                  if (mounted) {
                    setState(() {
                      _drawnStopsNearby = nearbyStops;
                    });
                  }

                  if (nearbyStops.isEmpty) {
                    if (!context.mounted) return;
                    showSimpleSnackbar(
                      context,
                      "Nu s-au gasit statii in apropiere",
                    );
                  }

                case Failure(exception: final e):
                  log.e("Failed to fetch nearby stops: $e");

                  if (!context.mounted) return;
                  showSimpleSnackbar(context, "Nu s-au putut incarca statiile");
              }
            },
          ),
        ),

        Positioned(
          top: 70,
          right: 10,
          child: FloatingActionButton(
            heroTag: "selectYourVehicleButton",
            tooltip: "Selecteaza vehiculul apropiat",
            mini: true,
            child: const Icon(Icons.bus_alert),
            onPressed: () {
              // cerem linia pentru ca pot fi multe autobuze in acelasi loc
              TextEditingController controller = TextEditingController();

              showDialog(
                context: context,
                builder: (context) {
                  return AlertDialog(
                    title: const Text(
                      "Introdu doar numele liniei pentru a identifica vehiculul aflat in proximitate",
                    ),
                    content: TextField(
                      controller: controller,
                      keyboardType: TextInputType.text,
                      decoration: const InputDecoration(
                        hintText: "Numele liniei",
                      ),
                      maxLength: 7,
                      autofocus: true,
                    ),

                    actions: [
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                        child: const Text("Anuleaza"),
                      ),

                      TextButton(
                        onPressed: () async {
                          if (_currentPosition == null) {
                            showSimpleSnackbar(
                              context,
                              "Locatia ta nu este disponibila momentan",
                            );

                            Navigator.of(context).pop();
                            return;
                          }

                          if (_validVehicles.isEmpty) {
                            showSimpleSnackbar(
                              context,
                              "Trebuie sa ai minim un vehicul la favorite pentru a utiliza functionalitatea",
                            );

                            Navigator.of(context).pop();
                            return;
                          }

                          String input = controller.text.trim().toUpperCase();
                          if (input.isNotEmpty) {
                            final matchingVehicles = _validVehicles.where((v) {
                              final routeShortName = routeProvider
                                  .getRouteShortNameFromRouteId(
                                    v.routeId!,
                                    widget.city.agencyId,
                                  );

                              return routeShortName == input;
                            }).toList();

                            if (matchingVehicles.isEmpty) {
                              showSimpleSnackbar(
                                context,
                                "Nu s-au gasit vehicule pentru linia $input",
                              );

                              Navigator.of(context).pop();
                              return;
                            }

                            // gasim cele mai apropiate vehicule sortate dupa distanta

                            final vehiclesNearby =
                                matchingVehicles
                                    .map((v) {
                                      final distance =
                                          Geolocator.distanceBetween(
                                            _currentPosition!.latitude,
                                            _currentPosition!.longitude,
                                            v.latitude!,
                                            v.longitude!,
                                          );

                                      return VehicleWithDistance(v, distance);
                                    })
                                    .where(
                                      (vd) =>
                                          vd.distance <=
                                          Constants.nearbyVehiclesRadius,
                                    )
                                    .toList()
                                  ..sort(
                                    (vd1, vd2) =>
                                        vd1.distance.compareTo(vd2.distance),
                                  );

                            if (vehiclesNearby.isEmpty) {
                              showSimpleSnackbar(
                                context,
                                "Nu s-au gasit vehicule pentru linia $input in apropierea ta",
                              );
                            } else {
                              final vd = vehiclesNearby.first;

                              // nu ar trebui sa se intample vreodata caci lista de vehicule e filtrata deja
                              final routeId = vd.vehicle.routeId;
                              if (routeId == null) {
                                return;
                              }

                              final routeShortName = routeProvider
                                  .getRouteShortNameFromRouteId(
                                    vd.vehicle.routeId!,
                                    widget.city.agencyId,
                                  );

                              // pentru a inchide eventuala fereastra de sosiri statie
                              // nu mai trebuie setstate pt ca va fi apelat in _onVehicleTap
                              _arrivalsDisplayInfo.clear();
                              _selectedStop = null;
                              _routeShortNamesForStop.clear();
                              _stopArrivalsCreateTime = null;

                              // ne asiguram ca vehiculul, ruta, sunt la favorite ca altfel nici nu-l vedem
                              bool addRouteToFavorites = false;
                              if (!routeProvider.isFavorite(
                                vd.vehicle.routeId!,
                              )) {
                                await routeProvider.toggleFavorite(
                                  routeId,
                                  widget.city.agencyId,
                                );
                                addRouteToFavorites = true;
                              }

                              await _onVehicleTap(vd.vehicle, routeShortName);

                              if (!context.mounted) return;

                              if (addRouteToFavorites) {
                                showSimpleSnackbar(
                                  context,
                                  "Linia $input a fost adaugata la favorite pentru a putea urmari vehiculul",
                                );
                              }

                              if (vehiclesNearby.length > 1) {
                                showSimpleSnackbar(
                                  context,
                                  "Au fost gasite mai multe vehicule pentru linia $input in proximitatea ta. Se selecteaza cel mai apropiat, dar e posibil sa fie incorect!",
                                );
                              }
                            }
                          }

                          Navigator.of(context).pop();
                        },
                        child: const Text("Cauta"),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),

        Positioned(
          top: 70,
          right: 110,
          child: FloatingActionButton(
            heroTag: "toggleStopNamesButton",
            tooltip: "Arata/ascunde numele statiilor",
            mini: true,
            child: const Icon(Icons.visibility_off),
            onPressed: () {
              setState(() {
                _showStopNames = !_showStopNames;
              });
            },
          ),
        ),

        //daca e vineri verde
        if (DateTime.now().weekday == DateTime.friday &&
            Constants.cityNamesWithVineriVerde.contains(widget.city.name))
          Positioned(
            bottom: 10,
            right: 10,

            child: Container(
              padding: EdgeInsets.all(8.0),
              decoration: BoxDecoration(
                color: const Color.fromARGB(123, 78, 207, 82),
                borderRadius: BorderRadius.circular(8.0),
              ),

              child: const Text(
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
            stopName: _selectedStop!.stopName,
            routeNames: _routeShortNamesForStop,
            arrivals: _arrivalsDisplayInfo,
            tableCreateTime: _stopArrivalsCreateTime,
            onClose: () {
              setState(() {
                _arrivalsDisplayInfo.clear();
                _selectedStop = null;
                _routeShortNamesForStop.clear();
                _stopArrivalsCreateTime = null;
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
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,

              children: [
                const Icon(Icons.place, color: Colors.orange, size: 50),

                Positioned(
                  top: 50,
                  child: Text(
                    _selectedStop!.stopName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                      backgroundColor: Colors.orange,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
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

        if (isSelected && _drawnPoints.length > 1 && _drawnStops.isNotEmpty) {
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
          width: 60,
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

    // oribil pe web
    double heading = _currentPosition!.heading;

    return MarkerLayer(
      markers: [
        Marker(
          point: latLng,

          width: 40,
          height: 40,
          child: UserLocationMarker(heading: heading),
        ),
      ],
    );
  }

  MarkerLayer _stopsLayer() {
    List<Marker> allStopsMarkers = [];

    allStopsMarkers.addAll(
      _drawnStops.expand((stop) {
        final bool isStart = stop.stopId == _drawnStops.first.stopId;
        final bool isEnd = stop.stopId == _drawnStops.last.stopId;

        final bool isFinalStopMarker = isStart || isEnd;

        final double iconSize = isFinalStopMarker ? 36 : 24;

        return [
          StopMarker(
            stop: stop,
            iconSize: iconSize,
            isFinalStopMarker: isFinalStopMarker,
            isStart: isStart,
            isEnd: isEnd,
            showStopNames: _showStopNames,
            onStopTap: _onStopTap,
          ),
        ];
      }).toList(),
    );

    allStopsMarkers.addAll(
      _drawnStopsNearby
          .where((nearbyStop) {
            return !_drawnStops.any(
              (drawnStop) => drawnStop.stopId == nearbyStop.stopId,
            );
          })
          .map((stop) {
            return StopMarker(
              stop: stop,
              iconSize: 24,
              isFinalStopMarker: false,
              isStart: false,
              isEnd: false,
              showStopNames: _showStopNames,
              onStopTap: _onStopTap,
            );
          })
          .toList(),
    );

    return MarkerLayer(markers: allStopsMarkers);
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
