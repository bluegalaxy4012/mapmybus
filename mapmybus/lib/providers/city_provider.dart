import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CityProvider extends ChangeNotifier {
  String _city = 'Cluj-Napoca';
  String get city => _city;

  Future<void> setCity(String city) async {
    _city = city;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_city', city);
  }
}
