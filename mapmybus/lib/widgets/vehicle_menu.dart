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

  // ar trebui si la alte widget-uri de astea dar nu stiu cum e optim de lucrat
  late double screenWidth;
  final double smallScreenBonusSize = 11.0;
  final double largeScreenBonusSize = 1.0;

  bool _isMinimized = false;

  void _toggleMinimize() {
    setState(() {
      _isMinimized = !_isMinimized;
    });
  }

  double calculateFontSize(double baseSize) {
    if (screenWidth >= 864) return (baseSize + largeScreenBonusSize).sp;

    return (baseSize + smallScreenBonusSize).sp;
  }

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
      // offset ?
      final double rowH = 26.h;
      final double headerH = 32.h;

      final double rowTop = headerH + (index * rowH);
      final double visibleHeight = _scrollController.position.viewportDimension;
      final double middleOffset = (visibleHeight / 2) - (rowH / 2);
      final double finalPos = rowTop - middleOffset;

      _scrollController.animateTo(
        finalPos.clamp(0, _scrollController.position.maxScrollExtent),
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
    screenWidth = MediaQuery.sizeOf(context).width;

    return Positioned(
      left: 10.w,
      top: 10.h,
      child: Material(
        elevation: 4.0,
        borderRadius: BorderRadius.circular(6.r),

        child: Container(
          padding: EdgeInsets.all(12.w),
          color: Colors.white,
          child: _isMinimized
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.directions_bus, size: 40),
                    const SizedBox(width: 8),
                    Text(
                      "Linia ${widget.selectedRouteName}",
                      style: const TextStyle(fontSize: 20),
                    ),
                    IconButton(
                      icon: const Icon(Icons.expand_more, size: 34),
                      onPressed: _toggleMinimize,
                    ),
                  ],
                )
              : Column(
                  spacing: 18.h,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.expand_less, size: 72.sp),
                          onPressed: _toggleMinimize,
                        ),

                        Icon(
                          getIconForVehicleType(
                            widget.selectedVehicle!.vehicleType,
                          ),
                          size: 58.sp,
                        ),
                      ],
                    ),

                    Text(
                      "Detalii traseu: Linia ${widget.selectedRouteName}",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: calculateFontSize(24),
                      ),
                    ),

                    Text(
                      "Statia anterioara: ${widget.previousStopName}",
                      style: TextStyle(fontSize: calculateFontSize(18)),
                    ),

                    Text(
                      "Statia urmatoare: ${widget.nextStopName}",
                      style: TextStyle(fontSize: calculateFontSize(18)),
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
                      child: Text(
                        "Afiseaza orar",
                        style: TextStyle(fontSize: calculateFontSize(18)),
                      ),
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
                                  style: TextStyle(
                                    fontSize: calculateFontSize(18),
                                  ),
                                ),
                                Text(
                                  "la statiile de pe traseu",
                                  style: TextStyle(
                                    fontSize: calculateFontSize(18),
                                  ),
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
                            child: Container(
                              // ignore overflow, doar sa nu fie prea lat tabelul
                              constraints: BoxConstraints(
                                maxWidth: screenWidth * 0.34,
                              ),

                              child: DataTable(
                                headingRowColor: WidgetStateProperty.all(
                                  Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerLow,
                                ),

                                dataRowMinHeight: 18.h,
                                dataRowMaxHeight: 26.h,
                                headingRowHeight: 32.h,

                                columns: [
                                  DataColumn(
                                    label: Text(
                                      "Nume statie",
                                      style: TextStyle(
                                        fontSize: calculateFontSize(16),
                                      ),
                                    ),
                                  ),
                                  DataColumn(
                                    label: Text(
                                      "Timp estimat",
                                      style: TextStyle(
                                        fontSize: calculateFontSize(16),
                                      ),
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
                                            fontSize: calculateFontSize(13),
                                            fontWeight:
                                                e.stopName ==
                                                    widget.nextStopName
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          e.etaMessage,
                                          style: TextStyle(
                                            fontSize: calculateFontSize(14),
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
                      ),
                    ],

                    ElevatedButton(
                      onPressed: widget.onClose,
                      child: Text(
                        "Inchide",
                        style: TextStyle(fontSize: calculateFontSize(18)),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
