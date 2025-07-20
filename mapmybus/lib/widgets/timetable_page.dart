import 'package:flutter/material.dart';
import 'package:mapmybus/main.dart';
import 'package:provider/provider.dart';

class TimetablePage extends StatelessWidget {
  final String agencyId;
  final String routeShortName;

  const TimetablePage({
    super.key,
    required this.agencyId,
    required this.routeShortName,
  });

  Future<Map<String, List<List<String>>?>> loadTimetables(
    BuildContext context,
  ) async {
    // momentan
    if (agencyId != "2") return {};

    final db = context.read<MyAppState>().dbService;

    const days = {"Luni - Vineri": "lv", "Sambata": "s", "Duminica": "d"};
    final data = <String, List<List<String>>?>{};

    for (final entry in days.entries) {
      try {
        final rows = await db.getTimetable(routeShortName, entry.value);
        data[entry.key] = rows
            .map((r) => r.map((c) => c.toString()).toList())
            .toList();
      } catch (_) {
        data[entry.key] = null;
      }
    }

    return data;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Orar - $routeShortName")),

      body: FutureBuilder(
        future: loadTimetables(context),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text("Eroare: ${snapshot.error}"));
          }

          final data = snapshot.data as Map<String, List<List<String>>?>;

          final allEmpty = data.values.every((v) => v == null);
          if (allEmpty) {
            return const Center(
              child: Text("Aceasta ruta nu are orarul disponibil"),
            );
          }

          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 12),
            children: data.entries.map((entry) {
              final title = entry.key;
              final rows = entry.value;

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),

                child: ExpansionTile(
                  title: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),

                  children: [
                    if (rows == null)
                      const Text("Nu circula")
                    else
                      ..._buildTimetable(rows, context), // fiecare
                  ],
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }

  List<Widget> _buildTimetable(List<List<String>> rows, BuildContext context) {
    final widgets = <Widget>[];

    if (rows.length < 5) {
      return [const Text("Orarul este indisponibil")];
    }

    final traseu = rows[0][1];
    final valabilDeLa = rows[2][1];
    final capete = [rows[3][1], rows[4][1]];

    final headerRows = [
      ["Traseu", traseu],
      ["Valabil de la", valabilDeLa],
      [
        "Dus - Plecare de la ${capete[0]}",
        "Intors - Plecare de la ${capete[1]}",
      ],
    ];

    for (final row in headerRows) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),

          child: Row(
            children: row.map((cell) {
              return Expanded(
                child: Text(
                  cell.trim(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      );

      widgets.add(const Divider());
    }

    final timetableRows = rows.sublist(5);

    for (int i = 0; i < timetableRows.length; i++) {
      final row = timetableRows[i];
      final backgroundColor = i % 2 == 0
          ? Theme.of(context).colorScheme.surfaceContainer
          : Theme.of(context).colorScheme.surfaceContainerHigh;

      widgets.add(
        Container(
          color: backgroundColor,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),

          child: Row(
            children: row.map((cell) {
              return Expanded(
                child: Text(cell.trim(), textAlign: TextAlign.center),
              );
            }).toList(),
          ),
        ),
      );
    }

    return widgets;
  }
}
