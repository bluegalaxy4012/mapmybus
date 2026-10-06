import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Route;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mapmybus/models/city_config.dart';
import 'package:mapmybus/models/eta.dart';
import 'package:mapmybus/models/info_dtos.dart';
import 'package:mapmybus/models/result.dart';
import 'package:mapmybus/models/stop.dart';
import 'package:mapmybus/models/vehicle.dart';
import 'package:mapmybus/models/weather.dart';
import 'package:mapmybus/models/reachable.dart';
import 'package:mapmybus/service/api_service.dart';
import 'package:mapmybus/providers/city_provider.dart';
import 'package:mapmybus/providers/routes_provider.dart';
import 'package:mapmybus/providers/vehicles_provider.dart';
import 'package:mapmybus/providers/route_preview_provider.dart';
import 'package:mapmybus/core/utils.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:mapmybus/widgets/common-page/simple_snackbar.dart';
import 'package:mapmybus/widgets/map-page/stop_arrivals_table.dart';
import 'package:mapmybus/widgets/map-page/stop_markers.dart';
import 'package:mapmybus/widgets/common-page/stops_page.dart';
import 'package:mapmybus/widgets/map-page/user_location_marker.dart';
import 'package:mapmybus/widgets/map-page/vehicle_marker.dart';
import 'package:mapmybus/widgets/map-page/vehicle_menu.dart';
import 'package:mapmybus/widgets/map-page/nearby_vehicles_sheet.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key, required this.city});

  final CityConfig city;

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  // main
  final MapController _mapController = MapController();
  // late final VehiclesProvider _vehicleProvider;
  VehiclesProvider? _vehicleProvider;
  String? _currentAgencyId;

  // user position
  StreamSubscription<Position>? _positionStreamSubscription;
  Position? _currentPosition;

  // map drawings
  vt.Style? _mapStyle;
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
  StopWithoutPosition? previousStop;
  StopWithoutPosition? nextStop;
  Vehicle? selectedVehicle;
  bool? isSelectedVehicleOnRoute;
  bool? isSelectedVehicleAtEnds;

  // state for etas and stop arrivals
  String? _lastVehicleLabel;
  String? _lastTripId;

  DateTime? _lastEtaFetchTime;
  List<EtaDisplayInfo> _currentEtaDisplayInfo = [];

  List<StopArrivalDisplayInfo> _arrivalsDisplayInfo = [];
  Stop? _selectedStop;
  DateTime? _stopArrivalsCreateTime;
  List<String> _routeShortNamesForStop = [];

  final Map<String, List<List<String>>> _timetableCache = {};

  // for better localization of vehicles
  List<double> _shapeCumDistances = [];
  final List<StopDistanceInfo> _stopsDistanceInfo = [];

  // some display state
  bool _isLoading = false;
  bool _showStopNames = true;
  bool showOnlySelectedVehicleRoute = false;

  // weather
  WeatherInfo? _weather;
  Timer? _weatherTimer;

  // reachable stops
  List<ReachableStop> _reachableStops = [];

  // route preview
  String? _previewTripId;
  String? _previewRouteShortName;
  List<LatLng> _previewPoints = [];
  List<Stop> _previewStops = [];
  int _handledPreviewId = 0;
  bool _weatherStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final cityProvider = context.watch<CityProvider>();
    final newAgencyId = getAgencyIdForCity(cityProvider.city);

    final previewProvider = context.watch<RoutePreviewProvider>();
    if (previewProvider.requestId != _handledPreviewId) {
      _handledPreviewId = previewProvider.requestId;
      final pendingTripId = previewProvider.tripId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (pendingTripId != null) {
          _loadPreviewRoute(pendingTripId);
        } else {
          _clearPreview();
        }
      });
    }

    if (newAgencyId != _currentAgencyId) {
      _currentAgencyId = newAgencyId;
      _weatherStarted = false;

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _initRoutes(newAgencyId);
        await _initVehicles(newAgencyId);
        _fetchWeather();
      });
    } else if (!_weatherStarted) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fetchWeather());
    }
  }

  // weather related
  void _fetchWeather() {
    if (_currentAgencyId == null) return;
    _weatherStarted = true;

    final server = context.read<Server>();
    server.getWeather(_currentAgencyId!).then((result) {
      if (!mounted) return;
      switch (result) {
        case Success(data: final weather):
          setState(() => _weather = weather);
        case Failure():
          break;
      }
    });

    _weatherTimer?.cancel();
    _weatherTimer = Timer(const Duration(minutes: 10), _fetchWeather);
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
        _mapController.camera.zoom,
      );
    } else {
      showSimpleSnackbar(context, "Locatia ta nu este disponibila momentan");
    }
  }
  //

  @override
  void initState() {
    super.initState();

    _loadMapStyle();

    _initUserPosition();
  }

  Future<void> _loadMapStyle() async {
    final style = await vt.StyleReader(
      uri: 'mapbox://styles/bluegalaxy4012/cmuto0p9900xq01sb8j69ap99',
      apiKey: Constants.mapboxToken,
    ).read();

    if (!mounted) {
      style.dispose();
      return;
    }

    setState(() => _mapStyle = style);
  }

  void _initUserPosition() {
    _getCurrentPosition();
    _startPositionStream();
  }

  Future<void> _initVehicles(String agencyId) async {
    final vp = context.read<VehiclesProvider>();
    _vehicleProvider?.removeListener(_updateMenuOnVehicleFetch);
    _vehicleProvider = vp;

    await vp.startVehicleFetchTimer(agencyId);
    vp.addListener(_updateMenuOnVehicleFetch);
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
    final server = context.read<Server>();

    final resultStops = await server.getStopsForTrip(
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

    final resultShape = await server.getShape(tripId, widget.city.agencyId);

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

  Future<void> _loadPreviewRoute(String tripId) async {
    final server = context.read<Server>();
    final previewProvider = context.read<RoutePreviewProvider>();

    final resultStops = await server.getStopsForTrip(
      tripId,
      widget.city.agencyId,
    );

    if (!mounted) return;

    switch (resultStops) {
      case Success(data: final stops):
        _previewStops = stops;
        break;

      case Failure(exception: final e):
        log.e("Failed to fetch stops for preview trip $tripId: $e");
        _clearPreview();
        return;
    }

    final resultShape = await server.getShape(tripId, widget.city.agencyId);

    if (!mounted) return;

    switch (resultShape) {
      case Success(data: final shapePoints):
        _previewPoints = shapePoints
            .map((point) => LatLng(point.latitude, point.longitude))
            .toList();
        break;

      case Failure(exception: final e):
        log.e("Failed to fetch shape for preview trip $tripId: $e");
        _clearPreview();
        return;
    }

    _previewTripId = tripId;
    _previewRouteShortName = previewProvider.routeShortName;

    if (mounted) {
      setState(() {});
    }
  }

  void _clearPreview() {
    if (_previewTripId == null &&
        _previewRouteShortName == null &&
        _previewPoints.isEmpty &&
        _previewStops.isEmpty) {
      return;
    }
    setState(() {
      _previewTripId = null;
      _previewRouteShortName = null;
      _previewPoints.clear();
      _previewStops.clear();
    });
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
      previousStop =
          adjacentStops['previous'] ??
          StopWithoutPosition(stopId: "0", stopName: "-");
      nextStop =
          adjacentStops['next'] ??
          StopWithoutPosition(stopId: "0", stopName: "-");
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

    if (_lastVehicleLabel != vehicle.label || _lastTripId != vehicle.tripId) {
      _currentEtaDisplayInfo.clear();
      _stopsDistanceInfo.clear();
      _shapeCumDistances.clear();

      // sa nu dam load iar la mapDetails sau tabel de etas
      _lastVehicleLabel = vehicle.label;
      _lastTripId = vehicle.tripId;

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
      final vehicle = _vehicleProvider!.vehicles.firstWhere(
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
        showOnlySelectedVehicleRoute = false;
        _lastVehicleLabel = null;
        _lastTripId = null;
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

  void _showDirectRouteDialog(ReachableStop s) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(s.stopName),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Poti ajunge direct cu:",
              style: TextStyle(fontSize: 13),
            ),

            const Text(
              "(maxim 8 linii afisate)",
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            ...s.routes
                .take(8)
                .map(
                  (r) => ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 15,
                      child: Text(
                        r.routeShortName,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    title: Text(
                      "Linia ${r.routeShortName}",
                      style: const TextStyle(fontSize: 16),
                    ),
                    subtitle: Text(
                      "${r.stopsAway} ${r.stopsAway == 1 ? 'statie' : 'statii'}",
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      context.read<RoutePreviewProvider>().request(
                        r.tripId,
                        r.routeShortName,
                      );
                    },
                  ),
                ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Inchide"),
          ),
        ],
      ),
    );
  }

  MarkerLayer _reachableLayer() => MarkerLayer(
    markers: _reachableStops
        .map(
          (s) => Marker(
            point: LatLng(s.lat, s.lon),
            width: 16,
            height: 16,
            child: GestureDetector(
              onTap: () => _showDirectRouteDialog(s),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color.fromARGB(255, 174, 74, 202),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
            ),
          ),
        )
        .toList(),
  );

  void requestStopArrivalTimes(Vehicle vehicle) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final server = context.read<Server>();

      final stopIds = _drawnStops.map((s) => s.stopId).toList();
      if (stopIds.isEmpty) return;

      final result = await server.getEtas(
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

        etas.add(
          EtaDisplayInfo(
            stop: StopWithoutPosition(stopId: data.stopId, stopName: stopName),
            etaMessage: etaMessage,
          ),
        );
      } else if (data.message == ArrivalStatus.passed.name) {
        etas.add(
          EtaDisplayInfo(
            stop: StopWithoutPosition(stopId: data.stopId, stopName: stopName),
            etaMessage: "Trecut",
          ),
        );
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

  String _todayDayType() {
    final d = DateTime.now().weekday;
    if (d == DateTime.sunday) return "d";
    if (d == DateTime.saturday) return "s";
    return "lv";
  }

  Future<double> getNextDepartureTimeDifference(
    String agencyId,
    String routeShortName,
    String routeIdString,
    String direction,
  ) async {
    if (routeShortName.isEmpty || (direction != "0" && direction != "1")) {
      return 0;
    }

    final key = "$agencyId|$routeIdString|${_todayDayType()}";
    List<List<String>>? rows = _timetableCache[key];

    if (rows == null) {
      final result = await context.read<Server>().getTimetable(
        agencyId,
        routeShortName,
        routeIdString,
        _todayDayType(),
      );
      if (result is! Success<List<List<String>>, Exception>) return 0;
      rows = result.data;
      _timetableCache[key] = rows;
    }

    // orar extern (PDF/site) sau orar invalid -> nu putem calcula
    if (rows.length < 6 ||
        (rows.isNotEmpty &&
            rows[0].isNotEmpty &&
            rows[0][0] == "EXTERNAL_URL")) {
      return 0;
    }

    final next = _findNextDepartureTimeDifference(
      rows.sublist(5),
      DateTime.now(),
      direction,
    );

    return max(0, next - 10);
  }

  double _findNextDepartureTimeDifference(
    List<List<String>> timetableRows,
    DateTime currentTime,
    String direction,
  ) {
    DateTime? nextDeparture;

    for (final row in timetableRows) {
      if (row.length < 2) continue;

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
    });

    setState(() {
      _arrivalsDisplayInfo = [StopArrivalDisplayInfo("-", 0, "-", false)];
    });

    final routeProvider = context.read<RoutesProvider>();
    final db = context.read<Server>();

    if (!mounted) return;

    // gasim si vehiculele care trec prin statie
    final tripIdsResult = await context.read<Server>().getTripIdsForStop(
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

          final routeId = routeProvider.getRouteIdFromRouteShortName(
            routeShortName ?? "",
          );

          Vehicle? veh;
          for (final v in _validVehicles) {
            if (v.label == arrival.vehicleLabel) {
              veh = v;
              break;
            }
          }
          final bool isVehicleAtFirstEnd =
              veh != null && _isVehicleAtFirstEnd(veh);

          // adunam cat ia sa porneasca de la capat de linie (din orar)
          // momentan merge doar pentru cluj
          double nextRoutingTimeDifference = 0;
          if (isVehicleAtFirstEnd) {
            nextRoutingTimeDifference = await getNextDepartureTimeDifference(
              widget.city.agencyId,
              routeShortName ?? "",
              routeId.toString(),
              arrival.tripId.endsWith("_0") ? "0" : "1",
            );
          }

          // rectificare, nu e foarte exact cu orarul deci afisam posibilul delay in plus in loc sa l adaugam direct

          final double eta = arrival.etaMinutes;
          String etaMessage = getEtaMessage(eta);

          if (nextRoutingTimeDifference > 0) {
            final String possibleDelayMessage =
                nextRoutingTimeDifference / 60.0 > 1
                ? "${(nextRoutingTimeDifference / 60.0).toStringAsFixed(0)} min"
                : "${nextRoutingTimeDifference.toStringAsFixed(0)} sec";
            etaMessage = "$etaMessage (+$possibleDelayMessage)";
          }

          arrivalsDisplayInfo.add(
            StopArrivalDisplayInfo(
              routeShortName ?? "?",
              eta, // doar pentru sortare ca sa nu mai recalculez mesajele altcandva
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
          arrivalsDisplayInfo.sort((a, b) => a.eta.compareTo(b.eta));

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
    _vehicleProvider?.removeListener(_updateMenuOnVehicleFetch);
    _weatherTimer?.cancel();
    _mapStyle?.dispose();

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
            // TileLayer(
            //   urlTemplate: Constants.mapTileProviderUrl,
            //   userAgentPackageName: 'com.marian.mapmybus',

            //   tileUpdateTransformer: TileUpdateTransformers.debounce(
            //     const Duration(milliseconds: 300),
            //   ),
            // ),
            TileLayer(
              urlTemplate:
                  'https://api.mapbox.com/styles/v1/bluegalaxy4012/cmuto0p9900xq01sb8j69ap99/tiles/512/{z}/{x}/{y}@2x.webp?access_token=${Constants.mapboxToken}',
              userAgentPackageName: 'com.marian.mapmybus',
              tileUpdateTransformer: TileUpdateTransformers.debounce(
                const Duration(milliseconds: 100),
              ),
              tileDimension: 512,
              zoomOffset: -1,
            ),

            // merge prost cu vector tiles
            // if (_mapStyle != null)
            //   vt.VectorTileLayer(
            //     theme: _mapStyle!.theme,
            //     tileProviders: _mapStyle!.providers,
            //     rasterSources: _mapStyle!.rasterSources,
            //     sprites: _mapStyle!.sprites,
            //     concurrency: 2,
            //     rasterCacheMaxBytes: 64 * 1024 * 1024,
            //     memoryCacheMaxBytes: 16 * 1024 * 1024,
            //     tileFadeDuration: Duration.zero,
            //     // showLabels: false,
            //   ),
            if (_drawnPoints.isNotEmpty) _shapePointsLayer(),

            if (_previewPoints.isNotEmpty) _previewShapeLayer(),

            if (_previewStops.isNotEmpty) _previewStopsLayer(),

            if (_previewPoints.isNotEmpty && _previewStops.isNotEmpty)
              _previewDirectionLayer(),

            if (_reachableStops.isNotEmpty) _reachableLayer(),

            if (_drawnStops.isNotEmpty || _drawnStopsNearby.isNotEmpty)
              _stopsLayer(),

            if (_currentPosition != null) _userPositionLayer(),

            _vehiclesLayer(routeProvider),

            if (_selectedStop != null) _selectedStopLayer(),
          ],
        ),

        if (_weather?.shouldWarn == true)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                margin: const EdgeInsets.fromLTRB(8, 4, 170, 0),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _weather!.color,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _weather!.message!,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        if (_previewTripId != null)
          Positioned(
            bottom: 15,
            left: 0,
            right: 0,
            child: Center(
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color.fromARGB(255, 219, 206, 19),
                      width: 2,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.directions_bus,
                        color: Color.fromARGB(255, 219, 206, 19),
                        size: 32,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "Previzualizare: $_previewRouteShortName",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color.fromARGB(255, 219, 206, 19),
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: _clearPreview,
                        child: const Icon(
                          Icons.close,
                          color: Color.fromARGB(255, 219, 206, 19),
                          size: 32,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

        Positioned(
          bottom: 5,
          left: 5,
          child: const Text(
            Constants.copyrightText,
            style: TextStyle(fontSize: 10, color: Color.fromARGB(192, 0, 0, 0)),
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
                  // astea au sens sa se stearga si daca e selectat un vehicul
                  _drawnStopsNearby.clear();
                  _reachableStops.clear();
                  _clearPreview();
                });

                showSimpleSnackbar(
                  context,
                  "Inchide meniul vehiculului inainte de a sterge traseul sau",
                );

                return;
              }

              setState(() {
                _drawnStops.clear();
                _drawnStopsNearby.clear();
                _drawnPoints.clear();
                _stopsDistanceInfo.clear();
                _shapeCumDistances.clear();
                _reachableStops.clear();
              });
              _clearPreview();
              if (_previewTripId == null) {
                context.read<RoutePreviewProvider>().clear();
              }
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

                // await Future.delayed(const Duration(milliseconds: 1200));

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

              final server = context.read<Server>();
              final nearbyStopsResult = await server.getNearbyStops(
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
            heroTag: "selectRouteButton",
            tooltip: "Cauta vehicule in apropiere",
            mini: true,
            child: const Icon(Icons.near_me),
            onPressed: () {
              if (_currentPosition == null) {
                showSimpleSnackbar(
                  context,
                  "Locatia ta nu este disponibila momentan",
                );
                return;
              }

              if (_validVehicles.isEmpty) {
                showSimpleSnackbar(
                  context,
                  "Trebuie sa ai minim un vehicul la favorite pentru a utiliza functionalitatea",
                );
                return;
              }

              showNearbyVehiclesSheet(
                context: context,
                currentPosition: _currentPosition!,
                vehicles: _validVehicles,
                routeProvider: routeProvider,
                agencyId: widget.city.agencyId,
                onVehicleSelected: (vehicle, routeShortName) async {
                  if (!routeProvider.isFavorite(vehicle.routeId!)) {
                    await routeProvider.toggleFavorite(
                      vehicle.routeId!,
                      widget.city.agencyId,
                    );
                  }
                  await _onVehicleTap(vehicle, routeShortName);
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
            tooltip: "Arata/Ascunde numele statiilor",
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
            previousStop: previousStop,
            nextStop: nextStop,

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

            removeFromFavorites: () async {
              if (selectedVehicle == null) return;

              final routeProvider = context.read<RoutesProvider>();
              final routeId = selectedVehicle!.routeId;
              final routeShortName = selectedRouteName;

              if (routeId == null) return;

              if (routeProvider.isFavorite(routeId)) {
                await routeProvider.toggleFavorite(
                  routeId,
                  widget.city.agencyId,
                );
              }

              if (!context.mounted) return;
              showSimpleSnackbar(
                context,
                "Linia $routeShortName a fost scoasa de la favorite",
              );
            },

            showOnlyThisRoute: () {
              setState(() {
                showOnlySelectedVehicleRoute = !showOnlySelectedVehicleRoute;
              });
            },

            onClose: () {
              setState(() {
                showMenu = false;
                selectedRouteName = "";
                previousStopName = null;
                nextStopName = null;
                selectedVehicle = null;
                showOnlySelectedVehicleRoute = false;
                isSelectedVehicleOnRoute = null;
                isSelectedVehicleAtEnds = null;

                _currentEtaDisplayInfo.clear();
                _lastVehicleLabel = null;
                _lastTripId = null;
                _lastEtaFetchTime = null;
              });
            },
          ),

        if (_arrivalsDisplayInfo.isNotEmpty && _selectedStop != null)
          StopArrivalsTable(
            agencyId: widget.city.agencyId,
            stopId: _selectedStop!.stopId,
            stopName: _selectedStop!.stopName,
            routeNames: _routeShortNamesForStop,
            arrivals: _arrivalsDisplayInfo,
            tableCreateTime: _stopArrivalsCreateTime,
            weather: _weather,
            onClose: () {
              setState(() {
                _arrivalsDisplayInfo.clear();
                _selectedStop = null;
                _routeShortNamesForStop.clear();
                _stopArrivalsCreateTime = null;
                _reachableStops.clear();
              });
            },
            onShowReachable: () async {
              final server = context.read<Server>();
              final result = await server.getReachableStops(
                widget.city.agencyId,
                _selectedStop!.stopId,
              );

              if (!mounted) return;

              switch (result) {
                case Success(data: final stops):
                  setState(() => _reachableStops = stops);
                case Failure():
                  if (!context.mounted) return;
                  showSimpleSnackbar(
                    context,
                    "Nu s-au putut incarca destinatiile directe",
                  );
              }
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
    Marker? selectedVehicleMarker;
    final List<Marker> markers = [];

    for (final v in _visibleVehicles) {
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

      final vehicleMarker = Marker(
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

      if (isSelected) {
        selectedVehicleMarker = vehicleMarker;
      }

      if (!showOnlySelectedVehicleRoute ||
          (selectedVehicle != null && v.routeId! == selectedVehicle!.routeId)) {
        markers.add(vehicleMarker);
      }
    }

    // ca sa fie peste toate celelalte
    if (selectedVehicleMarker != null) {
      markers.remove(selectedVehicleMarker);
      markers.add(selectedVehicleMarker);
    }

    return MarkerLayer(markers: markers);
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

  PolylineLayer<Object> _previewShapeLayer() {
    return PolylineLayer(
      polylines: [
        Polyline(
          points: _previewPoints,
          color: const Color.fromARGB(95, 219, 206, 19),
          strokeWidth: 5.0,
        ),
      ],
    );
  }

  MarkerLayer _previewStopsLayer() {
    return MarkerLayer(
      markers: _previewStops.asMap().entries.map((entry) {
        final index = entry.key;
        final stop = entry.value;
        final bool isFinal = index == 0 || index == _previewStops.length - 1;
        final double size = isFinal ? 22 : 12;

        return Marker(
          point: LatLng(stop.latitude, stop.longitude),
          width: size,
          height: size,
          child: Container(
            decoration: BoxDecoration(
              color: const Color.fromARGB(255, 219, 206, 19),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5),
            ),
          ),
        );
      }).toList(),
    );
  }

  MarkerLayer _previewDirectionLayer() {
    if (_previewPoints.length < 2) {
      return MarkerLayer(markers: []);
    }

    final start = _previewPoints.first;
    final end = _previewPoints.last;

    // punem o sageata de la start->end fix langa start dar impinsa un pic in directia opusa lui end ca sa nu se suprapuna cu markerul de start

    Offset offset = Offset(
      start.latitude - end.latitude,
      start.longitude - end.longitude,
    );
    offset = offset / offset.distance * 0.003;

    final arrowPoint = LatLng(
      (start.latitude + offset.dx),
      (start.longitude + offset.dy),
    );

    final bearing = calculateBearing(end, start);

    return MarkerLayer(
      markers: [
        Marker(
          point: arrowPoint,
          width: 50,
          height: 50,
          child: Transform.rotate(
            angle: bearing,
            child: const Icon(
              Icons.arrow_drop_down_circle_outlined,
              color: Color.fromARGB(255, 255, 206, 19),
              size: 50,
            ),
          ),
        ),
      ],
    );
  }
}
