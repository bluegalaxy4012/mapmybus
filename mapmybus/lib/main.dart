// import 'package:english_words/english_words.dart';
import 'dart:async';

import 'package:flutter/material.dart';
// import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
// import 'package:flutter_osm_plugin/flutter_osm_plugin.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;


void main() {
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

enum Accessibility {
  bikeAccessible,
  bikeInaccessible,
  wheelchairAccessible,
  wheelchairInaccessible,
  unknown,
}

class Vehicle {
  final int id;
  final String label;
  final double? latitude;
  final double? longitude;
  final DateTime timestamp;
  final int? speed;
  final int? routeId;
  final String? tripId;
  final int vehicleType;
  final Accessibility bikeAccessible;
  final Accessibility wheelchairAccessible;

  Vehicle({
    required this.id,
    required this.label,
    this.latitude,
    this.longitude,
    required this.timestamp,
    this.speed,
    this.routeId,
    this.tripId,
    required this.vehicleType,
    required this.bikeAccessible,
    required this.wheelchairAccessible,
  });

  factory Vehicle.fromJson(Map<String, dynamic> json) {
    Accessibility parseAccessibility(String? value) {
      if (value == null) return Accessibility.unknown;

      switch (value) {
        case 'BIKE_ACCESSIBLE':
          return Accessibility.bikeAccessible;
        case 'BIKE_INACCESSIBLE':
          return Accessibility.bikeInaccessible;
        case 'WHEELCHAIR_ACCESSIBLE':
          return Accessibility.wheelchairAccessible;
        case 'WHEELCHAIR_INACCESSIBLE':
          return Accessibility.wheelchairInaccessible;
        default:
          return Accessibility.unknown;
      }
    }

    DateTime parseTimestamp(String? timestamp) {
      if (timestamp == null) return DateTime.now();
      try {
        return DateTime.parse(timestamp);
      } catch (e) {
        print('Eroare la parsarea timestamp-ului: $e');
        return DateTime.now();
      }
    }

    return Vehicle(
      id: json['id'] as int,
      label: json['label'] as String,
      latitude: json['latitude'] != null
          ? (json['latitude'] as num).toDouble()
          : null,
      longitude: json['longitude'] != null
          ? (json['longitude'] as num).toDouble()
          : null,
      timestamp: parseTimestamp(json['timestamp'] as String?),
      speed: json['speed'] != null ? (json['speed'] as num).toInt() : null,
      routeId: json['route_id'] as int?,
      tripId: json['trip_id'] as String?,
      vehicleType: json['vehicle_type'] as int,
      bikeAccessible: parseAccessibility(json['bike_accessible'] as String?),
      wheelchairAccessible: parseAccessibility(
        json['wheelchair_accessible'] as String?,
      ),
    );
  }
}

class Route {
  final String agencyId;
  final int routeId;
  final String routeShortName;
  final String routeLongName;
  final Color routeColor; // Store as Color
  final int routeType;
  final String routeDesc;
  bool isFavorite;

  Route({
    required this.agencyId,
    required this.routeId,
    required this.routeShortName,
    required this.routeLongName,
    required this.routeColor,
    required this.routeType,
    required this.routeDesc,
    this.isFavorite = false,
  });

  factory Route.fromJson(Map<String, dynamic> json) {
    Color color;

    // unele il au gresit oricum (#000)
    try {
      String hexString = json['route_color'].toString().replaceAll('#', '');

      if (hexString.length == 6) {
        hexString = 'FF$hexString';
      } else if (hexString.length != 8) {
        throw FormatException(
          'Lungime invalida a string-ului hex pentru culoare: $hexString',
        );
      }

      color = Color(int.parse(hexString, radix: 16));
    } catch (e) {
      color = Colors.grey;
      print(
        'Eroare la parsarea culorii pentru ruta ${json['route_short_name']}: $e. Se foloseste gri implicit.',
      );
    }

    return Route(
      agencyId: json['agency_id'] as String,
      routeId: json['route_id'] as int,
      routeShortName: json['route_short_name'] as String,
      routeLongName: json['route_long_name'] as String,
      routeColor: color,
      routeType: json['route_type'] as int,
      routeDesc: json['route_desc'] as String,
      isFavorite: false,
    );
  }
}

class CityConfig {
  final String name;
  final LatLng center;
  final double initialZoom;
  final double minZoom;
  final double maxZoom;
  final LatLngBounds bounds;
  final String agencyId;

  const CityConfig({
    required this.name,
    required this.center,
    required this.initialZoom,
    required this.minZoom,
    required this.maxZoom,
    required this.bounds,
    required this.agencyId,
  });
}

final List<CityConfig> cities = [
  CityConfig(
    name: "Cluj-Napoca",
    center: LatLng(46.770439, 23.591423),
    initialZoom: 14,
    minZoom: 13,
    maxZoom: 19,
    bounds: LatLngBounds(LatLng(46.83, 23.44), LatLng(46.72, 23.74)),
    agencyId: '2',
  ),
];

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



  Future<void> _fetchVehicles(String agencyId) async {
    const url = 'https://api.tranzy.ai/v1/opendata/vehicles';
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'X-Agency-Id': agencyId,
          'Accept': 'application/json',
          'X-API-KEY': 'iZfqSdYCq0ZxEsKEkfCRoyiXEsaC19CQ5QV4WMnF',
        },
      );

      if(response.statusCode == 200) {
        final List<dynamic> jsonData = jsonDecode(response.body);
        final List<Vehicle> vehicles = jsonData.map((json) {
          return Vehicle.fromJson(json);
        }).toList();

        print('Fetched ${vehicles.length} vehicles for agency $agencyId');
        _vehicles = vehicles;
        notifyListeners();

      }
    }
    catch (e) {
      print('error fetching vehicles: $e');
      // handle
    }
  }


  void _startVehicleFetchTimer(String agencyId) {
    _vehicleFetchTimer?.cancel();

    _vehicleFetchTimer = Timer.periodic(Duration(seconds: 30), (timer) async {
      // print('Fetching vehicles...');
      await _fetchVehicles(agencyId);
    });
  }


  Future<void> toggleFavorite(Route route) async {
    final index = _allRoutes.indexWhere((r) => r.routeId == route.routeId && r.agencyId == route.agencyId);
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

// ...

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  var currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final city = cities.firstWhere((c) => c.name == 'Cluj-Napoca');

    Widget page;
    switch (currentIndex) {
      case 0:
        page = MapPage(city: city);
        break;
      case 1:
        page = FavoritesPage();
        break;
      default:
        page = Center(child: Text('Index necunoscut: $currentIndex'));
    }

    return Scaffold(
      body: page,

      bottomNavigationBar: SafeArea(
        child: BottomNavigationBar(
          items: [
            BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Harta'),
            BottomNavigationBarItem(
              icon: Icon(Icons.favorite),
              label: 'Linii favorite',
            ),
          ],
          currentIndex: currentIndex,
          onTap: (index) {
            setState(() {
              currentIndex = index;
            });
          },
        ),
      ),
    );
  }
}

class FavoritesPage extends StatelessWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();
    var filteredRoutes = appState.filteredRoutes;
    var searchQuery = appState.searchQuery;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Cauta numele liniilor...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10.0),
                borderSide: BorderSide.none,
              ),

              filled: true,
              fillColor: Colors.grey[200],
              contentPadding: EdgeInsets.symmetric(vertical: 0, horizontal: 10),
            ),
            onChanged: (query) {
              appState.filterRoutes(query);
            },
          ),
        ),

        Expanded(
          child: filteredRoutes.isEmpty && searchQuery.isNotEmpty
              ? Center(
                  child: Text(
                    'Nicio ruta gasita pentru "$searchQuery"',
                    style: TextStyle(fontSize: 18),
                  ),
                )
              : filteredRoutes.isEmpty && searchQuery.isEmpty
              ? Center(
                  child: Text(
                    'Nicio ruta disponibila.',
                    style: TextStyle(fontSize: 18),
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.all(8.0),
                  itemCount: filteredRoutes.length,

                  itemBuilder: (context, index) {
                    final route = filteredRoutes[index];
                    return RouteListItem(route: route);
                  },
                ),
        ),
      ],
    );
  }
}

class RouteListItem extends StatelessWidget {
  final Route route;

  const RouteListItem({super.key, required this.route});

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();

    return Card(
      margin: EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
      elevation: 2.0,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: route.routeColor,
          child: Text(
            route.routeShortName,
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),

        title: Text(
          route.routeShortName,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18.0),
        ),

        subtitle: Text(
          route.routeLongName,
          style: TextStyle(fontSize: 14.0, color: Colors.grey[600]),
        ),
        trailing: IconButton(
          icon: Icon(
            route.isFavorite ? Icons.favorite : Icons.favorite_border,
            color: route.isFavorite ? Colors.red : Colors.grey,
          ),

          onPressed: () {
            appState.toggleFavorite(route);
          },
        ),

        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('afisare orar etc ${route.routeShortName}')),
          );
        },
      ),
    );
  }
}



Future<Position> _determinePosition() async {
  bool serviceEnabled;
  LocationPermission permission;

  serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    return Future.error('Location services are disabled.');
  }

  permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      return Future.error('Location permissions are denied');
    }
  }

  if (permission == LocationPermission.deniedForever) {

    return Future.error(
      'Location permissions are permanently denied, we cannot request permissions.',
    );
  }


  return await Geolocator.getCurrentPosition(
    // locationSettings: LocationSettings(
    //   accuracy: LocationAccuracy.high,
    //   distanceFilter: 3,
    // ),
  );
}

class MapPage extends StatefulWidget {
  const MapPage({super.key, required this.city});

  final CityConfig city;

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final MapController _mapController = MapController();
  StreamSubscription<Position>? _positionStreamSubscription;

  LatLng? _currentPosition;

  Future<void> _getCurrentPosition() async {
    try {
      Position position = await _determinePosition();
      if (mounted)
      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
      });

    } catch (e) {
      print('error: $e');
      // handle
    }
  }

  void _startPositionStream() {
    final LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 3,
    );
    _positionStreamSubscription =
        Geolocator.getPositionStream(
          locationSettings: locationSettings,
        ).listen((Position? position) {
          print(
            position == null
                ? 'Unknown'
                : '${position.latitude.toString()}, ${position.longitude.toString()}',
          );

          if (position != null && mounted) {
            setState(() {
              _currentPosition = LatLng(position.latitude, position.longitude);
            });
          }
        });
  }

  void _centerMapOnCurrentPosition() {
    if (_currentPosition != null) {
      _mapController.move(_currentPosition!, widget.city.initialZoom);
    } else {
      print('current position unavailable');
    }
  }

  @override
  void initState() {
    super.initState();
    _getCurrentPosition();
    _startPositionStream();
    context.read<MyAppState>()._fetchVehicles(widget.city.agencyId);
    context.read<MyAppState>()._startVehicleFetchTimer(widget.city.agencyId);
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();

    var visibleRoutesIds = appState._favoriteRouteIds;
    final visibleVehicles = appState.vehicles.where((v) =>
      v.latitude != null &&
      v.longitude != null &&
      v.routeId != null &&
      v.tripId != null &&
      visibleRoutesIds.contains(v.routeId!),
    ).toList();

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: widget.city.center,
            initialZoom: widget.city.initialZoom,
            maxZoom: widget.city.maxZoom,
            minZoom: widget.city.minZoom,
            interactionOptions: InteractionOptions(
              flags:
                  InteractiveFlag.drag |
                  InteractiveFlag.flingAnimation |
                  InteractiveFlag.doubleTapZoom |
                  InteractiveFlag.scrollWheelZoom |
                  InteractiveFlag.pinchZoom,
            ),
            cameraConstraint: CameraConstraint.contain(bounds: widget.city.bounds),
          ),

          children: [
            TileLayer(
              urlTemplate: "https://{s}.basemaps.cartocdn.com/rastertiles/light_all/{z}/{x}/{y}.png",
              userAgentPackageName: 'com.mapmybus.app',
            ),
            if (_currentPosition != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: _currentPosition!,
                    width: 40,
                    height: 40,
                    child: Icon(Icons.location_on, color: Colors.red, size: 40),
                  ),
                ],
              ),
            MarkerLayer(markers: visibleVehicles.map((v) {
              final routeShortName = appState.getRouteShortName(v.routeId!, widget.city.agencyId);
              return Marker(
                point: LatLng(v.latitude!, v.longitude!),
                width: 40,
                height: 30,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.black),
                        ),
                        child: Text(
                          routeShortName ?? 'Unknown',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ],
                  ),
              );
            }).toList(),)
          ],
        ),

        Positioned(
          child: FloatingActionButton(
            mini: true,
            child: const Icon(Icons.my_location),
            onPressed: _centerMapOnCurrentPosition,
          ),
          top: 30,
          right: 30,
        ),
      ],
    );
  }
}
