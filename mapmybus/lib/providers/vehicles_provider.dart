import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mapmybus/db_service.dart';
import 'package:mapmybus/models.dart';
import 'package:mapmybus/utils.dart';

class VehiclesProvider extends ChangeNotifier {
  final DbService dbService;

  List<Vehicle> _vehicles = [];
  Timer? _vehicleFetchTimer;

List<Vehicle> get vehicles => _vehicles;


  VehiclesProvider({required this.dbService}) {
    fetchVehiclesAndNotify('default_agency_id');
  }



   void fetchVehiclesAndNotify(String agencyId) async {
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

  void startVehicleFetchTimer(String agencyId) {
    _vehicleFetchTimer?.cancel();

    _vehicleFetchTimer = Timer.periodic(const Duration(seconds: 20), (timer) {
      fetchVehiclesAndNotify(agencyId);
    });
  }


    @override
  void dispose() {
    _vehicleFetchTimer?.cancel();
    super.dispose();
  }

}