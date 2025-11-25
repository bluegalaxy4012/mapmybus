import 'dart:async';
import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mapmybus/config.dart';
import 'package:mapmybus/utils.dart';
import 'package:http/http.dart' as http;
import 'package:retry/retry.dart';

import 'models.dart';

class DbService {
  // in caz de timeout-uri
  static const retryOptions = RetryOptions(
    maxAttempts: 3,
    delayFactor: Duration(seconds: 5),
  );

  Future<Result<List<Vehicle>, Exception>> fetchVehicles(
    String agencyId,
  ) async {
    final uri = Uri.parse('${AppConfig.vehiclesApiUrl}/$agencyId');

    try {
      final response = await retryOptions.retry(
        () => http.get(uri),
        retryIf: (e) => e is http.ClientException || e is TimeoutException,
      );

      if (response.statusCode == 200) {
        final List<dynamic> jsonData = jsonDecode(response.body);

        final List<Vehicle> vehicles = [];
        for (var vehicleJson in jsonData) {
          try {
            vehicles.add(Vehicle.fromJson(vehicleJson));
          } catch (e, st) {
            log.e("Failed to parse vehicle JSON: $vehicleJson, $e, $st");
          }
        }

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
      final response = await retryOptions.retry(
        () => http.get(uri),
        retryIf: (e) => e is http.ClientException || e is TimeoutException,
      );

      if (response.statusCode == 200) {
        final List<dynamic> jsonData = jsonDecode(response.body);
        final List<Route> routes = jsonData.map((json) {
          return Route.fromJson(json);
        }).toList();

        log.d("Fetched ${routes.length} routes for agency $agencyId");
        return Success(routes);
      } else {
        return Failure(
          ApiException("Server error during routes fetch", response.statusCode),
        );
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
      final response = await retryOptions.retry(
        () => http.get(uri),
        retryIf: (e) => e is http.ClientException || e is TimeoutException,
      );

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
      final response = await retryOptions.retry(
        () => http.get(uri),
        retryIf: (e) => e is http.ClientException || e is TimeoutException,
      );

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

  Future<Result<List<Stop>, Exception>> getNearbyStops(
    String agencyId,
    Position position,
    double radiusMeters,
  ) async {
    final stopsResult = await getStops(agencyId);

    switch (stopsResult) {
      case Success(data: final stops):
        double maxDist = 0;

        final nearbyStops = stops.where((stop) {
          final distance = Geolocator.distanceBetween(
            position.latitude,
            position.longitude,
            stop.latitude,
            stop.longitude,
          );

          if (distance > maxDist) {
            maxDist = distance;
          }

          return distance <= radiusMeters;
        }).toList();

        log.d(
          "Found ${nearbyStops.length} nearby stops within $radiusMeters meters",
        );

        return Success(nearbyStops);
      case Failure(exception: final e):
        return Failure(e);
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
      final response = await retryOptions.retry(
        () => http.get(uri),
        retryIf: (e) => e is http.ClientException || e is TimeoutException,
      );

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
        'ts': vehicle.timestamp.toIso8601String(), // un standard sa fie sigur ca primeste bine backend-ul
        'lat': vehicle.latitude.toString(),
        'lon': vehicle.longitude.toString(),
        'stop_ids': stopIds,
      },
    );

    try {
      final response = await retryOptions.retry(
        () => http.get(uri),
        retryIf: (e) => e is http.ClientException || e is TimeoutException,
      );

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

  Future<Result<List<List<String>>, Exception>> getTimetable(
    String agencyId,
    String routeShortName,
    String dayType,
  ) async {
    final uri = '${AppConfig.timetablesApiUrl}/$agencyId';

    try {
      final response = await retryOptions.retry(
        () => http.get(
          Uri.parse(uri).replace(
            queryParameters: {
              'route_short_name': routeShortName,
              'day_type': dayType,
            },
          ),
        ),
        retryIf: (e) => e is http.ClientException || e is TimeoutException,
      );

      if (response.statusCode == 200) {
        log.d("Fetched timetable for route $routeShortName on day $dayType");

        final contentType = response.headers['content-type'] ?? '';

        if (contentType.contains('text/csv')) {
          return Success(
            const CsvToListConverter(
              eol: "\n",
              shouldParseNumbers: false,
            ).convert(utf8.decode(response.bodyBytes)),
          );
        } else if (contentType.contains('application/json')) {
          final jsonData = jsonDecode(response.body);
          final url = jsonData['url'] as String;
          return Success([
            ["EXTERNAL_URL", url],
          ]);
        }
      }

      return Failure(
        ApiException(
          "Server error during timetables fetch",
          response.statusCode,
        ),
      );
    } catch (e) {
      return Failure(Exception("Unexpected error: $e"));
    }
  }

  Future<Result<List<Arrival>, Exception>> getSoonArrivalsForStop(
    String agencyId,
    String stopId,
    List<Map<String, dynamic>> vehiclePositions,
  ) async {
    final uri = Uri.parse(
      '${AppConfig.arrivalsApiUrl}/$agencyId/arrivals/$stopId',
    );

    try {
      final response = await retryOptions.retry(
        () => http.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(vehiclePositions),
        ),
        retryIf: (e) => e is http.ClientException || e is TimeoutException,
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
      print(e);
      return Failure(Exception("Unexpected error: $e"));
    }
  }
}
