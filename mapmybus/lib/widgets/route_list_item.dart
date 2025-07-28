import 'package:flutter/material.dart' hide Route;
import 'package:mapmybus/providers/routes_provider.dart';
import 'package:mapmybus/widgets/simple_snackbar.dart';
import 'package:mapmybus/widgets/timetable_page.dart';
import 'package:provider/provider.dart';

import '../models.dart';

class RouteListItem extends StatelessWidget {
  final String agencyId;
  final Route route;

  const RouteListItem({super.key, required this.agencyId, required this.route});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
      elevation: 2.0,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: route.routeColor,
          child: Text(
            route.routeShortName,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14.0,
            ),
          ),
        ),

        title: Text(
          route.routeShortName,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 19.0),
        ),

        subtitle: Text(
          route.routeLongName,
          style: TextStyle(fontSize: 13.0, color: Colors.grey[700]),
        ),
        trailing: Selector<RoutesProvider, bool>(
          selector: (_, provider) => provider.isFavorite(route.routeId),
          builder: (_, isFav, _) => IconButton(
            icon: Icon(
              isFav ? Icons.favorite : Icons.favorite_border,
              color: isFav ? Colors.red : Colors.grey,
              size: 28.0,
            ),

            onPressed: () {
              context.read<RoutesProvider>().toggleFavorite(route);
              showSimpleSnackbar(
                context,
                'Linia ${route.routeShortName} a fost ${isFav ? 'scoasa de la' : 'adaugata la'} favorite.',
              );
            },
          ),
        ),

        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => TimetablePage(
                agencyId: agencyId,
                routeShortName: route.routeShortName,
              ),
            ),
          );
        },
      ),
    );
  }
}
