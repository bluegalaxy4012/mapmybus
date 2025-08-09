import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:mapmybus/utils.dart';

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

  const Vehicle({
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
        log.w("Eroare la parsarea timestamp-ului: $e");
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
  final Color routeColor;
  final int routeType;
  final String routeDesc;
  final bool isFavorite;

  const Route({
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

    try {
      String hexString = json['route_color'].toString().replaceAll('#', '');

      if (hexString.length == 6) {
        hexString = 'FF$hexString';
      } else if (hexString.length == 3) {
        hexString =
            'FF${hexString[0]}${hexString[0]}'
            '${hexString[1]}${hexString[1]}'
            '${hexString[2]}${hexString[2]}';
      } else if (hexString.length != 8) {
        throw FormatException(
          "Lungime invalida a string-ului hex pentru culoare: $hexString",
        );
      }

      color = Color(int.parse(hexString, radix: 16));

      // folosim portocaliu si in loc de negru si alb
      if (color == Colors.black || color == Colors.white) {
        color = Colors.orangeAccent;
      }
    } catch (e) {
      color = Colors.orangeAccent;
      log.w(
        "Eroare la parsarea culorii pentru ruta ${json['route_short_name']}: $e. Se foloseste portocaliu implicit",
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

  Route copyWith({
    String? agencyId,
    int? routeId,
    String? routeShortName,
    String? routeLongName,
    Color? routeColor,
    int? routeType,
    String? routeDesc,
    bool? isFavorite,
  }) {
    return Route(
      agencyId: agencyId ?? this.agencyId,
      routeId: routeId ?? this.routeId,
      routeShortName: routeShortName ?? this.routeShortName,
      routeLongName: routeLongName ?? this.routeLongName,
      routeColor: routeColor ?? this.routeColor,
      routeType: routeType ?? this.routeType,
      routeDesc: routeDesc ?? this.routeDesc,
      isFavorite: isFavorite ?? this.isFavorite,
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

class Stop {
  final String stopId;
  final String stopName;
  final double latitude;
  final double longitude;

  const Stop({
    required this.stopId,
    required this.stopName,
    required this.latitude,
    required this.longitude,
  });

  factory Stop.fromJson(Map<String, dynamic> json) {
    return Stop(
      stopId: json['stop_id'].toString(),
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

  const TripStop({
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

  const ShapePoint({
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

class Eta {
  final String tripId;
  final String stopId;
  final double predictedEtaMinutes;
  final String message;

  const Eta({
    required this.tripId,
    required this.stopId,
    required this.predictedEtaMinutes,
    required this.message,
  });

  factory Eta.fromJson(Map<String, dynamic> json) => Eta(
    tripId: json['trip_id'] as String,
    stopId: json['stop_id'].toString(),
    predictedEtaMinutes: (json['predicted_eta_minutes'] as num).toDouble(),
    message: json['message'] as String,
  );
}

class Arrival {
  final String tripId;
  final String? vehicleLabel;
  final double etaMinutes;
  final String message;

  const Arrival({
    required this.tripId,
    this.vehicleLabel,
    required this.etaMinutes,
    required this.message,
  });

  factory Arrival.fromJson(Map<String, dynamic> json) {
    return Arrival(
      tripId: json['trip_id'] as String,
      vehicleLabel: json['vehicle_label'] as String?,
      etaMinutes: (json['predicted_eta_minutes'] as num).toDouble(),
      message: json['message'] as String,
    );
  }
}

class StopDistanceInfo {
  final Stop stop;
  final double distanceAlongRoute;

  const StopDistanceInfo({
    required this.stop,
    required this.distanceAlongRoute,
  });
}

class VehicleStopsInfo {
  final double latitude;
  final double longitude;
  final List<StopDistanceInfo> stopsDistanceInfo;
  final List<LatLng> shapePoints;
  final List<double> shapeCumDistances;

  const VehicleStopsInfo({
    required this.latitude,
    required this.longitude,
    required this.stopsDistanceInfo,
    required this.shapePoints,
    required this.shapeCumDistances,
  });
}

class EtaDisplayInfo {
  final String stopName;
  final String etaMessage;

  EtaDisplayInfo({required this.stopName, required this.etaMessage});
}

class StopArrivalDisplayInfo {
  final String routeShortName;
  final String etaMessage;

  StopArrivalDisplayInfo(this.routeShortName, this.etaMessage);
}

// results

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
