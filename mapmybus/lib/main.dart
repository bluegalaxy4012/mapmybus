import 'dart:async';

import 'package:flutter/material.dart' hide Route;
import 'package:mapmybus/config.dart';
import 'package:mapmybus/db_service.dart';
import 'package:mapmybus/providers/city_provider.dart';
import 'package:mapmybus/providers/routes_provider.dart';
import 'package:mapmybus/providers/vehicles_provider.dart';
import 'package:mapmybus/utils.dart';
import 'package:mapmybus/widgets/welcome_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'widgets/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AppConfig.load();

  final dbService = DbService();

  final prefs = await SharedPreferences.getInstance();
  final bool seenWelcome = prefs.getBool('seen_welcome') ?? false; // tutorial
  final selectedCityName = prefs.getString('selected_city') ?? 'Cluj-Napoca';

  runApp(
    MyApp(
      dbService: dbService,
      seenWelcome: seenWelcome,
      selectedCityName: selectedCityName,
    ),
  );
}

class MyApp extends StatelessWidget {
  final DbService dbService;
  final bool seenWelcome;
  final String selectedCityName;

  const MyApp({
    required this.dbService,
    required this.seenWelcome,
    required this.selectedCityName,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<DbService>.value(value: dbService),
        ChangeNotifierProvider(
          create: (context) {
            final db = Provider.of<DbService>(context, listen: false);
            return RoutesProvider(dbService: db);
          },
        ),

        ChangeNotifierProvider(
          create: (context) {
            final db = Provider.of<DbService>(context, listen: false);
            return VehiclesProvider(dbService: db);
          },
        ),

        ChangeNotifierProvider(
          create: (_) {
            final provider = CityProvider();
            provider.setCity(selectedCityName);
            return provider;
          },
        ),
      ],
      child: MaterialApp(
        title: Constants.appTitle,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.orange,
            primary: Colors.deepOrange,
            secondary: Colors.orangeAccent,
          ),
        ),
        home: seenWelcome ? MyHomePage() : const WelcomePage(),
      ),
    );
  }
}
