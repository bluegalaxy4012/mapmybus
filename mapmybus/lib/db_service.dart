import 'dart:convert';
// import 'package:flutter/services.dart' show rootBundle;
// import 'package:hive_flutter/hive_flutter.dart';
import 'package:csv/csv.dart';
import 'package:mapmybus/config.dart';
// import 'package:mapmybus/utils.dart';
import 'models.dart';
// import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

// to fix:
// apikey in header
// spread
// getEtas remake models
// fetch on build
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

        // print('fetched ${vehicles.length} vehicles for agency $agencyId');

        // print(
        //   'first vehicle: ${vehicles.first}, tripId: ${vehicles.first.tripId}, lat: ${vehicles.first.latitude}, lon: ${vehicles.first.longitude}',
        // );

        return vehicles;
      }
    } catch (e) {
      print('error fetching vehicles: $e');
      // handle
    }

    return null;
  }

  Future<List<Stop>> getStopsForTrip(String tripId, String agencyId) async {
    final uri = Uri.parse('${AppConfig.stopsApiUrl}/$agencyId?trip_id=$tripId');

    final response = await http.get(uri);

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      // print("first stop: ${data.first}");
      return data.map((stop) => Stop.fromJson(stop)).toList();
    }

    throw Exception('Failed to fetch stops: ${response.statusCode}');
  }

  Future<List<ShapePoint>> getShape(String shapeId, String agencyId) async {
    final uri = Uri.parse(
      '${AppConfig.shapesApiUrl}/$agencyId?shape_id=$shapeId',
    );

    final response = await http.get(uri);

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      // print("first shape point: ${data.first}");
      return data.map((point) => ShapePoint.fromJson(point)).toList();
    }

    throw Exception('Failed to fetch shapes: ${response.statusCode}');
  }

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
        'failed to fetch etas - response code ${response.statusCode}',
      );
    }
  }

  Future<List<List<dynamic>>> getTimetable(
    String routeShortName,
    String dayType,
  ) async {
    final url = '${AppConfig.timetablesApiUrl}/$routeShortName/$dayType';

    final res = await http.get(Uri.parse(url));
    if (res.statusCode == 200) {
      return const CsvToListConverter(
        eol: "\n",
      ).convert(utf8.decode(res.bodyBytes));
    }

    throw Exception('Failed to fetch timetable: ${res.statusCode}');
  }
}
