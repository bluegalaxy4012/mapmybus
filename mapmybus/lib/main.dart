import 'dart:async';

import 'package:flutter/material.dart' hide Route;
import 'package:mapmybus/config.dart';
import 'package:mapmybus/db_service.dart';
import 'package:mapmybus/providers/routes_provider.dart';
import 'package:mapmybus/providers/vehicles_provider.dart';
import 'package:mapmybus/utils.dart';
import 'package:provider/provider.dart';

import 'widgets/home_page.dart';

//hover - imposibil
//reenter fav ramane lista filtrata si tot inceata - mai incerc threading in rest OK
//mai bine mut routes pe partea de api - OK
//sa dau fetch cum trebuie la vehicule (doar cand e fix pe map_page si timeru o trecut si sa existe linii in favorites) - OK
//threading pentru calculari
//aia de click pe stop - nume si cele mai curand-ajungande vehicule acolo
//dau store la file pe partea de api in loc sa fac requesturi si mi fac un script de reinnoire pe la 3 30 dimineata - OK
//din nouuuu nu se da fetch bine la deschiderea aplicatiei(si de 2  ori) - OK

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AppConfig.load();

  final dbService = DbService();

  runApp(MyApp(dbService: dbService));
}

class MyApp extends StatelessWidget {
  final DbService dbService;
  const MyApp({required this.dbService, super.key});

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
      ],
      child: MaterialApp(
        title: appTitle,
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
