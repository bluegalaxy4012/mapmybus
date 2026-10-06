class Eta {
  final String tripId;
  final String stopId;
  final double predictedEtaMinutes;
  final String message;

  const Eta({
    required this.tripId,
    required this.stopId,
    required this.predictedEtaMinutes,
    required this.message,
  });

  factory Eta.fromJson(Map<String, dynamic> json) => Eta(
    tripId: json['trip_id'] as String,
    stopId: json['stop_id'].toString(),
    predictedEtaMinutes: (json['predicted_eta_minutes'] as num).toDouble(),
    message: json['message'] as String,
  );
}

enum ArrivalStatus { arriving, passed, unknown }

class Arrival {
  final String tripId;
  final String? vehicleLabel;
  final double etaMinutes;
  final String message;

  const Arrival({
    required this.tripId,
    this.vehicleLabel,
    required this.etaMinutes,
    required this.message,
  });

  factory Arrival.fromJson(Map<String, dynamic> json) {
    return Arrival(
      tripId: json['trip_id'] as String,
      vehicleLabel: json['vehicle_label'] as String?,
      etaMinutes: (json['predicted_eta_minutes'] as num).toDouble(),
      message: json['message'] as String,
    );
  }
}
