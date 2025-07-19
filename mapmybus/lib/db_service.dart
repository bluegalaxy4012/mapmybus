import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mapmybus/utils.dart';
import 'models.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class DbService {
  static const String _stopsBoxName = stopsBoxName;
  static const String _tripStopsBoxName = tripStopsBoxName;
  static const String _shapesBoxName = shapesBoxName;

  Future<void> init() async {
    await dotenv.load(fileName: ".env");
    etasApiUrl = dotenv.env['ETAS_API_URL'] ?? '';

    await Hive.initFlutter();
    await Hive.openBox(_stopsBoxName);
    await Hive.openBox(_tripStopsBoxName);
    await Hive.openBox(_shapesBoxName);

    final stopsBox = Hive.box(_stopsBoxName);

    if (stopsBox.isEmpty) {
      final stopsJson = await rootBundle.loadString(stopsAssetPath);
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
      final tripStopsJson = await rootBundle.loadString(tripStopsAssetPath);
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
      final shapesJson = await rootBundle.loadString(shapesAssetPath);
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

  Future<List<dynamic>> getEtas(
    Vehicle vehicle,
    List<String> stopIds,
    String agencyId,
  ) async {
    final Uri uri = Uri.parse('$etasApiUrl/$agencyId').replace(
      queryParameters: {
        'trip_id': vehicle.tripId,
        'lat': vehicle.latitude.toString(),
        'lon': vehicle.longitude.toString(),
        'stop_ids': stopIds,
      },
    );

    final response = await http.get(uri);
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception(
        'failed to fetch etas - response code ${response.statusCode}',
      );
    }
  }
}
