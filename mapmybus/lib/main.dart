// import 'package:english_words/english_words.dart';
import 'dart:async';

import 'package:flutter/material.dart' hide Route;
// import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
// import 'package:flutter_osm_plugin/flutter_osm_plugin.dart';
import 'package:provider/provider.dart';
// import 'package:flutter_map/flutter_map.dart';
// import 'package:latlong2/latlong.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
// import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'models.dart';
import 'widgets/home_page.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> main() async {
  await dotenv.load(fileName: ".env");
  runApp(MyApp());
}

IconData getIconForVehicleType(int vehicleType) {
  switch (vehicleType) {
    case 0:
      return Icons.tram; // Tram, Streetcar, Light rail
    case 1:
      return Icons.subway; // Subway, Metro
    case 2:
      return Icons.train; // Rail
    case 3:
      return Icons.directions_bus; // Bus
    case 4:
      return Icons.directions_ferry; // Ferry
    case 5:
      return Icons.tram; // Cable tram
    case 6:
      return Icons.airline_seat_flat; // Aerial lift
    case 7:
      return Icons.directions_railway; // Funicular
    case 11:
      return Icons.directions_bus_filled; // Trolleybus
    case 12:
      return Icons.train; // Monorail
    default:
      return Icons.directions_bus; // Default bus icon
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => MyAppState(),
      child: MaterialApp(
        title: 'Map My Bus',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.orange,
            primary: Colors.deepOrange,
            secondary: Colors.orangeAccent,
          ),
        ),

        home: MyHomePage(),
      ),
    );
  }
}

class MyAppState extends ChangeNotifier {
  List<Route> _allRoutes = [];
  List<Route> _filteredRoutes = [];
  String _searchQuery = '';
  List<int> _favoriteRouteIds = [];

  List<Vehicle> _vehicles = [];
  Timer? _vehicleFetchTimer;

  MyAppState() {
    // _loadRoutes();
    // _loadFavoriteRouteIds();
    _loadData();
  }

  Future<void> _loadData() async {
    await _loadFavoriteRouteIds();
    await _loadRoutes();
  }

  List<Route> get filteredRoutes => _filteredRoutes;
  String get searchQuery => _searchQuery;
  List<Vehicle> get vehicles => _vehicles;
  List<int> get favoriteRouteIds => _favoriteRouteIds;

  Future<void> _loadRoutes() async {
    try {
      final String response = await rootBundle.loadString('data/routes.json');
      final List<dynamic> jsonData = jsonDecode(response);

      _allRoutes = jsonData.map((json) {
        final Route route = Route.fromJson(json);

        if (_favoriteRouteIds.contains(route.routeId)) {
          route.isFavorite = true;
        }

        return route;
      }).toList();
      _filteredRoutes = List.from(_allRoutes);
      notifyListeners();
      print('routes loaded successfully: ${_allRoutes.length} routes');
    } catch (e) {
      print('error loading routes from assets: $e');
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

  Future<void> fetchVehicles(String agencyId) async {
    const url = 'https://api.tranzy.ai/v1/opendata/vehicles';
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'X-Agency-Id': agencyId,
          'Accept': 'application/json',
          'X-API-KEY': dotenv.env['API_KEY'] ?? '',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> jsonData = jsonDecode(response.body);
        final List<Vehicle> vehicles = jsonData.map((json) {
          return Vehicle.fromJson(json);
        }).toList();

        print('Fetched ${vehicles.length} vehicles for agency $agencyId');
        _vehicles = vehicles;
        notifyListeners();
      }
    } catch (e) {
      print('error fetching vehicles: $e');
      // handle
    }
  }

  void startVehicleFetchTimer(String agencyId) {
    _vehicleFetchTimer?.cancel();

    _vehicleFetchTimer = Timer.periodic(Duration(seconds: 30), (timer) async {
      // print('fetching vehicles...');
      await fetchVehicles(agencyId);
    });
  }

  Future<void> toggleFavorite(Route route) async {
    final index = _allRoutes.indexWhere(
      (r) => r.routeId == route.routeId && r.agencyId == route.agencyId,
    );
    if (index != -1) {
      _allRoutes[index].isFavorite = !_allRoutes[index].isFavorite;

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
      print('loaded favorite IDs: $_favoriteRouteIds');
    }
  }

  Future<void> _saveFavoriteRouteIds() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> favoriteIdsJson = _favoriteRouteIds
        .map((id) => id.toString())
        .toList();
    await prefs.setStringList('favoriteRouteIds', favoriteIdsJson);
    print('saved favorite IDs: $_favoriteRouteIds');
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

  @override
  void dispose() {
    _vehicleFetchTimer?.cancel();
    super.dispose();
  }
}
