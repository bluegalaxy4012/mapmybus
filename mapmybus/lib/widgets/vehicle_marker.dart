import 'package:flutter/material.dart';
import 'package:mapmybus/models.dart';

class VehicleMarker extends StatelessWidget {
  final Vehicle v;
  final String? routeShortName;
  final bool isSelected;
  final double bearing;
  final VoidCallback onTap;

  const VehicleMarker({
    super.key,
    required this.v,
    required this.routeShortName,
    required this.isSelected,
    required this.bearing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final int secondsFromUpdate = DateTime.now()
        .difference(v.timestamp)
        .inSeconds;
    Color dotColor;

    if (secondsFromUpdate <= 15) {
      dotColor = Colors.green;
    } else if (secondsFromUpdate <= 35) {
      dotColor = Colors.yellowAccent;
    } else {
      dotColor = Colors.red;
    }

    return GestureDetector(
      onTap: onTap,

      child: Stack(
        // mainAxisAlignment: MainAxisAlignment.center,
        alignment: Alignment.center,
        children: [
          if (isSelected)
            Transform.rotate(
              angle: bearing,
              child: Transform.translate(
                offset: Offset(0, -18),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(Icons.navigation, color: Colors.black, size: 27),

                    Icon(
                      Icons.navigation,
                      color: v.tripId!.endsWith('_0')
                          ? Colors.green
                          : Colors.red,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          Container(
            padding: EdgeInsets.fromLTRB(8, 0, 8, 6),
            decoration: BoxDecoration(
              color: v.tripId!.endsWith('_0') ? Colors.green : Colors.red,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.black),
            ),

            child: Text(
              routeShortName ?? 'Unknown',
              style: TextStyle(
                fontSize: isSelected ? 14 : 13,
                fontWeight: FontWeight.bold,
                color: isSelected
                    ? Colors.black
                    : const Color.fromARGB(255, 48, 48, 48),
                decoration: isSelected
                    ? TextDecoration.underline
                    : TextDecoration.none,
              ),
            ),
          ),

          Positioned(
            bottom: 10,
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black, width: 1.0),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
