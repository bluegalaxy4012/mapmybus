import 'package:flutter/material.dart';
import 'package:mapmybus/providers/city_provider.dart';
import 'package:mapmybus/utils.dart';
import 'package:mapmybus/widgets/settings_page.dart';
import 'package:provider/provider.dart';

import 'favorites_page.dart';
import 'map_page.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final cityName = context.watch<CityProvider>().city;
    final city = getCityConfig(cityName);

    Widget page;
    switch (currentIndex) {
      case 0:
        page = MapPage(city: city);
        break;
      case 1:
        page = FavoritesPage(city: city);
        break;
      case 2:
        page = SettingsPage();
        break;
      default:
        page = Center(child: Text("Index necunoscut: $currentIndex"));
    }

    return Scaffold(
      body: page,

      bottomNavigationBar: SafeArea(
        child: BottomNavigationBar(
          items: [
            const BottomNavigationBarItem(
              icon: Icon(Icons.map),
              label: 'Harta',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.favorite),
              label: 'Linii favorite',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.settings),
              label: 'Setari',
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
