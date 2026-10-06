import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapmybus/core/utils.dart';
import 'package:mapmybus/models/vehicle.dart';
import 'package:mapmybus/providers/routes_provider.dart';
import 'package:mapmybus/widgets/common-page/simple_snackbar.dart';

class NearbyVehicle {
  final Vehicle vehicle;
  final double distance;
  final String routeShortName;
  final double bearingToVehicle;
  final String? headingDescription;

  const NearbyVehicle({
    required this.vehicle,
    required this.distance,
    required this.routeShortName,
    required this.bearingToVehicle,
    this.headingDescription,
  });
}

Future<void> showNearbyVehiclesSheet({
  required BuildContext context,
  required Position currentPosition,
  required List<Vehicle> vehicles,
  required RoutesProvider routeProvider,
  required String agencyId,
  required Function(Vehicle, String) onVehicleSelected,
}) async {
  if (vehicles.isEmpty) {
    showSimpleSnackbar(context, 'Niciun vehicul disponibil');
    return;
  }

  // distanta + unde se indreapta
  final allNearby =
      vehicles
          .where((v) => v.latitude != null && v.longitude != null && !v.isGhost)
          .map((v) {
            final distance = Geolocator.distanceBetween(
              currentPosition.latitude,
              currentPosition.longitude,
              v.latitude!,
              v.longitude!,
            );
            final routeShortName =
                routeProvider.getRouteShortNameFromRouteId(
                  v.routeId!,
                  agencyId,
                ) ??
                '?';
            final bearingToVehicle = calculateBearing(
              LatLng(currentPosition.latitude, currentPosition.longitude),
              LatLng(v.latitude!, v.longitude!),
            );

            // probabil nenecesar dar poate fi util
            String? headingDescription;

            if (v.lastStopLatitude != null && v.lastStopLongitude != null) {
              final headingBearing = calculateBearing(
                LatLng(v.latitude!, v.longitude!),
                LatLng(v.lastStopLatitude!, v.lastStopLongitude!),
              );
              headingDescription = compassDirection(headingBearing);
            }

            return NearbyVehicle(
              vehicle: v,
              distance: distance,
              routeShortName: routeShortName,
              bearingToVehicle: bearingToVehicle,
              headingDescription: headingDescription,
            );
          })
          .toList()
        ..sort((a, b) => a.distance.compareTo(b.distance));

  if (!context.mounted) return;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _NearbyVehiclesSheetContent(
      allNearby: allNearby,
      onVehicleSelected: onVehicleSelected,
    ),
  );
}

class _NearbyVehiclesSheetContent extends StatefulWidget {
  final List<NearbyVehicle> allNearby;
  final Function(Vehicle, String) onVehicleSelected;

  const _NearbyVehiclesSheetContent({
    required this.allNearby,
    required this.onVehicleSelected,
  });

  @override
  State<_NearbyVehiclesSheetContent> createState() =>
      _NearbyVehiclesSheetContentState();
}

class _NearbyVehiclesSheetContentState
    extends State<_NearbyVehiclesSheetContent> {
  late double _activeRadius;
  late double screenWidth;

  @override
  void initState() {
    super.initState();
    _activeRadius = Constants.nearbyVehiclesPickRadius;
  }

  String _formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.round()} m';
    }
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  @override
  Widget build(BuildContext context) {
    screenWidth = MediaQuery.sizeOf(context).width;

    final within = widget.allNearby
        .where((nv) => nv.distance <= _activeRadius)
        .toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Column(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.directions_bus, color: Colors.orange, size: 96.sp),
                  SizedBox(width: 8.w),
                  Text(
                    'Vehicule in apropiere',
                    style: TextStyle(
                      fontSize: calculateFontSize(screenWidth, 42),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            // radius selector chips
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
              child: Row(
                children: [
                  Text(
                    'Raza: ',
                    style: TextStyle(
                      fontSize: calculateFontSize(screenWidth, 30),
                      color: Colors.grey[700],
                    ),
                  ),
                  SizedBox(width: 8.w),
                  _radiusChip(200, '${_activeRadius == 200 ? '✓ ' : ""}200m'),
                  SizedBox(width: 8.w),
                  _radiusChip(400, '${_activeRadius == 400 ? '✓ ' : ""}400m'),
                  SizedBox(width: 8.w),
                  _radiusChip(800, '${_activeRadius == 800 ? '✓ ' : ""}800m'),
                ],
              ),
            ),
            const Divider(height: 2),
            Expanded(
              child: within.isEmpty
                  ? Center(
                      child: Padding(
                        padding: EdgeInsets.all(24.w),
                        child: Text(
                          'Nu sunt vehicule la sub ${_activeRadius.toInt()} m de tine. Incearca o raza mai mare.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: calculateFontSize(screenWidth, 40),
                            color: Colors.grey[600],
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      controller: scrollController,
                      itemCount: within.length,
                      separatorBuilder: (_, _) => Divider(height: 1.h),
                      itemBuilder: (context, index) {
                        final nv = within[index];
                        final vehicle = nv.vehicle;
                        final heading = nv.headingDescription;

                        return ListTile(
                          leading: Container(
                            width: 128.w,
                            height: 64.h,
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8.r),
                              border: Border.all(
                                color: Colors.orange,
                                width: 1.5,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                nv.routeShortName,
                                style: TextStyle(
                                  fontSize: calculateFontSize(screenWidth, 32),
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange,
                                ),
                              ),
                            ),
                          ),
                          title: Text(
                            'Linia ${nv.routeShortName}',
                            style: TextStyle(
                              fontSize: calculateFontSize(screenWidth, 28),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.straighten,
                                    size: 26.sp,
                                    color: Colors.grey[600],
                                  ),
                                  SizedBox(width: 4.w),
                                  Text(
                                    _formatDistance(nv.distance),
                                    style: TextStyle(
                                      fontSize: calculateFontSize(
                                        screenWidth,
                                        18,
                                      ),
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                              if (vehicle.lastStopName != null &&
                                  heading != null) ...[
                                SizedBox(height: 2.h),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.navigation,
                                      size: 26.sp,
                                      color: Colors.grey[600],
                                    ),
                                    SizedBox(width: 4.w),
                                    Expanded(
                                      child: Text(
                                        'Spre $heading -> ${vehicle.lastStopName}',
                                        style: TextStyle(
                                          fontSize: calculateFontSize(
                                            screenWidth,
                                            18,
                                          ),
                                          color: Colors.grey[600],
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ] else if (vehicle.lastStopName != null) ...[
                                SizedBox(height: 2.h),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.place,
                                      size: 26.sp,
                                      color: Colors.grey[600],
                                    ),
                                    SizedBox(width: 4.w),
                                    Expanded(
                                      child: Text(
                                        'Catre ${vehicle.lastStopName}',
                                        style: TextStyle(
                                          fontSize: calculateFontSize(
                                            screenWidth,
                                            18,
                                          ),
                                          color: Colors.grey[600],
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                          trailing: vehicle.isGhost
                              ? Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 8.w,
                                    vertical: 2.h,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(10.r),
                                  ),
                                  child: Text(
                                    'Fantoma',
                                    style: TextStyle(
                                      fontSize: calculateFontSize(
                                        screenWidth,
                                        14,
                                      ),
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                )
                              : Icon(
                                  Icons.chevron_right,
                                  color: Colors.grey[400],
                                ),
                          onTap: vehicle.isGhost
                              ? null
                              : () {
                                  Navigator.pop(context);
                                  widget.onVehicleSelected(
                                    vehicle,
                                    nv.routeShortName,
                                  );
                                },
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _radiusChip(double radius, String label) {
    final selected = _activeRadius == radius;
    return GestureDetector(
      onTap: () => setState(() => _activeRadius = radius),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
        decoration: BoxDecoration(
          color: selected ? Colors.orange : Colors.grey[200],
          borderRadius: BorderRadius.circular(14.r),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: calculateFontSize(screenWidth, 28),
            color: selected ? Colors.white : Colors.grey[800],
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
