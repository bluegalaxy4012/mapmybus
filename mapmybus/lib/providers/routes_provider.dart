import 'dart:convert';

import 'package:flutter/material.dart' hide Route;
import 'package:mapmybus/db_service.dart';
import 'package:mapmybus/utils.dart';
import 'package:mapmybus/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RoutesProvider extends ChangeNotifier {
  final DbService dbService;

  List<Route> _allRoutes = [];
  List<Route> _filteredRoutes = [];
  String _searchQuery = '';
  Map<int, bool> _favoriteRouteIds = {};
  bool _showFavoritesOnly = false;
  String _agencyId = '';

  List<Route> get allRoutes => _allRoutes;
  List<Route> get filteredRoutes => _filteredRoutes;
  String get searchQuery => _searchQuery;
  bool get showFavoritesOnly => _showFavoritesOnly;

  RoutesProvider({required this.dbService});

  void init(String agencyId) async {
    if (_allRoutes.isNotEmpty && _agencyId == agencyId) return;

    _agencyId = agencyId;

    _allRoutes = [];
    _filteredRoutes = [];
    _searchQuery = '';
    _showFavoritesOnly = false;

    await setShowFavoritesOnly(false);

    await _loadData();
  }

  Future<void> _loadData() async {
    await _loadSettings();
    await _loadFavoriteRouteIds();
    await _loadRoutes(_agencyId);
  }

  Future<void> _loadRoutes(String agencyId) async {
    try {
      final result = await dbService.fetchRoutes(agencyId);

      switch (result) {
        case Success(data: final routes):
          _allRoutes = routes
              .map(
                (r) => r.copyWith(
                  isFavorite: _favoriteRouteIds[r.routeId] ?? false,
                ),
              )
              .toList();
          break;
        case Failure(exception: final e):
          log.e("Failed to fetch routes: $e");
          _allRoutes = [];
          _filteredRoutes = [];
          break;
      }
    } catch (e) {
      log.e("Unexpected error while loading routes: $e");
      _allRoutes = [];
      _filteredRoutes = [];
    } finally {
      _applyFilters();
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _showFavoritesOnly = prefs.getBool('showFavoritesOnly') ?? false;
  }

  void _applyFilters() {
    List<Route> tempRoutes = List.from(_allRoutes);

    if (_showFavoritesOnly) {
      tempRoutes = tempRoutes.where((route) => route.isFavorite).toList();
    }

    if (_searchQuery.isNotEmpty) {
      tempRoutes = tempRoutes.where((route) {
        return route.routeShortName.toLowerCase().contains(_searchQuery) ||
            route.routeLongName.toLowerCase().contains(_searchQuery);
      }).toList();
    }

    _filteredRoutes = tempRoutes;
    notifyListeners();
  }

  void refreshFilters() {
    _applyFilters();
  }

  void filterRoutes(String query) {
    _searchQuery = query.toLowerCase();
    _applyFilters();
  }

  void resetSearchQuery() {
    _searchQuery = '';
  }

  Future<void> setShowFavoritesOnly(bool value) async {
    _showFavoritesOnly = value;
    _applyFilters();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('showFavoritesOnly', value);
  }

  Future<void> toggleFavorite(Route route) async {
    final index = _allRoutes.indexWhere(
      (r) => r.routeId == route.routeId && r.agencyId == route.agencyId,
    );
    if (index != -1) {
      final current = _allRoutes[index];
      final updated = current.copyWith(isFavorite: !current.isFavorite);
      _allRoutes[index] = updated;

      _favoriteRouteIds[updated.routeId] = updated.isFavorite;

      await _saveFavoriteRouteIds();

      _applyFilters();
    }
  }

  Future<void> _loadFavoriteRouteIds() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('favoriteRouteMap_$_agencyId');

    if (jsonString != null) {
      final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
      _favoriteRouteIds = decoded.map(
        (k, v) => MapEntry(int.parse(k), v as bool),
      );
      log.d("Loaded favorite route map: $_favoriteRouteIds");
    }
  }

  Future<void> _saveFavoriteRouteIds() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(
      _favoriteRouteIds.map((k, v) => MapEntry(k.toString(), v)),
    );

    await prefs.setString('favoriteRouteMap_$_agencyId', encoded);
    log.d("Saved favorite route map: $_favoriteRouteIds");
  }

  List<Route> get favoriteRoutes =>
      _allRoutes.where((route) => route.isFavorite).toList();
  Set<int> get favoriteRouteIdsSet {
    return _favoriteRouteIds.entries
        .where((e) => e.value == true)
        .map((e) => e.key)
        .toSet();
  }

  bool isFavorite(int routeId) => _favoriteRouteIds[routeId] ?? false;

  String? getRouteShortName(int routeId, String agencyId) {
    return _allRoutes
        .firstWhere(
          (r) => r.routeId == routeId && r.agencyId == agencyId,
          orElse: () => Route(
            agencyId: agencyId,
            routeId: routeId,
            routeShortName: "?",
            routeLongName: '?',
            routeColor: Colors.grey,
            routeType: 3,
            routeDesc: "",
          ),
        )
        .routeShortName;
  }
}
