import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mapmybus/models/result.dart';
import 'package:mapmybus/models/vehicle.dart';
import 'package:mapmybus/service/api_service.dart';
import 'package:mapmybus/core/utils.dart';

class VehiclesProvider extends ChangeNotifier {
  final Server server;

  List<Vehicle> _vehicles = [];
  Timer? _vehicleFetchTimer;
  bool isTimerActive = false;

  String? _currentAgencyId;

  List<Vehicle> get vehicles => _vehicles;

  VehiclesProvider({required this.server});

  Future<void> fetchVehiclesAndNotify(String agencyId) async {
    final result = await server.fetchVehicles(agencyId);

    switch (result) {
      case Success(data: final vehicles):
        _vehicles = vehicles;
        break;

      case Failure(exception: final e):
        log.e("Failed to fetch vehicles: $e");
        break;
    }

    notifyListeners();
  }

  Future<void> startVehicleFetchTimer(String agencyId) async {
    if (isTimerActive && agencyId == _currentAgencyId) {
      return;
    }

    stopVehicleFetchTimer();

    _currentAgencyId = agencyId;

    await fetchVehiclesAndNotify(agencyId);

    _vehicleFetchTimer = Timer.periodic(const Duration(seconds: 20), (
      timer,
    ) async {
      await fetchVehiclesAndNotify(agencyId);
    });
    isTimerActive = true;
  }

  void stopVehicleFetchTimer() {
    _vehicleFetchTimer?.cancel();
    isTimerActive = false;
  }

  @override
  void dispose() {
    stopVehicleFetchTimer();
    super.dispose();
  }
}
