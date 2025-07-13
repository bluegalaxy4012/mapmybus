import 'package:flutter/material.dart' hide Route;
import 'package:provider/provider.dart';
import '../models.dart';
import '../main.dart';

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
