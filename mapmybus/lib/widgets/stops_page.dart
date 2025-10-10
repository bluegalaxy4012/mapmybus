import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mapmybus/db_service.dart';
import 'package:mapmybus/models.dart';
import 'package:mapmybus/widgets/simple_snackbar.dart';
import 'package:provider/provider.dart';
import 'package:diacritic/diacritic.dart';

class StopsPage extends StatefulWidget {
  final CityConfig city;

  const StopsPage({super.key, required this.city});

  @override
  State<StopsPage> createState() => _StopsPageState();
}

class _StopsPageState extends State<StopsPage> {
  List<Stop> _allStops = [];
  List<Stop> _filteredStops = [];
  String _searchQuery = '';
  Timer? _debounceTimer;

  void _loadStops() async {
    final result = await context.read<DbService>().getStops(
      widget.city.agencyId,
    );

    switch (result) {
      case Success(data: final stops):
        if (mounted) {
          setState(() {
            _allStops = stops;
            _filteredStops = stops;
          });
        }
        break;

      default:
        if (mounted) {
          showSimpleSnackbar(context, "Nu s-au putut incarca statiile");
        }
    }
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 200), () {
      setState(() {
        _searchQuery = query;

        _filteredStops = _allStops
            .where(
              (stop) => removeDiacritics(
                stop.stopName.toLowerCase(),
              ).contains(removeDiacritics(query.toLowerCase())),
            )
            .toList();
      });
    });
  }

  @override
  void initState() {
    super.initState();
    _loadStops();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Lista statii", style: TextStyle(fontSize: 28)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),

      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: "Cauta numele statiei...",
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10.0),
                  borderSide: BorderSide.none,
                ),

                filled: true,
                fillColor: Colors.grey[250],
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 0,
                  horizontal: 10,
                ),
              ),

              onChanged: _onSearchChanged,
              maxLength: 50,
            ),
          ),

          if (_filteredStops.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  _searchQuery.isEmpty
                      ? "Nicio statie disponibila"
                      : 'Nicio statie gasita pentru "$_searchQuery"',
                  style: const TextStyle(fontSize: 24),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.all(4.0),
                itemCount: _filteredStops.length,

                itemBuilder: (context, index) {
                  final stop = _filteredStops[index];

                  return ListTile(
                    title: Text(
                      stop.stopName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context, stop);
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
