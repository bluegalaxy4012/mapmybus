import 'package:english_words/english_words.dart';
import 'package:flutter/material.dart';
// import 'package:flutter_osm_plugin/flutter_osm_plugin.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(MyApp());
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
        hexString = 'FF' + hexString;
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

  const CityConfig({
    required this.name,
    required this.center,
    required this.initialZoom,
    required this.minZoom,
    required this.maxZoom,
    required this.bounds,
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

  Future<void> toggleFavorite(Route route) async {
    final index = _allRoutes.indexWhere((r) => r.routeId == route.routeId);
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
}

// ...

class MyHomePage extends StatefulWidget {
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

  const RouteListItem({Key? key, required this.route}) : super(key: key);

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

class MapPage extends StatelessWidget {
  const MapPage({super.key, required this.city});

  final CityConfig city;

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      // mapController: MapController(),
      options: MapOptions(
        initialCenter: city.center,
        initialZoom: city.initialZoom,
        maxZoom: city.maxZoom,
        minZoom: city.minZoom,
        interactionOptions: InteractionOptions(
          flags:
              InteractiveFlag.drag |
              InteractiveFlag.flingAnimation |
              InteractiveFlag.doubleTapZoom |
              InteractiveFlag.scrollWheelZoom |
              InteractiveFlag.pinchZoom,
        ),
        cameraConstraint: CameraConstraint.contain(bounds: city.bounds),
      ),

      children: [
        TileLayer(
          urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
          subdomains: ['a', 'b', 'c'],
          userAgentPackageName: 'com.mapmybus.app',
        ),
      ],
    );
  }
}

// class GeneratorPage extends StatelessWidget {
//   @override
//   Widget build(BuildContext context) {
//     var appState = context.watch<MyAppState>();
//     var pair = appState.current;

//     IconData icon;
//     if (appState.favorites.contains(pair)) {
//       icon = Icons.favorite;
//     } else {
//       icon = Icons.favorite_border;
//     }

//     return Center(
//       child: Column(
//         mainAxisAlignment: MainAxisAlignment.center,
//         children: [
//           BigCard(pair: pair),
//           SizedBox(height: 10),
//           Row(
//             mainAxisSize: MainAxisSize.min,
//             children: [
//               ElevatedButton.icon(
//                 onPressed: () {
//                   appState.saveFavorite();
//                 },
//                 icon: Icon(icon),
//                 label: Text('Like'),
//               ),
//               SizedBox(width: 10),
//               ElevatedButton(
//                 onPressed: () {
//                   appState.getNext();
//                 },
//                 child: Text('Next'),
//               ),
//             ],
//           ),
//         ],
//       ),
//     );
//   }
// }

// ...

class BigCard extends StatelessWidget {
  const BigCard({super.key, required this.pair});

  final WordPair pair;

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    final style = theme.textTheme.displayMedium!.copyWith(
      color: theme.colorScheme.onPrimary,
    );

    return Card(
      color: theme.colorScheme.primary,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Text(
          pair.asLowerCase,
          style: style,
          semanticsLabel: "${pair.first} ${pair.second}",
        ),
      ),
    );
  }
}
