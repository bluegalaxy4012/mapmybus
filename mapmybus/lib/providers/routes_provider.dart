import 'dart:convert';

import 'package:flutter/material.dart' hide Route;
import 'package:flutter/services.dart';
import 'package:mapmybus/utils.dart';
import 'package:mapmybus/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RoutesProvider extends ChangeNotifier {
  List<Route> _allRoutes = [];
  List<Route> _filteredRoutes = [];
  String _searchQuery = '';
  List<int> _favoriteRouteIds = [];


  List<Route> get filteredRoutes => _filteredRoutes;
  String get searchQuery => _searchQuery;
  List<int> get favoriteRouteIds => _favoriteRouteIds;

  RoutesProvider() {
    _loadData();
  }


  Future<void> _loadData() async {
    await _loadFavoriteRouteIds();
    await _loadRoutesFromAsset();
  }

  Future<void> _loadRoutesFromAsset() async {
    try {
      final String response = await rootBundle.loadString(routesAssetPath);
      final List<dynamic> jsonData = jsonDecode(response);

      _allRoutes = jsonData.map((json) {
        Route route = Route.fromJson(json);

        if (_favoriteRouteIds.contains(route.routeId)) {
          route = route.copyWith(isFavorite: true);
        }

        return route;
      }).toList();

      _filteredRoutes = _allRoutes;

      notifyListeners();
      log.i('Routes loaded successfully: ${_allRoutes.length} routes');
    } catch (e) {
      log.e('Error loading routes from assets: $e');
      // handle
    }
  }

  void filterRoutes(String query) {
    _searchQuery = query.toLowerCase();
    if (query.isEmpty) {
      _filteredRoutes = List.from(_allRoutes);
    } else {
      _filteredRoutes = _allRoutes.where((route) {
        return route.routeShortName.toLowerCase().contains(
              query.toLowerCase(),
            ) ||
            route.routeLongName.toLowerCase().contains(query.toLowerCase());
      }).toList();
    }

    notifyListeners();
  }



    Future<void> toggleFavorite(Route route) async {
    final index = _allRoutes.indexWhere(
      (r) => r.routeId == route.routeId && r.agencyId == route.agencyId,
    );
    if (index != -1) {
      final oldRoute = _allRoutes[index];
      _allRoutes[index] = oldRoute.copyWith(isFavorite: !oldRoute.isFavorite);

      if (_allRoutes[index].isFavorite) {
        _favoriteRouteIds.add(_allRoutes[index].routeId);
      } else {
        _favoriteRouteIds.remove(_allRoutes[index].routeId);
      }

      await _saveFavoriteRouteIds();

      filterRoutes(_searchQuery);
    }
  }

  Future<void> _loadFavoriteRouteIds() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? favoriteIdsJson = prefs.getStringList(
      'favoriteRouteIds',
    );

    if (favoriteIdsJson != null) {
      _favoriteRouteIds = favoriteIdsJson.map(int.parse).toList();
      log.d('Loaded favorite IDs: $_favoriteRouteIds');
    }
  }

  Future<void> _saveFavoriteRouteIds() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> favoriteIdsJson = _favoriteRouteIds
        .map((id) => id.toString())
        .toList();

    await prefs.setStringList('favoriteRouteIds', favoriteIdsJson);
    log.d('Saved favorite IDs: $_favoriteRouteIds');
  }

  List<Route> get favoriteRoutes {
    return _allRoutes.where((route) => route.isFavorite).toList();
  }

  String? getRouteShortName(int routeId, String agencyId) {
    final route = _allRoutes.firstWhere(
      (r) => r.routeId == routeId && r.agencyId == agencyId,
      orElse: () => Route(
        agencyId: agencyId,
        routeId: routeId,
        routeShortName: 'Unknown',
        routeLongName: 'Unknown',
        routeColor: Colors.grey,
        routeType: 3,
        routeDesc: '',
      ),
    );
    return route.routeShortName;
  }
}