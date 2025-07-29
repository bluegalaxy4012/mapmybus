import 'package:flutter/material.dart';
import 'package:mapmybus/models.dart';
import 'package:mapmybus/utils.dart';
import 'package:mapmybus/widgets/timetable_page.dart';

class VehicleMenu extends StatelessWidget {
  final String agencyId;
  final String selectedRouteName;
  final String? previousStopName;
  final String? nextStopName;
  final bool isLoading;
  final Vehicle? selectedVehicle;
  final List<EtaDisplayInfo> etasInfo;

  final VoidCallback onRequestStopArrivalTimes;
  final VoidCallback onClose;

  const VehicleMenu({
    super.key,
    required this.agencyId,
    required this.selectedRouteName,
    this.previousStopName,
    this.nextStopName,
    required this.isLoading,
    this.selectedVehicle,
    required this.etasInfo,
    required this.onRequestStopArrivalTimes,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 10,
      top: 10,
      child: Material(
        elevation: 4.0,
        borderRadius: BorderRadius.circular(8.0),
        child: Container(
          padding: EdgeInsets.all(12.0),
          color: Colors.white,
          child: Column(
            spacing: 12.0,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(getIconForVehicleType(selectedVehicle!.vehicleType)),
              Text(
                "Detalii traseu: Linia $selectedRouteName",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),

              Text("Statia anterioara: $previousStopName"),

              Text("Statia urmatoare: $nextStopName"),

              ElevatedButton(
                onPressed: () {
                  if (selectedVehicle != null && selectedRouteName.isNotEmpty) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => TimetablePage(
                          agencyId: agencyId,
                          routeShortName: selectedRouteName,
                        ),
                      ),
                    );
                  }
                },
                child: Text("Afiseaza orar"),
              ),

              ElevatedButton(
                onPressed: onRequestStopArrivalTimes,

                child: isLoading
                    ? SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      )
                    // better alternative ?
                    : Column(
                        children: [
                          Text("Estimeaza timpurile de sosire"),
                          Text("la statiile de pe traseu"),
                        ],
                      ),
              ),

              if (etasInfo.isNotEmpty) ...[
                SizedBox(
                  height: 120,

                  child: Scrollbar(
                    thumbVisibility: true,

                    child: SingleChildScrollView(
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(
                          Theme.of(context).colorScheme.surfaceContainerLow,
                        ),

                        dataRowMinHeight: 18,
                        dataRowMaxHeight: 26,
                        headingRowHeight: 32,

                        columns: const [
                          DataColumn(
                            label: Text(
                              "Nume statie",
                              style: TextStyle(fontSize: 13),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              "Timp estimat",
                              style: TextStyle(fontSize: 13),
                            ),
                          ),
                        ],

                        rows: etasInfo.map((e) {
                          return DataRow(
                            cells: [
                              DataCell(
                                Text(
                                  e.stopName,
                                  style: const TextStyle(fontSize: 10),
                                ),
                              ),
                              DataCell(
                                Text(
                                  e.etaMessage,
                                  style: const TextStyle(fontSize: 10),
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ],

              ElevatedButton(onPressed: onClose, child: Text("Inchide")),
            ],
          ),
        ),
      ),
    );
  }
}
