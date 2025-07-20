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
                'Detalii traseu: Linia $selectedRouteName',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),

              Text('Statia anterioara: $previousStopName'),

              Text('Statia urmatoare: $nextStopName'),

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
                child: Text('Afiseaza orar'),
              ),

              ElevatedButton(
                onPressed: onRequestStopArrivalTimes,

                child: isLoading
                    ? SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Theme.of(context).primaryColor,
                        ),
                      )
                    // better alternative ?
                    : Column(
                        children: [
                          Text('Estimeaza timpurile de sosire'),
                          Text('la statiile de pe traseu'),
                        ],
                      ),
              ),

              ElevatedButton(onPressed: onClose, child: Text('Inchide')),
            ],
          ),
        ),
      ),
    );
  }
}
