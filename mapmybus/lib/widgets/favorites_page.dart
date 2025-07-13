import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import 'route_list_item.dart';

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
