class TripStop {
  final String tripId;
  final String stopId;
  final int stopSequence;

  const TripStop({
    required this.tripId,
    required this.stopId,
    required this.stopSequence,
  });

  factory TripStop.fromJson(Map<String, dynamic> json) {
    return TripStop(
      tripId: json['trip_id'] as String,
      stopId: json['stop_id'] as String,
      stopSequence: (json['stop_sequence'] as num).toInt(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'trip_id': tripId,
      'stop_id': stopId,
      'stop_sequence': stopSequence,
    };
  }
}
