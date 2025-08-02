class AppConfig {
  static final String etasApiUrl = const String.fromEnvironment(
    'ETAS_API_URL',
    defaultValue: '',
  );
  static final String arrivalsApiUrl = const String.fromEnvironment(
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
