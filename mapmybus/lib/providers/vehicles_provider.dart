import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mapmybus/db_service.dart';
import 'package:mapmybus/models.dart';
import 'package:mapmybus/utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VehiclesProvider extends ChangeNotifier {
  final DbService dbService;

  List<Vehicle> _vehicles = [];
  Timer? _vehicleFetchTimer;
  bool isTimerActive = false;

  String? _currentAgencyId;

  List<Vehicle> get vehicles => _vehicles;

  VehiclesProvider({required this.dbService});

  Future<void> fetchVehiclesAndNotify(String agencyId) async {
    final isAnyToDraw = await isAnyVehicleToDraw();
    if (!isAnyToDraw) {
      _vehicles = [];
      notifyListeners();
      stopVehicleFetchTimer();
      return;
    }

    final result = await dbService.fetchVehicles(agencyId);

    switch (result) {
      case Success(data: final vehicles):
        _vehicles = vehicles;
        break;
      case Failure(exception: final e):
        log.e('Failed to fetch vehicles: $e');
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

    final isAnyToDraw = await isAnyVehicleToDraw();
    if (!isAnyToDraw) return;

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

  Future<bool> isAnyVehicleToDraw() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('favoriteRouteMap_$_currentAgencyId');

    if (jsonString != null) {
      final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
      return decoded.values.any((v) => v == true);
    }

    return false;
  }

  @override
  void dispose() {
    stopVehicleFetchTimer();
    super.dispose();
  }
}
