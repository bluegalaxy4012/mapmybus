import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:hive_flutter/hive_flutter.dart';
import 'models.dart';

class DbService {
  static const String _stopsBoxName = 'stops';
  static const String _tripStopsBoxName = 'trip_stops';
  static const String _shapesBoxName = 'shapes';

  Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox(_stopsBoxName);
    await Hive.openBox(_tripStopsBoxName);
    await Hive.openBox(_shapesBoxName);

    final stopsBox = Hive.box(_stopsBoxName);

    if (stopsBox.isEmpty) {
      final stopsJson = await rootBundle.loadString('data/stops.json');
      final stopsList = jsonDecode(stopsJson) as List;
      for (var stop in stopsList) {
        await stopsBox.put(
          stop['stop_id'].toString(),
          Map<String, dynamic>.from(stop),
        );
      }

      print('loaded ${stopsList.length} stops into Hive');
    }

    final tripStopsBox = Hive.box(_tripStopsBoxName);

    if (tripStopsBox.isEmpty) {
      final tripStopsJson = await rootBundle.loadString('data/trip_stops.json');
      final tripStopsList = jsonDecode(tripStopsJson) as List;
      for (var ts in tripStopsList) {
        await tripStopsBox.put(
          '${ts['trip_id']}_${ts['stop_id'].toString()}',
          Map<String, dynamic>.from(ts),
        );
      }

      print('loaded ${tripStopsList.length} trip_stops into Hive');
    }

    final shapesBox = Hive.box(_shapesBoxName);

    if (shapesBox.isEmpty) {
      final shapesJson = await rootBundle.loadString('data/shapes.json');
      final shapesList = jsonDecode(shapesJson) as List;
      for (var shape in shapesList) {
        await shapesBox.put(
          shape['shape_id'].toString(),
          (shape['points'] as List)
              .map((p) => Map<String, dynamic>.from(p))
              .toList(),
        );
      }

      print(
        'loaded ${shapesList.length} shapes with ${shapesList.fold<int>(0, (sum, shape) => sum + (shape['points'] as List).length)} points into Hive',
      );
    }
  }

  Future<List<Stop>> getStopsForTrip(String tripId) async {
    final tripStopsBox = Hive.box(_tripStopsBoxName);
    final stopsBox = Hive.box(_stopsBoxName);

    final tripStops =
        tripStopsBox.values.where((ts) => ts['trip_id'] == tripId).toList()
          ..sort(
            (a, b) => (a['stop_sequence'] as int).compareTo(
              b['stop_sequence'] as int,
            ),
          );

    return tripStops.map((ts) {
      final stopRaw = stopsBox.get(ts['stop_id'].toString());
      final stopMap = Map<String, dynamic>.from(stopRaw);
      return Stop.fromJson(stopMap);
    }).toList();
  }

  Future<List<ShapePoint>> getShape(String shapeId) async {
    final shapesBox = Hive.box(_shapesBoxName);
    final pointsRaw = shapesBox.get(shapeId, defaultValue: []) as List;

    return pointsRaw.map((point) {
      final pointMap = Map<String, dynamic>.from(point);
      return ShapePoint.fromJson(pointMap);
    }).toList()..sort((a, b) => a.sequence.compareTo(b.sequence));
  }
}
