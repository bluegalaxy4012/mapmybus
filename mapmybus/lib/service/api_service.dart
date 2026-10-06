import 'dart:async';
import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mapmybus/core/api_config.dart';
import 'package:mapmybus/core/utils.dart';
import 'package:http/http.dart' as http;
import 'package:mapmybus/models/eta.dart';
import 'package:mapmybus/models/info_dtos.dart';
import 'package:mapmybus/models/result.dart';
import 'package:mapmybus/models/route.dart';
import 'package:mapmybus/models/shape_point.dart';
import 'package:mapmybus/models/stop.dart';
import 'package:mapmybus/models/vehicle.dart';
import 'package:mapmybus/models/weather.dart';
import 'package:mapmybus/models/reachable.dart';
import 'package:retry/retry.dart';

class Server {
  // in caz de timeout-uri
  static const retryOptions = RetryOptions(
    maxAttempts: 3,
    delayFactor: Duration(seconds: 1),
  );

  static const Duration _httpTimeout = Duration(seconds: 12);
  Future<http.Response> _get(Uri uri) {
    return http.get(uri).timeout(_httpTimeout);
  }

  // acum stim sigur ca vehiculele sunt valide si au campurile necesare din backend
  Future<Result<List<Vehicle>, Exception>> fetchVehicles(
    String agencyId,
  ) async {
    final uri = Uri.parse('${AppConfig.vehiclesApiUrl}/$agencyId');

    try {
      final response = await retryOptions.retry(
        () => _get(uri),
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
        () => _get(uri),
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
        () => _get(uri),
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

  Future<Result<List<String>, Exception>> getTripIdsForStop(
    String stopId,
    String agencyId,
  ) async {
    final uri = Uri.parse(
      '${AppConfig.tripsForStopApiUrl}/$agencyId?stop_id=$stopId',
    );

    try {
      final response = await retryOptions.retry(
        () => _get(uri),
        retryIf: (e) => e is http.ClientException || e is TimeoutException,
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);

        log.d("Fetched ${data.length} trip IDs for stop $stopId");

        return Success(data.map((tripId) => tripId.toString()).toList());
      } else {
        return Failure(
          ApiException(
            "Server error during trip IDs for stop fetch",
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
        () => _get(uri),
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
        () => _get(uri),
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
        'ts': vehicle.timestamp
            .toIso8601String(), // un standard sa fie sigur ca primeste bine backend-ul
        'lat': vehicle.latitude.toString(),
        'lon': vehicle.longitude.toString(),
        'stop_ids': stopIds,
      },
    );

    try {
      final response = await retryOptions.retry(
        () => _get(uri),
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
    String routeIdString,
    String dayType,
  ) async {
    final uri = '${AppConfig.timetablesApiUrl}/$agencyId';

    try {
      final response = await retryOptions.retry(
        () => _get(
          Uri.parse(uri).replace(
            queryParameters: {
              'route_short_name': routeShortName,
              'route_id': routeIdString,
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
          final csvRows = Csv(
            dynamicTyping: false,
          ).decode(utf8.decode(response.bodyBytes));

          final List<List<String>> csv = csvRows
              .map((row) => row.map((cell) => cell.toString()).toList())
              .toList();

          return Success(csv);
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
  ) async {
    final uri = Uri.parse(
      '${AppConfig.arrivalsApiUrl}/$agencyId?stop_id=$stopId',
    );

    try {
      final response = await retryOptions.retry(
        () => http.get(uri).timeout(_httpTimeout),
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
      return Failure(Exception("Unexpected error: $e"));
    }
  }

  Future<Result<WeatherInfo, Exception>> getWeather(String agencyId) async {
    final uri = Uri.parse('${AppConfig.weatherApiUrl}/$agencyId');

    try {
      final response = await retryOptions.retry(
        () => _get(uri),
        retryIf: (e) => e is http.ClientException || e is TimeoutException,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return Success(WeatherInfo.fromJson(data));
      }
      return Failure(ApiException("weather", response.statusCode));
    } catch (e) {
      return Failure(Exception("$e"));
    }
  }

  Future<Result<List<ReachableStop>, Exception>> getReachableStops(
    String agencyId,
    String stopId,
  ) async {
    final uri = Uri.parse('${AppConfig.reachableApiUrl}/$agencyId/$stopId');

    try {
      final response = await retryOptions.retry(
        () => _get(uri),
        retryIf: (e) => e is http.ClientException || e is TimeoutException,
      );

      if (response.statusCode == 200) {
        final d = jsonDecode(response.body) as List;
        return Success(d.map((e) => ReachableStop.fromJson(e)).toList());
      }
      return Failure(ApiException("reachable", response.statusCode));
    } catch (e) {
      return Failure(Exception("$e"));
    }
  }
}
