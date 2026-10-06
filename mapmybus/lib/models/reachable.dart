class DirectRouteOption {
  final String routeShortName;
  final int stopsAway;
  final String tripId;

  DirectRouteOption(this.routeShortName, this.stopsAway, this.tripId);

  factory DirectRouteOption.fromJson(Map<String, dynamic> j) =>
      DirectRouteOption(
        j['route_short_name'],
        (j['stops_away'] as num).toInt(),
        j['trip_id'],
      );
}

class ReachableStop {
  final String stopId, stopName;
  final double lat, lon;
  final List<DirectRouteOption> routes;

  ReachableStop(this.stopId, this.stopName, this.lat, this.lon, this.routes);

  factory ReachableStop.fromJson(Map<String, dynamic> j) => ReachableStop(
    j['stop_id'].toString(),
    j['stop_name'],
    (j['stop_lat'] as num).toDouble(),
    (j['stop_lon'] as num).toDouble(),
    (j['routes'] as List).map((e) => DirectRouteOption.fromJson(e)).toList(),
  );
}
