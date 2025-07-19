import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

// constants
  const String stopsBoxName = 'stops';
  const String tripStopsBoxName = 'trip_stops';
  const String shapesBoxName = 'shapes';
  late String etasApiUrl;
  const String routesAssetPath = 'data/routes.json';
const String stopsAssetPath = 'data/stops.json';
const String tripStopsAssetPath = 'data/trip_stops.json';
const String shapesAssetPath = 'data/shapes.json';


const String tranzyApiBaseUrl = 'https://api.tranzy.ai/v1/opendata';
const String tranzyVehiclesEndpoint = '$tranzyApiBaseUrl/vehicles';
const String mapTileProviderUrl = 'https://{s}.basemaps.cartocdn.com/rastertiles/light_all/{z}/{x}/{y}.png';
//

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
