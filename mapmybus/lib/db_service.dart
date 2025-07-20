import 'dart:convert';
// import 'package:flutter/services.dart' show rootBundle;
// import 'package:hive_flutter/hive_flutter.dart';
import 'package:csv/csv.dart';
import 'package:mapmybus/config.dart';
import 'package:mapmybus/utils.dart';
// import 'package:mapmybus/utils.dart';
import 'models.dart';
// import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class DbService {
  Future<List<Vehicle>?> fetchVehicles(String agencyId) async {
    final uri = Uri.parse('${AppConfig.vehiclesApiUrl}/$agencyId');

    try {
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final List<dynamic> jsonData = jsonDecode(response.body);
        final List<Vehicle> vehicles = jsonData.map((json) {
          return Vehicle.fromJson(json);
        }).toList();

        log.d("Fetched ${vehicles.length} vehicles for agency $agencyId");

        return vehicles;
      }
    } catch (e) {
      print('error fetching vehicles: $e');
      // handle
    }

    return null;
  }

  /// throws exception
  Future<List<Stop>> getStopsForTrip(String tripId, String agencyId) async {
    final uri = Uri.parse('${AppConfig.stopsApiUrl}/$agencyId?trip_id=$tripId');

    final response = await http.get(uri);

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);

      log.d("Fetched ${data.length} stops for trip $tripId");

      return data.map((stop) => Stop.fromJson(stop)).toList();
    }

    throw Exception('Failed to fetch stops: ${response.statusCode}');
  }

  /// throws exception
  Future<List<ShapePoint>> getShape(String shapeId, String agencyId) async {
    final uri = Uri.parse(
      '${AppConfig.shapesApiUrl}/$agencyId?shape_id=$shapeId',
    );

    final response = await http.get(uri);

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);

      log.d("Fetched ${data.length} shape points for shape $shapeId");

      return data.map((point) => ShapePoint.fromJson(point)).toList();
    }

    throw Exception('Failed to fetch shapes: ${response.statusCode}');
  }

  /// throws exception
  Future<List<dynamic>> getEtas(
    Vehicle vehicle,
    List<String> stopIds,
    String agencyId,
  ) async {
    final Uri uri = Uri.parse('${AppConfig.etasApiUrl}/$agencyId').replace(
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
        'Failed to fetch etas - response code ${response.statusCode}',
      );
    }
  }

  /// throws exception
  Future<List<List<dynamic>>> getTimetable(
    String routeShortName,
    String dayType,
  ) async {
    final url = '${AppConfig.timetablesApiUrl}/$routeShortName/$dayType';

    final res = await http.get(Uri.parse(url));
    if (res.statusCode == 200) {
      log.d("Fetched timetable for route $routeShortName on day $dayType");

      return const CsvToListConverter(
        eol: "\n",
      ).convert(utf8.decode(res.bodyBytes));
    }

    throw Exception('Failed to fetch timetable: ${res.statusCode}');
  }
}
