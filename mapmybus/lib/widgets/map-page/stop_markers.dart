import 'package:flutter/material.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapmybus/models/stop.dart';

class StopMarker extends Marker {
  StopMarker({
    required Stop stop,
    required double iconSize,
    required bool isFinalStopMarker,
    required bool isStart,
    required bool isEnd,
    required bool showStopNames,
    void Function(Stop)? onStopTap,
  }) : super(
         point: LatLng(stop.latitude, stop.longitude),
         width: iconSize + 80,
         height: iconSize,

         // unul e cerc deci trebuie centrul sa fie in punctul acela de pe harta
         // si unul marker deci trebuie varful de jos sa fie la acea pozitie,
         alignment: isFinalStopMarker ? Alignment.center : Alignment.topCenter,

         child: GestureDetector(
           onTap: onStopTap != null ? () => onStopTap(stop) : null,

           child: Stack(
             clipBehavior: Clip.none,
             alignment: Alignment.center,
             children: [
               isStart
                   ? FinalStopMarker(name: "Start")
                   : isEnd
                   ? FinalStopMarker(name: "End")
                   : const Icon(
                       Icons.place,
                       color: Color.fromARGB(255, 68, 137, 216),
                       size: 30,
                     ),

               if (showStopNames)
                 Positioned(
                   top: iconSize,

                   child: Text(
                     stop.stopName,
                     textAlign: TextAlign.center,
                     style: const TextStyle(
                       fontSize: 11.25,
                       fontWeight: FontWeight.bold,
                       color: Color.fromARGB(255, 85, 85, 85),
                       backgroundColor: Colors.white10,
                     ),
                     overflow: TextOverflow.ellipsis,
                   ),
                 ),
             ],
           ),
         ),
       );
}

class FinalStopMarker extends StatelessWidget {
  final String name;

  const FinalStopMarker({super.key, required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: Colors.black,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        name,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
