import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:mapmybus/models.dart';
import 'package:mapmybus/utils.dart';

class StopArrivalsTable extends StatefulWidget {
  final String stopName;
  final List<StopArrivalDisplayInfo> arrivals;

  final VoidCallback onClose;

  const StopArrivalsTable({
    super.key,
    required this.stopName,
    required this.arrivals,
    required this.onClose,
  });

  @override
  State<StopArrivalsTable> createState() => _StopArrivalsTableState();
}

class _StopArrivalsTableState extends State<StopArrivalsTable> {
  Offset _position = Offset(10.w, 100.h);

  late double screenWidth;
  late double screenHeight;

  @override
  Widget build(BuildContext context) {
    screenWidth = MediaQuery.sizeOf(context).width;
    screenHeight = MediaQuery.sizeOf(context).height;

    final clampedPosition = Offset(
      _position.dx.clamp(-200.w, screenWidth - 200.w),
      _position.dy.clamp(-200.h, screenHeight - 200.h),
    );

    return Positioned(
      right: clampedPosition.dx,
      bottom: clampedPosition.dy,

      child: GestureDetector(
        onPanUpdate: (dragDetails) {
          setState(() {
            _position += dragDetails.delta;
          });
        },

        child: Material(
          elevation: 4.0,
          borderRadius: BorderRadius.circular(6.r),

          child: Column(
            children: [
              Container(
                color: Colors.white,
                padding: EdgeInsets.all(16.w),
                child: Column(
                  spacing: 12.w,
                  mainAxisSize: MainAxisSize.min,

                  children: [
                    Column(
                      children: [
                        Text(
                          "Urmatoarele sosiri la",
                          style: TextStyle(
                            fontSize: calculateFontSize(screenWidth, 22),
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        Text(
                          widget.stopName,
                          style: TextStyle(
                            fontSize: calculateFontSize(screenWidth, 22),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),

                    DataTable(
                      headingRowColor: WidgetStateProperty.all(
                        Theme.of(context).colorScheme.surfaceContainerLow,
                      ),

                      dataRowMinHeight: 18.h,
                      dataRowMaxHeight: 26.h,
                      headingRowHeight: 32.h,

                      columns: [
                        DataColumn(
                          label: Text(
                            "Linia",
                            style: TextStyle(
                              fontSize: calculateFontSize(screenWidth, 18),
                            ),
                          ),
                        ),
                        DataColumn(
                          label: Text(
                            "Estimat sosire",
                            style: TextStyle(
                              fontSize: calculateFontSize(screenWidth, 18),
                            ),
                          ),
                        ),
                      ],

                      rows: widget.arrivals.map((arrival) {
                        return DataRow(
                          cells: [
                            DataCell(
                              Text(
                                arrival.routeShortName,
                                style: TextStyle(
                                  fontSize: calculateFontSize(screenWidth, 15),
                                ),
                              ),
                            ),
                            DataCell(
                              Text(
                                arrival.etaMessage,
                                style: TextStyle(
                                  fontSize: calculateFontSize(screenWidth, 15),
                                ),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),

                    SizedBox(height: 6.h),

                    ElevatedButton(
                      onPressed: widget.onClose,
                      child: Text(
                        "Inchide",
                        style: TextStyle(
                          fontSize: calculateFontSize(screenWidth, 22),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(
                height: 12,
                child: Center(
                  child: Container(
                    width: 45,
                    height: 3,
                    decoration: BoxDecoration(
                      color: Colors.grey,
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
