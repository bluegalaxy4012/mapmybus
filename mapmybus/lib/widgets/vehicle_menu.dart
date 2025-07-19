import 'package:flutter/material.dart';
import 'package:mapmybus/models.dart';

class VehicleMenu extends StatelessWidget {
  final String selectedRouteName;
  final String? previousStopName;
  final String? nextStopName;
  final bool isLoading;
  final Vehicle? selectedVehicle;
  final VoidCallback onRequestStopArrivalTimes;
  final VoidCallback onClose;

  const VehicleMenu({
    super.key,
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
            spacing: 15.0,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Detalii traseu: Linia $selectedRouteName',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),

              Text('Statia anterioara: $previousStopName'),

              Text('Statia urmatoare: $nextStopName'),

              ElevatedButton(onPressed: () {}, child: Text('Afiseaza orar')),

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
                    : Text('Estimeaza timpul de sosire la o statie'),
              ),

              ElevatedButton(onPressed: onClose, child: Text('Inchide')),
            ],
          ),
        ),
      ),
    );
  }
}
