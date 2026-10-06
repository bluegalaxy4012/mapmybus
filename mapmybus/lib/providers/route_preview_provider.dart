import 'package:flutter/material.dart';

class RoutePreviewProvider extends ChangeNotifier {
  String? tripId;
  String? routeShortName;
  int requestId = 0;

  void request(String tripId, String routeShortName) {
    this.tripId = tripId;
    this.routeShortName = routeShortName;
    requestId++;
    notifyListeners();
  }

  void clear() {
    tripId = null;
    routeShortName = null;
    notifyListeners();
  }
}
