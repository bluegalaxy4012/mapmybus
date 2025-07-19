import 'package:flutter/material.dart';
import '../models.dart';
import 'favorites_page.dart';
import 'map_page.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  var currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    // momentan
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
