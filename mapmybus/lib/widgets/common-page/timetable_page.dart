import 'package:flutter/material.dart';
import 'package:mapmybus/models/result.dart';
import 'package:mapmybus/service/api_service.dart';
import 'package:mapmybus/providers/route_preview_provider.dart';
import 'package:mapmybus/core/utils.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class TimetablePage extends StatefulWidget {
  final String agencyId;
  final String routeShortName;
  final String routeIdString;

  const TimetablePage({
    super.key,
    required this.agencyId,
    required this.routeShortName,
    required this.routeIdString,
  });

  @override
  State<TimetablePage> createState() => _TimetablePageState();
}

class _TimetablePageState extends State<TimetablePage> {
  late Future<Map<String, List<List<String>>?>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadTimetables();
  }

  Future<Map<String, List<List<String>>?>> _loadTimetables() async {
    final db = context.read<Server>();

    const days = {"Luni - Vineri": "lv", "Sambata": "s", "Duminica": "d"};
    final data = <String, List<List<String>>?>{};

    for (final entry in days.entries) {
      final result = await db.getTimetable(
        widget.agencyId,
        widget.routeShortName,
        widget.routeIdString,
        entry.value,
      );

      switch (result) {
        case Success(data: final rows):
          if (rows.isEmpty) {
            data[entry.key] = null;
          } else {
            data[entry.key] = rows
                .map((r) => r.map((c) => c.toString()).toList())
                .toList();
          }
          break;
        case Failure(exception: final e):
          log.w("Failed to fetch timetable for ${entry.key}: $e");
          data[entry.key] = null;
          break;
      }
    }

    return data;
  }

  void _showDirectionDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Alege sensul'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.arrow_forward),
                title: const Text('Sens dus'),
                onTap: () {
                  Navigator.pop(ctx);
                  _requestPreview('0');
                },
              ),
              ListTile(
                leading: const Icon(Icons.arrow_back),
                title: const Text('Sens intors'),
                onTap: () {
                  Navigator.pop(ctx);
                  _requestPreview('1');
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _requestPreview(String direction) {
    final tripId = '${widget.routeIdString}_$direction';
    context.read<RoutePreviewProvider>().request(tripId, widget.routeShortName);
    Navigator.popUntil(context, (r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Orar - ${widget.routeShortName}"),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.map_outlined),
            onPressed: _showDirectionDialog,
            label: const SizedBox(
              width: 75,
              child: Text(
                "Afiseaza ruta pe harta",
                textAlign: TextAlign.center,
                maxLines: 2,
                style: TextStyle(fontSize: 11),
              ),
            ),
          ),
        ],
      ),

      body: FutureBuilder(
        future: _future,
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
              child: Text("Aceasta ruta nu are momentan orarul disponibil"),
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
                      ..._buildTimetable(rows, context),
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

    if (rows.length == 1 && rows[0][0] == "EXTERNAL_URL") {
      final url = rows[0][1];
      return [
        Padding(
          padding: const EdgeInsets.all(16),
          child: InkWell(
            onTap: () async {
              await launchUrl(Uri.parse(url));
            },

            child: Text(
              "Orarul este disponibil momentan doar online. Apasa aici pentru a-l deschide.",
              style: const TextStyle(color: Colors.blue),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ];
    }

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
