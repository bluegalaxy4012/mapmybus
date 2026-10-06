import 'package:mapmybus/core/utils.dart';

enum Accessibility {
  bikeAccessible,
  bikeInaccessible,
  wheelchairAccessible,
  wheelchairInaccessible,
  unknown,
}

class Vehicle {
  final int id;
  final String label;
  final double? latitude;
  final double? longitude;
  final DateTime timestamp;
  final int? speed;
  final int? routeId;
  final String? tripId;
  final double? firstStopLatitude, firstStopLongitude;
  final double? lastStopLatitude, lastStopLongitude;
  final String? firstStopName;
  final String? lastStopName;
  final bool isGhost;
  final int vehicleType;
  final Accessibility bikeAccessible;
  final Accessibility wheelchairAccessible;

  const Vehicle({
    required this.id,
    required this.label,
    this.latitude,
    this.longitude,
    required this.timestamp,
    this.speed,
    this.routeId,
    this.tripId,
    this.firstStopLatitude,
    this.firstStopLongitude,
    this.lastStopLatitude,
    this.lastStopLongitude,
    this.firstStopName,
    this.lastStopName,
    required this.isGhost,
    required this.vehicleType,
    required this.bikeAccessible,
    required this.wheelchairAccessible,
  });

  factory Vehicle.fromJson(Map<String, dynamic> json) {
    Accessibility parseAccessibility(String? value) {
      if (value == null) return Accessibility.unknown;

      switch (value) {
        case 'BIKE_ACCESSIBLE':
          return Accessibility.bikeAccessible;
        case 'BIKE_INACCESSIBLE':
          return Accessibility.bikeInaccessible;
        case 'WHEELCHAIR_ACCESSIBLE':
          return Accessibility.wheelchairAccessible;
        case 'WHEELCHAIR_INACCESSIBLE':
          return Accessibility.wheelchairInaccessible;
        default:
          return Accessibility.unknown;
      }
    }

    DateTime parseTimestamp(String? timestamp) {
      if (timestamp == null) return DateTime.now();
      try {
        return DateTime.parse(timestamp);
      } catch (e) {
        log.w("Eroare la parsarea timestamp-ului: $e");
        return DateTime.now();
      }
    }

    int parseInt(dynamic integer) {
      if (integer is int) return integer;
      if (integer is num) return integer.toInt();
      if (integer is String) {
        return int.tryParse(integer) ?? 0;
      }

      return 0;
    }

    return Vehicle(
      id: parseInt(json['id']),
      label: json['label'] as String,
      latitude: json['latitude'] != null
          ? (json['latitude'] as num).toDouble()
          : null,
      longitude: json['longitude'] != null
          ? (json['longitude'] as num).toDouble()
          : null,
      timestamp: parseTimestamp(json['timestamp'] as String?),
      speed: json['speed'] != null ? parseInt(json['speed']) : null,
      routeId: json['route_id'] != null ? parseInt(json['route_id']) : null,
      tripId: json['trip_id'] as String?,
      firstStopLatitude: json['first_stop_lat'] != null
          ? (json['first_stop_lat'] as num).toDouble()
          : null,
      firstStopLongitude: json['first_stop_lon'] != null
          ? (json['first_stop_lon'] as num).toDouble()
          : null,
      lastStopLatitude: json['last_stop_lat'] != null
          ? (json['last_stop_lat'] as num).toDouble()
          : null,
      lastStopLongitude: json['last_stop_lon'] != null
          ? (json['last_stop_lon'] as num).toDouble()
          : null,
      firstStopName: json['first_stop_name'] as String?,
      lastStopName: json['last_stop_name'] as String?,
      isGhost: json['is_ghost'] == true,
      vehicleType: parseInt(json['vehicle_type']),
      bikeAccessible: parseAccessibility(json['bike_accessible'] as String?),
      wheelchairAccessible: parseAccessibility(
        json['wheelchair_accessible'] as String?,
      ),
    );
  }
}

class VehicleWithDistance {
  final Vehicle vehicle;
  final double distance;

  const VehicleWithDistance(this.vehicle, this.distance);
}
