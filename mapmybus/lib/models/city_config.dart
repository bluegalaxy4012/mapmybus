import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';

class CityConfig {
  final String name;
  final LatLng center;
  final double initialZoom;
  final double minZoom;
  final double maxZoom;
  final LatLngBounds bounds;
  final String agencyId;

  const CityConfig({
    required this.name,
    required this.center,
    required this.initialZoom,
    required this.minZoom,
    required this.maxZoom,
    required this.bounds,
    required this.agencyId,
  });
}
