import 'package:flutter/material.dart';
import 'package:mapmybus/providers/city_provider.dart';
import 'package:mapmybus/core/utils.dart';
import 'package:mapmybus/widgets/favorites-page/favorites_page.dart';
import 'package:mapmybus/widgets/map-page/map_page.dart';
import 'package:mapmybus/widgets/settings-page/settings_page.dart';
import 'package:provider/provider.dart';
import 'package:web/web.dart' as web;
import 'package:flutter/foundation.dart' show kIsWeb;

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    // din cauza ca APPLE au PWA facut prost ( https://github.com/flutter/flutter/issues/84833 )
    final isPwa =
        kIsWeb && web.window.matchMedia('(display-mode: standalone)').matches;

    final isWebiOS =
        kIsWeb &&
        (web.window.navigator.userAgent.contains('iPhone') ||
            web.window.navigator.userAgent.contains('iPad') ||
            web.window.navigator.userAgent.contains('iPod'));

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

      bottomNavigationBar: Padding(
        padding: EdgeInsets.only(bottom: isPwa && isWebiOS ? 25 : 0),
        child: SafeArea(
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
      ),
    );
  }
}
