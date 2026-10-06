import 'package:flutter/material.dart';
import 'package:mapmybus/core/utils.dart';

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
