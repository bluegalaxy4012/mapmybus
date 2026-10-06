class Stop {
  final String stopId;
  final String stopName;
  final double latitude;
  final double longitude;

  const Stop({
    required this.stopId,
    required this.stopName,
    required this.latitude,
    required this.longitude,
  });

  factory Stop.fromJson(Map<String, dynamic> json) {
    return Stop(
      stopId: json['stop_id'].toString(),
      stopName: json['stop_name'] as String,
      latitude: (json['stop_lat'] as num).toDouble(),
      longitude: (json['stop_lon'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'stop_id': stopId,
      'stop_name': stopName,
      'stop_lat': latitude,
      'stop_lon': longitude,
    };
  }
}

class StopWithoutPosition {
  final String stopId;
  final String stopName;

  const StopWithoutPosition({required this.stopId, required this.stopName});
}
