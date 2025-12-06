import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:logger/logger.dart';
import 'package:mapmybus/models/city_config.dart';
import 'package:mapmybus/models/info_dtos.dart';

final log = Logger(level: kReleaseMode ? Level.off : Level.debug);

class Constants {
  /// constants
  /// comentat = nemaifolosite

  // const String routesAssetPath = 'data/routes.json';
  // const String stopsAssetPath = 'data/stops.json';
  // const String tripStopsAssetPath = 'data/trip_stops.json';
  // const String shapesAssetPath = 'data/shapes.json';

  static const String tranzyApiBaseUrl = 'https://api.tranzy.ai/v1/opendata';
  static const String tranzyVehiclesEndpoint = '$tranzyApiBaseUrl/vehicles';
  static const String mapTileProviderUrl =
      'https://{s}.basemaps.cartocdn.com/rastertiles/light_all/{z}/{x}/{y}.png';

  static const Duration snackBarDuration = Duration(milliseconds: 2500);

  // typedef Seconds = int;
  static const int defaultRefreshInterval = 20;

  // distantele in metri
  static const double stopEndsRadius = 125;
  static const double routeProximityRadius = 125;

  static const double nearbyStopsRadius = 375;
  static const double nearbyVehiclesRadius = 475;

  static const double unknownEtaMinutes = 999;

  // static const int maxArrivalsCount = 7;

  static const String tripDirectionInSuffix = '_0';
  // const String tripDirectionOutSuffix = '_1';

  static const String appTitle = 'Map My Bus';
  static const String copyrightText = '© OpenStreetMap contributors, © CARTO';

  // fontSizes candva
  static const double smallScreenBonusSize = 17.5;
  static const double largeScreenBonusSize = 2;
  //

  // pentru cateva cazuri speciale in UI, cum ar fi cand numele liniei e lung si sageata trebuie mutata mai spre directia de mers
  // range -> power to raise length at (ca sa fie mai drastic la lungimi mari si bonus mare)
  static const ranges = [
    (-pi, -5 * pi / 6, 0.0),
    (-5 * pi / 6, -3 * pi / 4, 1.0),
    (-3 * pi / 4, -pi / 4, 2.0),
    (-pi / 4, -pi / 6, 1.0),
    (-pi / 6, pi / 6, 0.0),
    (pi / 6, pi / 4, 1.0),
    (pi / 4, 3 * pi / 4, 2.0),
    (3 * pi / 4, 5 * pi / 6, 1.0),
    (5 * pi / 6, pi, 0.0),
  ];

  static const int routesPerRowInStopArrivalsTable = 8;

  static final List<CityConfig> cities = [
    CityConfig(
      name: "Iasi",
      center: LatLng(47.162121, 27.587573),
      initialZoom: 14.25,
      minZoom: 12,
      maxZoom: 19,
      bounds: LatLngBounds(LatLng(47.35, 27.33), LatLng(47.00, 27.82)),
      agencyId: '1',
    ),
    CityConfig(
      name: "Cluj-Napoca",
      center: LatLng(46.770439, 23.591423),
      initialZoom: 14,
      minZoom: 12,
      maxZoom: 19,
      bounds: LatLngBounds(LatLng(46.91, 23.33), LatLng(46.62, 23.85)),
      agencyId: '2',
    ),

    CityConfig(
      name: "Chisinau",
      center: LatLng(47.023621, 28.833862),
      initialZoom: 14,
      minZoom: 12,
      maxZoom: 19,
      bounds: LatLngBounds(LatLng(47.25, 28.58), LatLng(46.80, 29.07)),
      agencyId: '4',
    ),

    CityConfig(
      name: "Botosani",
      center: LatLng(47.739867, 26.663183),
      initialZoom: 14,
      minZoom: 12,
      maxZoom: 19,
      bounds: LatLngBounds(LatLng(47.95, 26.43), LatLng(47.50, 26.87)),
      agencyId: '6',
    ),

    CityConfig(
      name: "Timisoara",
      center: LatLng(45.756659, 21.235592),
      initialZoom: 14,
      minZoom: 12,
      maxZoom: 19,
      bounds: LatLngBounds(LatLng(45.95, 20.98), LatLng(45.55, 21.52)),
      agencyId: '8',
    ),
  ];

  static const List<String> availableCityNames = [
    "Cluj-Napoca",
    "Iasi",
    "Timisoara",
    "Chisinau",
    "Botosani",
  ];

  static const List<String> cityNamesWithVineriVerde = ["Cluj-Napoca"];

  static const List<String> agencyIdsWithWorkingTimetables = ["2"];

  ///
}

double calculateFontSize(double screenWidth, double baseSize) {
  if (screenWidth >= 1080) {
    return (baseSize + Constants.largeScreenBonusSize).sp;
  }

  return (baseSize + Constants.smallScreenBonusSize).sp;
}

int compareRouteNames(String routeA, String routeB) {
  // ca si in python, practic ideea e sortarea pe grupuri, literele de la inceput daca exista
  // apoi numarul din mijloc daca exista, si apoi literele de la final daca exista

  final a = routeA.toUpperCase().trim();
  final b = routeB.toUpperCase().trim();

  final patternNumPrefix = RegExp(r'^(\d+)([^0-9\s]*)$');
  final patternAlphaNum = RegExp(r'^([^0-9\s]+)(\d+)([^0-9\s]*)$');

  final matchA1 = patternNumPrefix.firstMatch(a);
  final matchB1 = patternNumPrefix.firstMatch(b);

  if (matchA1 != null && matchB1 != null) {
    final numA = int.parse(matchA1.group(1)!);
    final numB = int.parse(matchB1.group(1)!);

    if (numA != numB) return numA.compareTo(numB);
    return (matchA1.group(2) ?? '').compareTo(matchB1.group(2) ?? '');
  }

  final matchA2 = patternAlphaNum.firstMatch(a);
  final matchB2 = patternAlphaNum.firstMatch(b);

  final rankA = matchA1 != null ? 0 : (matchA2 != null ? 1 : 2);
  final rankB = matchB1 != null ? 0 : (matchB2 != null ? 1 : 2);
  if (rankA != rankB) return rankA.compareTo(rankB);

  if (matchA2 != null && matchB2 != null) {
    final prefixA = matchA2.group(1)!;
    final prefixB = matchB2.group(1)!;

    final cmpPrefix = prefixA.compareTo(prefixB);
    if (cmpPrefix != 0) return cmpPrefix;

    final numA = int.parse(matchA2.group(2)!);
    final numB = int.parse(matchB2.group(2)!);
    if (numA != numB) return numA.compareTo(numB);

    return (matchA2.group(3) ?? '').compareTo(matchB2.group(3) ?? '');
  }

  return a.compareTo(b);
}

String getEtaMessage(double eta) {
  if (eta == Constants.unknownEtaMinutes) return "? min";

  // doar in caz de erori cu nr negative care nu ar trebui sa apara
  final minEta = max(0, (eta - 0.5).floor());
  final maxEta = min(60, max(1, (eta + 1).ceil()));

  String etaMessage = "$minEta - $maxEta min";

  if (maxEta > 25 || minEta > 20) {
    etaMessage = ">20 min";
  }

  return etaMessage;
}

String formattedTime(DateTime? time) {
  if (time == null) return "?";
  return "${time.hour.toString().padLeft(2, '0')}:"
      "${time.minute.toString().padLeft(2, '0')}:"
      "${time.second.toString().padLeft(2, '0')}";
}

CityConfig getCityConfig(String cityName) {
  return Constants.cities.firstWhere(
    (city) => city.name == cityName,
    orElse: () => Constants.cities.first,
  );
}

String getAgencyIdForCity(String cityName) {
  return getCityConfig(cityName).agencyId;
}

IconData getIconForVehicleType(int vehicleType) {
  switch (vehicleType) {
    case 0:
      return Icons.tram; // Tram, Streetcar, Light rail
    case 1:
      return Icons.subway; // Subway, Metro
    case 2:
      return Icons.train; // Rail
    case 3:
      return Icons.directions_bus; // Bus
    case 4:
      return Icons.directions_ferry; // Ferry
    case 5:
      return Icons.tram; // Cable tram
    case 6:
      return Icons.airline_seat_flat; // Aerial lift
    case 7:
      return Icons.directions_railway; // Funicular
    case 11:
      return Icons.directions_bus_filled; // Trolleybus
    case 12:
      return Icons.train; // Monorail
    default:
      return Icons.directions_bus; // Default bus icon
  }
}

double computeArrowOffset(double bearing, double routeNameLength) {
  for (final (start, end, bonusPower) in Constants.ranges) {
    if (bearing >= start && bearing < end) {
      return pow(routeNameLength, bonusPower).toDouble();
    }
  }

  return 0.0;
}

Future<Position> determinePosition() async {
  bool serviceEnabled;
  LocationPermission permission;

  serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    return Future.error("Location services are disabled.");
  }

  permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      return Future.error("Location permissions are denied.");
    }
  }

  if (permission == LocationPermission.deniedForever) {
    return Future.error(
      "Location permissions are permanently denied, we cannot request permissions.",
    );
  }

  return await Geolocator.getCurrentPosition(
    // locationSettings: LocationSettings(
    //   accuracy: LocationAccuracy.high,
    //   distanceFilter: 3,
    // ),
  );
}

double calculateBearing(LatLng start, LatLng end) {
  final double lat1 = start.latitudeInRad;
  final double lon1 = start.longitudeInRad;

  final double lat2 = end.latitudeInRad;
  final double lon2 = end.longitudeInRad;

  final double y = sin(lon2 - lon1) * cos(lat2);
  final double x =
      cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(lon2 - lon1);

  return atan2(y, x);
}

Map<String, String?> computeClosestStops(VehicleStopsInfo infoMap) {
  final double vehLat = infoMap.latitude;
  final double vehLon = infoMap.longitude;

  final List<StopDistanceInfo> stopsDistanceInfo = infoMap.stopsDistanceInfo;
  final List<double> shapeCumDistances = infoMap.shapeCumDistances;
  final List<LatLng> shapePoints = infoMap.shapePoints;

  int closestPointIndex = 0;
  double minDist = double.infinity;

  for (int i = 0; i < shapePoints.length; i++) {
    final point = shapePoints[i];
    final dist = Geolocator.distanceBetween(
      vehLat,
      vehLon,
      point.latitude,
      point.longitude,
    );

    if (dist < minDist) {
      minDist = dist;
      closestPointIndex = i;
    }
  }

  final double distToVehicle = shapeCumDistances[closestPointIndex];

  String? previous, next;

  // + 25 in caz ca e fix langa statie
  int nextStopIndex = stopsDistanceInfo.indexWhere(
    (info) => info.distanceAlongRoute >= distToVehicle + 25,
  );

  if (nextStopIndex >= 0) next = stopsDistanceInfo[nextStopIndex].stop.stopName;
  if (nextStopIndex > 0) {
    previous = stopsDistanceInfo[nextStopIndex - 1].stop.stopName;
  }

  return {'previous': previous, 'next': next};
}
