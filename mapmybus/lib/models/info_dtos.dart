import 'package:latlong2/latlong.dart';
import 'package:mapmybus/models/stop.dart';

class StopDistanceInfo {
  final Stop stop;
  final double distanceAlongRoute;

  const StopDistanceInfo({
    required this.stop,
    required this.distanceAlongRoute,
  });
}

class VehicleStopsInfo {
  final double latitude;
  final double longitude;
  final List<StopDistanceInfo> stopsDistanceInfo;
  final List<LatLng> shapePoints;
  final List<double> shapeCumDistances;

  const VehicleStopsInfo({
    required this.latitude,
    required this.longitude,
    required this.stopsDistanceInfo,
    required this.shapePoints,
    required this.shapeCumDistances,
  });
}

class EtaDisplayInfo {
  final StopWithoutPosition stop;
  final String etaMessage;

  EtaDisplayInfo({required this.stop, required this.etaMessage});
}

class StopArrivalDisplayInfo {
  final String routeShortName;
  final double eta;
  final String etaMessage;
  final bool isVehicleAtEnds;

  StopArrivalDisplayInfo(
    this.routeShortName,
    this.eta,
    this.etaMessage,
    this.isVehicleAtEnds,
  );
}

class AssistantResponse {
  final String response;
  final List<String> toolsUsed;

  AssistantResponse({required this.response, this.toolsUsed = const []});

  factory AssistantResponse.fromJson(Map<String, dynamic> json) {
    return AssistantResponse(
      response: json['response'] as String,
      toolsUsed: ((json['tools_used'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}
