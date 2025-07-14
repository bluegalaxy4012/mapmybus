import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'db_service.dart';

//auto generat
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final dbService = DbService();
  await dbService.init();

  final testTripIds = ['41_1', '117_1', '136_0'];

  print('Stops box: ${Hive.box('stops').length} entries');
  print('Trip_stops box: ${Hive.box('trip_stops').length} entries');
  print('Shapes box: ${Hive.box('shapes').length} entries');

  for (var tripId in testTripIds) {
    print('=== Testing trip_id: $tripId ===');
    try {
      final stops = await dbService.getStopsForTrip(tripId);
      print('Stops for trip_id $tripId (${stops.length} found):');
      for (var stop in stops.take(5)) {
        print(
          '  Stop: ${stop.stopName} (ID: ${stop.stopId}, Lat: ${stop.latitude}, Lon: ${stop.longitude})',
        );
      }
      if (stops.length > 5) print('  ...and ${stops.length - 5} more stops');
    } catch (e) {
      print('Error fetching stops for trip_id $tripId: $e');
    }

    try {
      final shapePoints = await dbService.getShape(tripId);
      print('Shape points for shape_id $tripId (${shapePoints.length} found):');
      for (var point in shapePoints.take(5)) {
        print(
          '  Point: Sequence ${point.sequence}, Lat: ${point.latitude}, Lon: ${point.longitude}',
        );
      }
      if (shapePoints.length > 5)
        print('  ...and ${shapePoints.length - 5} more points');
    } catch (e) {
      print('Error fetching shape points for shape_id $tripId: $e');
    }
    print('');
  }

  await Hive.close();
}
