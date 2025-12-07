import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:mapmybus/core/utils.dart';
import 'package:mapmybus/models/info_dtos.dart';

class StopArrivalsTable extends StatefulWidget {
  final String stopName;
  final List<String> routeNames;
  final List<StopArrivalDisplayInfo> arrivals;
  final DateTime? tableCreateTime;

  final VoidCallback onClose;

  const StopArrivalsTable({
    super.key,
    required this.stopName,
    required this.routeNames,
    required this.arrivals,
    required this.tableCreateTime,
    required this.onClose,
  });

  @override
  State<StopArrivalsTable> createState() => _StopArrivalsTableState();
}

class _StopArrivalsTableState extends State<StopArrivalsTable> {
  final ScrollController _scrollController = ScrollController();

  Offset _position = Offset(10.w, 60.h);

  late double screenWidth;
  late double screenHeight;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

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
            _position -= dragDetails.delta;
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

                    Column(
                      spacing: 2.0,

                      children: [
                        Text(
                          "Linii deservite:",
                          style: TextStyle(
                            fontSize: calculateFontSize(screenWidth, 17),
                            color: Colors.grey,
                          ),
                        ),

                        // punem maxim 8 pe rand (experimental)
                        for (
                          int i = 0;
                          i < widget.routeNames.length;
                          i += Constants.routesPerRowInStopArrivalsTable
                        )
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,

                            children: [
                              for (
                                int j = 0;
                                j < Constants.routesPerRowInStopArrivalsTable &&
                                    (i + j) < widget.routeNames.length;
                                j++
                              )
                                Padding(
                                  padding: EdgeInsets.only(right: 5.h),

                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 2,
                                      vertical: 0,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: Colors.black,
                                        width: 0.5,
                                      ),
                                      borderRadius: BorderRadius.circular(2),
                                    ),

                                    child: Text(
                                      widget.routeNames[i + j],
                                      style: TextStyle(
                                        fontSize: calculateFontSize(
                                          screenWidth,
                                          14,
                                        ),
                                        color: Colors.black,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ),

                    Column(
                      children: [
                        Text(
                          "*vehiculele boldate se afla in apropierea",
                          style: TextStyle(
                            fontSize: calculateFontSize(screenWidth, 11),
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                        ),

                        Text(
                          "unui capat de linie si este posibil sa",
                          style: TextStyle(
                            fontSize: calculateFontSize(screenWidth, 11),
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                        ),

                        Text(
                          "stationeze sau sa fi pornit deja",
                          style: TextStyle(
                            fontSize: calculateFontSize(screenWidth, 11),
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),

                    SizedBox(
                      // tabelul are dimensiunea intre un header si un header + 5 randuri (daca sunt)
                      height: 32.h + 26.h * min(5, widget.arrivals.length),

                      child: Scrollbar(
                        thumbVisibility: true,
                        controller: _scrollController,

                        child: SingleChildScrollView(
                          controller: _scrollController,

                          child: DataTable(
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
                                    fontSize: calculateFontSize(
                                      screenWidth,
                                      18,
                                    ),
                                  ),
                                ),
                              ),
                              DataColumn(
                                label: Text(
                                  "Estimat sosire",
                                  style: TextStyle(
                                    fontSize: calculateFontSize(
                                      screenWidth,
                                      18,
                                    ),
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
                                        fontSize: calculateFontSize(
                                          screenWidth,
                                          15,
                                        ),
                                        fontWeight: arrival.isVehicleAtEnds
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      arrival.etaMessage,
                                      style: TextStyle(
                                        fontSize: calculateFontSize(
                                          screenWidth,
                                          15,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),

                    Text(
                      "Actualizat la: ${formattedTime(widget.tableCreateTime)}",

                      style: TextStyle(
                        fontSize: calculateFontSize(screenWidth, 13),
                        color: Colors.grey,
                      ),
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
