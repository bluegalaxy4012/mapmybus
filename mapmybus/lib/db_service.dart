import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:mapmybus/config.dart';
import 'package:mapmybus/utils.dart';
import 'package:http/http.dart' as http;

import 'models.dart';

class DbService {
  Future<Result<List<Vehicle>, Exception>> fetchVehicles(
    String agencyId,
  ) async {
    final uri = Uri.parse('${AppConfig.vehiclesApiUrl}/$agencyId');

    try {
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final List<dynamic> jsonData = jsonDecode(response.body);
        final List<Vehicle> vehicles = jsonData.map((json) {
          return Vehicle.fromJson(json);
        }).toList();

        log.d("Fetched ${vehicles.length} vehicles for agency $agencyId");

        return Success(vehicles);
      } else {
        return Failure(ApiException("Server error", response.statusCode));
      }
    } catch (e) {
      return Failure(Exception("Unexpected error: $e"));
    }
  }

  Future<Result<List<Route>, Exception>> fetchRoutes(String agencyId) async {
    final uri = Uri.parse('${AppConfig.routesApiUrl}/$agencyId');

    try {
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final List<dynamic> jsonData = jsonDecode(response.body);
        final List<Route> routes = jsonData.map((json) {
          return Route.fromJson(json);
        }).toList();

        log.d("Fetched ${routes.length} routes for agency $agencyId");
        return Success(routes);
      } else {
        return Failure(ApiException("Server error", response.statusCode));
      }
    } catch (e) {
      return Failure(Exception("Unexpected error: $e"));
    }
  }

  Future<Result<List<Stop>, Exception>> getStopsForTrip(
    String tripId,
    String agencyId,
  ) async {
    final uri = Uri.parse('${AppConfig.stopsApiUrl}/$agencyId?trip_id=$tripId');

    try {
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);

        log.d("Fetched ${data.length} stops for trip $tripId");

        return Success(data.map((stop) => Stop.fromJson(stop)).toList());
      } else {
        return Failure(
          ApiException(
            "Server error during stops for trip fetch",
            response.statusCode,
          ),
        );
      }
    } catch (e) {
      return Failure(Exception("Unexpected error: $e"));
    }
  }

  Future<Result<List<Stop>, Exception>> getStops(String agencyId) async {
    final uri = Uri.parse('${AppConfig.stopsApiUrl}/$agencyId');

    try {
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);

        log.d("Fetched ${data.length} stops");

        return Success(data.map((stop) => Stop.fromJson(stop)).toList());
      } else {
        return Failure(
          ApiException("Server error during stops fetch", response.statusCode),
        );
      }
    } catch (e) {
      return Failure(Exception("Unexpected error: $e"));
    }
  }

  Future<Result<List<ShapePoint>, Exception>> getShape(
    String shapeId,
    String agencyId,
  ) async {
    final uri = Uri.parse(
      '${AppConfig.shapesApiUrl}/$agencyId?shape_id=$shapeId',
    );

    try {
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);

        log.d("Fetched ${data.length} shape points for shape $shapeId");

        return Success(
          data.map((point) => ShapePoint.fromJson(point)).toList(),
        );
      } else {
        return Failure(
          ApiException("Server error during shapes fetch", response.statusCode),
        );
      }
    } catch (e) {
      return Failure(Exception("Unexpected error: $e"));
    }
  }

  Future<Result<List<Eta>, Exception>> getEtas(
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

    try {
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List<dynamic>;

        return Success(data.map((json) => Eta.fromJson(json)).toList());
      } else {
        throw ApiException(
          "Server error during ETAs fetch",
          response.statusCode,
        );
      }
    } catch (e) {
      return Failure(Exception("Unexpected error: $e"));
    }
  }

  // momentan doar pentru Cluj-Napoca
  Future<Result<List<List<String>>, Exception>> getTimetable(
    String routeShortName,
    String dayType,
  ) async {
    final url = '${AppConfig.timetablesApiUrl}/$routeShortName/$dayType';

    try {
      final res = await http.get(Uri.parse(url));

      if (res.statusCode == 200) {
        log.d("Fetched timetable for route $routeShortName on day $dayType");

        return Success(
          const CsvToListConverter(
            eol: "\n",
            shouldParseNumbers: false,
          ).convert(utf8.decode(res.bodyBytes)),
        );
      } else {
        return Failure(
          ApiException("Server error during timetables fetch", res.statusCode),
        );
      }
    } catch (e) {
      return Failure(Exception("Unexpected error: $e"));
    }
  }

  Future<Result<List<Arrival>, Exception>> getSoonArrivalsForStop(
    String agencyId,
    String stopId,
    List<Map<String, dynamic>> vehiclePositions, {
    int n = 5,
  }) async {
    final url = Uri.parse(
      '${AppConfig.arrivalsApiUrl}/$agencyId/arrivals/$stopId',
    );

    try {
      final response = await http.post(
        url.replace(queryParameters: {'n': n.toString()}),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(vehiclePositions),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);

        log.d(
          "Fetched ${data.length} soon-arrival predictions for stop $stopId",
        );

        return Success(data.map((json) => Arrival.fromJson(json)).toList());
      } else {
        return Failure(
          ApiException(
            "Server error during arrivals for stop fetch",
            response.statusCode,
          ),
        );
      }
    } catch (e) {
      return Failure(Exception("Unexpected error: $e"));
    }
  }
}
