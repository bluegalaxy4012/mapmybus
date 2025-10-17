import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mapmybus/models.dart';
import 'package:mapmybus/providers/routes_provider.dart';
import 'package:mapmybus/widgets/simple_snackbar.dart';
import 'package:provider/provider.dart';

import 'route_list_item.dart';

class FavoritesPage extends StatefulWidget {
  final CityConfig city;

  const FavoritesPage({super.key, required this.city});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  RoutesProvider? _routesProvider;

  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _routesProvider = context.read<RoutesProvider>();

      var result = await _routesProvider?.init(widget.city.agencyId);

      switch (result) {
        case Success():
          _routesProvider?.refreshFilters();
          break;

        case Failure():
          if (mounted) {
            showSimpleSnackbar(context, "Nu s-au putut incarca liniile");
          }
          break;
        default:
          break;
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _routesProvider?.resetSearchQuery();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final routeProvider = context.watch<RoutesProvider>();
    final filteredRoutes = routeProvider.filteredRoutes;
    final searchQuery = routeProvider.searchQuery;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            decoration: InputDecoration(
              hintText: "Cauta numele liniilor...",
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10.0),
                borderSide: BorderSide.none,
              ),

              filled: true,
              fillColor: Colors.grey[250],
              contentPadding: EdgeInsets.symmetric(vertical: 0, horizontal: 10),
            ),
            onChanged: (query) {
              if (_debounceTimer?.isActive ?? false) {
                _debounceTimer!.cancel();
              }

              _debounceTimer = Timer(const Duration(milliseconds: 300), () {
                routeProvider.filterRoutes(query);
              });
            },
            maxLength: 50,
          ),
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              spacing: 8,
              children: [
                const Text("Afiseaza doar favoritele"),
                
                Switch(
                  value: routeProvider.showFavoritesOnly,
                  onChanged: (v) {
                    routeProvider.setShowFavoritesOnly(v);
                  },
                ),

                const Spacer(),

                OutlinedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text("Sterge toate favoritele"),
                        content: Text(
                          "Sigur doresti sa stergi toate rutele favorite pentru ${widget.city.name}?",
                        ),

                        actions: [
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                            },
                            child: const Text("Anuleaza"),
                          ),

                          TextButton(
                            onPressed: () {
                              routeProvider.clearAllFavorites();
                              Navigator.of(context).pop();

                              showSimpleSnackbar(
                                context,
                                "Rutele favorite au fost sterse cu succes",
                              );
                            },

                            child: const Text("Sterge"),
                          ),
                        ],
                      ),
                    );
                  },

                  child: const Text("Sterge toate favoritele"),
                ),
              ],
            ),
          ),
        ),

        Expanded(
          child: filteredRoutes.isEmpty && searchQuery.isNotEmpty
              ? Center(
                  child: Text(
                    'Nicio ruta gasita pentru "$searchQuery"',
                    style: const TextStyle(fontSize: 18),
                    textAlign: TextAlign.center,
                  ),
                )
              : filteredRoutes.isEmpty && searchQuery.isEmpty
              ? Center(
                  child: const Text(
                    "Nicio ruta disponibila.",
                    style: TextStyle(fontSize: 18),
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.all(8.0),
                  itemCount: filteredRoutes.length,
                  itemBuilder: (context, index) {
                    final route = filteredRoutes[index];
                    return RouteListItem(
                      key: ValueKey(route.routeId),
                      agencyId: widget.city.agencyId,
                      route: route,
                    );
                  },
                ),
        ),
      ],
    );
  }
}
