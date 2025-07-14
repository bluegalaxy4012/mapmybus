import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';

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
  final int vehicleType;
  final Accessibility bikeAccessible;
  final Accessibility wheelchairAccessible;

  Vehicle({
    required this.id,
    required this.label,
    this.latitude,
    this.longitude,
    required this.timestamp,
    this.speed,
    this.routeId,
    this.tripId,
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
        print('Eroare la parsarea timestamp-ului: $e');
        return DateTime.now();
      }
    }

    return Vehicle(
      id: json['id'] as int,
      label: json['label'] as String,
      latitude: json['latitude'] != null
          ? (json['latitude'] as num).toDouble()
          : null,
      longitude: json['longitude'] != null
          ? (json['longitude'] as num).toDouble()
          : null,
      timestamp: parseTimestamp(json['timestamp'] as String?),
      speed: json['speed'] != null ? (json['speed'] as num).toInt() : null,
      routeId: json['route_id'] as int?,
      tripId: json['trip_id'] as String?,
      vehicleType: json['vehicle_type'] as int,
      bikeAccessible: parseAccessibility(json['bike_accessible'] as String?),
      wheelchairAccessible: parseAccessibility(
        json['wheelchair_accessible'] as String?,
      ),
    );
  }
}

class Route {
  final String agencyId;
  final int routeId;
  final String routeShortName;
  final String routeLongName;
  final Color routeColor; // Store as Color
  final int routeType;
  final String routeDesc;
  bool isFavorite;

  Route({
    required this.agencyId,
    required this.routeId,
    required this.routeShortName,
    required this.routeLongName,
    required this.routeColor,
    required this.routeType,
    required this.routeDesc,
    this.isFavorite = false,
  });

  factory Route.fromJson(Map<String, dynamic> json) {
    Color color;

    // unele il au gresit oricum (#000)
    try {
      String hexString = json['route_color'].toString().replaceAll('#', '');

      if (hexString.length == 6) {
        hexString = 'FF$hexString';
      } else if (hexString.length != 8) {
        throw FormatException(
          'Lungime invalida a string-ului hex pentru culoare: $hexString',
        );
      }

      color = Color(int.parse(hexString, radix: 16));
    } catch (e) {
      color = Colors.grey;
      print(
        'Eroare la parsarea culorii pentru ruta ${json['route_short_name']}: $e. Se foloseste gri implicit.',
      );
    }

    return Route(
      agencyId: json['agency_id'] as String,
      routeId: json['route_id'] as int,
      routeShortName: json['route_short_name'] as String,
      routeLongName: json['route_long_name'] as String,
      routeColor: color,
      routeType: json['route_type'] as int,
      routeDesc: json['route_desc'] as String,
      isFavorite: false,
    );
  }
}

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

final List<CityConfig> cities = [
  CityConfig(
    name: "Cluj-Napoca",
    center: LatLng(46.770439, 23.591423),
    initialZoom: 14,
    minZoom: 13,
    maxZoom: 19,
    bounds: LatLngBounds(LatLng(46.83, 23.44), LatLng(46.72, 23.74)),
    agencyId: '2',
  ),
];

class Stop {
  final String stopId;
  final String stopName;
  final double latitude;
  final double longitude;

  Stop({
    required this.stopId,
    required this.stopName,
    required this.latitude,
    required this.longitude,
  });

  factory Stop.fromJson(Map<String, dynamic> json) {
    return Stop(
      stopId: json['stop_id'] as String,
      stopName: json['stop_name'] as String,
      latitude: (json['stop_lat'] as num).toDouble(),
      longitude: (json['stop_lon'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'stop_id': stopId,
      'stop_name': stopName,
      'stop_lat': latitude,
      'stop_lon': longitude,
    };
  }
}

class TripStop {
  final String tripId;
  final String stopId;
  final int stopSequence;

  TripStop({
    required this.tripId,
    required this.stopId,
    required this.stopSequence,
  });

  factory TripStop.fromJson(Map<String, dynamic> json) {
    return TripStop(
      tripId: json['trip_id'] as String,
      stopId: json['stop_id'] as String,
      stopSequence: (json['stop_sequence'] as num).toInt(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'trip_id': tripId,
      'stop_id': stopId,
      'stop_sequence': stopSequence,
    };
  }
}

class ShapePoint {
  final String shapeId;
  final double latitude;
  final double longitude;
  final int sequence;

  ShapePoint({
    required this.shapeId,
    required this.latitude,
    required this.longitude,
    required this.sequence,
  });

  factory ShapePoint.fromJson(Map<String, dynamic> json) {
    return ShapePoint(
      shapeId: json['shape_id'] as String,
      latitude: (json['shape_pt_lat'] as num).toDouble(),
      longitude: (json['shape_pt_lon'] as num).toDouble(),
      sequence: (json['shape_pt_sequence'] as num).toInt(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'shape_id': shapeId,
      'shape_pt_lat': latitude,
      'shape_pt_lon': longitude,
      'shape_pt_sequence': sequence,
    };
  }
}
