import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:mapmybus/models.dart';
import 'package:mapmybus/utils.dart';
import 'package:mapmybus/widgets/timetable_page.dart';

class VehicleMenu extends StatefulWidget {
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
  State<VehicleMenu> createState() => _VehicleMenuState();
}

class _VehicleMenuState extends State<VehicleMenu> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToCorrespondingStop();
    });
  }

  void _scrollToCorrespondingStop() {
    if (!_scrollController.hasClients ||
        widget.nextStopName == null ||
        widget.etasInfo.isEmpty) {
      return;
    }

    final int index = widget.etasInfo.indexWhere(
      (item) => item.stopName == widget.nextStopName,
    );

    if (index != -1) {
      final double rowH = 26.h;
      final double headerH = 32.0.h;

      final double rowTop = headerH + (index * rowH);
      final double visibleHeight = _scrollController.position.viewportDimension;
      final double middleOffset = (visibleHeight / 2) - (rowH / 2);
      final double finalPos = rowTop - middleOffset;

      _scrollController.animateTo(
        finalPos.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void didUpdateWidget(VehicleMenu oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.isLoading &&
        !widget.isLoading &&
        widget.etasInfo.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToCorrespondingStop();
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 10.w,
      top: 10.h,
      child: Material(
        elevation: 4.0,
        borderRadius: BorderRadius.circular(6.r),

        child: Container(
          padding: EdgeInsets.all(10.w),
          color: Colors.white,
          child: Column(
            spacing: 12.h,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                getIconForVehicleType(widget.selectedVehicle!.vehicleType),
                size: 60.sp,
              ),
              Text(
                "Detalii traseu: Linia ${widget.selectedRouteName}",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24.sp),
              ),

              Text(
                "Statia anterioara: ${widget.previousStopName}",
                style: TextStyle(fontSize: 18.sp),
              ),

              Text(
                "Statia urmatoare: ${widget.nextStopName}",
                style: TextStyle(fontSize: 18.sp),
              ),

              ElevatedButton(
                onPressed: () {
                  if (widget.selectedVehicle != null &&
                      widget.selectedRouteName.isNotEmpty) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => TimetablePage(
                          agencyId: widget.agencyId,
                          routeShortName: widget.selectedRouteName,
                        ),
                      ),
                    );
                  }
                },
                child: Text("Afiseaza orar", style: TextStyle(fontSize: 18.sp)),
              ),

              ElevatedButton(
                onPressed: widget.onRequestStopArrivalTimes,

                child: widget.isLoading
                    ? SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      )
                    // better alternative ?
                    : Column(
                        children: [
                          Text(
                            "Estimeaza timpurile de sosire",
                            style: TextStyle(fontSize: 18.sp),
                          ),
                          Text(
                            "la statiile de pe traseu",
                            style: TextStyle(fontSize: 18.sp),
                          ),
                        ],
                      ),
              ),

              if (widget.etasInfo.isNotEmpty) ...[
                SizedBox(
                  height: 120,

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
                              "Nume statie",
                              style: TextStyle(fontSize: 17.sp),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              "Timp estimat",
                              style: TextStyle(fontSize: 17.sp),
                            ),
                          ),
                        ],

                        rows: widget.etasInfo.map((e) {
                          return DataRow(
                            color: e.stopName == widget.nextStopName
                                ? WidgetStateProperty.all(
                                    Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerLow,
                                  )
                                : null,

                            cells: [
                              DataCell(
                                Text(
                                  e.stopName,
                                  style: TextStyle(
                                    fontSize: 14.sp,
                                    fontWeight:
                                        e.stopName == widget.nextStopName
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  e.etaMessage,
                                  style: TextStyle(fontSize: 15.sp),
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

              ElevatedButton(
                onPressed: widget.onClose,
                child: Text("Inchide", style: TextStyle(fontSize: 18.sp)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
