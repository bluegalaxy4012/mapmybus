import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:logger/logger.dart';
import 'package:mapmybus/models.dart';

final log = Logger(level: kReleaseMode ? Level.off : Level.debug);

/// constants
///
// const String routesAssetPath = 'data/routes.json';
// const String stopsAssetPath = 'data/stops.json';
// const String tripStopsAssetPath = 'data/trip_stops.json';
// const String shapesAssetPath = 'data/shapes.json';

const String tranzyApiBaseUrl = 'https://api.tranzy.ai/v1/opendata';
const String tranzyVehiclesEndpoint = '$tranzyApiBaseUrl/vehicles';
const String mapTileProviderUrl =
    'https://{s}.basemaps.cartocdn.com/rastertiles/light_all/{z}/{x}/{y}.png';

const Duration snackBarDuration = Duration(milliseconds: 2500);

typedef Seconds = int;
const Seconds defaultRefreshInterval = 20;

const String tripDirectionInSuffix = '_0';
// const String tripDirectionOutSuffix = '_1';

const String appTitle = 'Map My Bus';
const String copyrightText = '© OpenStreetMap contributors, © CARTO';

// fontSizes candva
///
///

sealed class Result<S, E extends Exception> {
  const Result();
}

final class Success<S, E extends Exception> extends Result<S, E> {
  const Success(this.data);
  final S data;
}

final class Failure<S, E extends Exception> extends Result<S, E> {
  const Failure(this.exception);
  final E exception;
}

class ApiException implements Exception {
  final String message;
  final int statusCode;
  ApiException(this.message, this.statusCode);
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

Future<Position> determinePosition() async {
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
      return Future.error('Location permissions are denied.');
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
  // presupunand ca nu exista statii la care e mai rapid sa cobori cu cateva inainte si sa mergi pe jos decat sa stai

  // final double vehLat = infoMap['lat'];
  // final double vehLon = infoMap['lon'];
  final double vehLat = infoMap.latitude;
  final double vehLon = infoMap.longitude;

  final List<Stop> stops = infoMap.stops;

  // final List<dynamic> stops = infoMap['stops'];

  double minDist = double.infinity;
  int closestIndex = 0;

  for (int i = 0; i < stops.length; i++) {
    final stop = stops[i];
    final dist = Geolocator.distanceBetween(
      vehLat,
      vehLon,
      stop.latitude,
      stop.longitude,
    );

    if (dist < minDist) {
      minDist = dist;
      closestIndex = i;
    }
  }

  final double dist1 = Geolocator.distanceBetween(
    stops.first.latitude,
    stops.first.longitude,
    stops[closestIndex].latitude,
    stops[closestIndex].longitude,
  );

  final double dist2 = Geolocator.distanceBetween(
    stops.first.latitude,
    stops.first.longitude,
    vehLat,
    vehLon,
  );

  String? previous, next;

  if (dist1 >= dist2) {
    next = stops[closestIndex].stopName;
    previous = closestIndex > 0 ? stops[closestIndex - 1].stopName : null;
  } else {
    previous = stops[closestIndex].stopName;
    next = closestIndex < stops.length - 1
        ? stops[closestIndex + 1].stopName
        : null;
  }

  return {'previous': previous, 'next': next};
}
