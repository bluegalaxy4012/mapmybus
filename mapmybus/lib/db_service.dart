import 'dart:convert';
// import 'package:flutter/services.dart' show rootBundle;
// import 'package:hive_flutter/hive_flutter.dart';
import 'package:mapmybus/utils.dart';
import 'models.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;


// to fix:
// apikey in header
// spread
// getEtas remake models
// fetch on build
class DbService {

  Future<void> init() async {
    await dotenv.load(fileName: ".env");
    stopsApiUrl = dotenv.env['STOPS_API_URL'] ?? '';
    shapesApiUrl = dotenv.env['SHAPES_API_URL'] ?? '';
    etasApiUrl = dotenv.env['ETAS_API_URL'] ?? '';
  }

    Future<List<Stop>> getStopsForTrip(String tripId, String agencyId) async {
    final uri = Uri.parse('$stopsApiUrl/$agencyId?trip_id=$tripId');
    final response = await http.get(uri, headers: {
      'X-Agency-Id': agencyId,
      'Accept': 'application/json',
      'X-API-KEY': dotenv.env['API_KEY'] ?? '',
    });
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      print("first stop: ${data.first}");
      return data.map((stop) => Stop.fromJson(stop)).toList();
    }
    throw Exception('Failed to fetch stops: ${response.statusCode}');
  }

  Future<List<ShapePoint>> getShape(String shapeId, String agencyId) async {
    final uri = Uri.parse('$shapesApiUrl/$agencyId?shape_id=$shapeId');
    final response = await http.get(uri, headers: {
      'X-Agency-Id': agencyId,
      'Accept': 'application/json',
      'X-API-KEY': dotenv.env['API_KEY'] ?? '',
    });
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      print("first shape point: ${data.first}");
      return data.map((point) => ShapePoint.fromJson(point)).toList();
    }
    throw Exception('Failed to fetch shapes: ${response.statusCode}');
  }


  Future<List<Vehicle>?> fetchVehicles(String agencyId) async {
    const url = tranzyVehiclesEndpoint;
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'X-Agency-Id': agencyId,
          'Accept': 'application/json',
          'X-API-KEY': dotenv.env['API_KEY'] ?? '',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> jsonData = jsonDecode(response.body);
        final List<Vehicle> vehicles = jsonData.map((json) {
          return Vehicle.fromJson(json);
        }).toList();

        print('fetched ${vehicles.length} vehicles for agency $agencyId');

        return vehicles;
      }
    } catch (e) {
      print('error fetching vehicles: $e');
      // handle
    }

    return null;
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
