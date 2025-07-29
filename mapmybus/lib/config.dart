// import 'package:flutter_dotenv/flutter_dotenv.dart';

// class AppConfig {
//   static late final String etasApiUrl;
//   static late final String stopsApiUrl;
//   static late final String shapesApiUrl;
//   static late final String vehiclesApiUrl;
//   static late final String timetablesApiUrl;
//   static late final String routesApiUrl;

//   static Future<void> load() async {
//     await dotenv.load(fileName: ".env");

//     etasApiUrl = dotenv.env['ETAS_API_URL'] ?? '';
//     stopsApiUrl = dotenv.env['STOPS_API_URL'] ?? '';
//     shapesApiUrl = dotenv.env['SHAPES_API_URL'] ?? '';
//     vehiclesApiUrl = dotenv.env['VEHICLES_API_URL'] ?? '';
//     timetablesApiUrl = dotenv.env['TIMETABLES_API_URL'] ?? '';
//     routesApiUrl = dotenv.env['ROUTES_API_URL'] ?? '';
//   }
// }

// try build time env

class AppConfig {
  static final String etasApiUrl = const String.fromEnvironment(
    'ETAS_API_URL',
    defaultValue: '',
  );
  static final String stopsApiUrl = const String.fromEnvironment(
    'STOPS_API_URL',
    defaultValue: '',
  );
  static final String shapesApiUrl = const String.fromEnvironment(
    'SHAPES_API_URL',
    defaultValue: '',
  );
  static final String vehiclesApiUrl = const String.fromEnvironment(
    'VEHICLES_API_URL',
    defaultValue: '',
  );
  static final String timetablesApiUrl = const String.fromEnvironment(
    'TIMETABLES_API_URL',
    defaultValue: '',
  );
  static final String routesApiUrl = const String.fromEnvironment(
    'ROUTES_API_URL',
    defaultValue: '',
  );
}
