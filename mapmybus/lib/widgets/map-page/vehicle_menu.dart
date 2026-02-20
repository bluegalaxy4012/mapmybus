import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:mapmybus/core/utils.dart';
import 'package:mapmybus/models/info_dtos.dart';
import 'package:mapmybus/models/stop.dart';
import 'package:mapmybus/models/vehicle.dart';
import 'package:mapmybus/widgets/common-page/timetable_page.dart';

class VehicleMenu extends StatefulWidget {
  final String agencyId;
  final String selectedRouteName;
  // final String? previousStopName;
  // final String? nextStopName;
  final StopWithoutPosition? previousStop;
  final StopWithoutPosition? nextStop;

  final bool isLoading;
  final Vehicle? selectedVehicle;

  final bool? isSelectedVehicleOnRoute;
  final bool? isSelectedVehicleAtEnds;
  final List<EtaDisplayInfo> etasInfo;
  final DateTime? lastEtaFetchTime;

  final VoidCallback onRequestStopArrivalTimes;
  final VoidCallback removeFromFavorites;
  final VoidCallback showOnlyThisRoute;
  final VoidCallback onClose;

  const VehicleMenu({
    super.key,
    required this.agencyId,
    required this.selectedRouteName,
    // required this.previousStopName,
    // required this.nextStopName,
    required this.previousStop,
    required this.nextStop,
    required this.isLoading,
    required this.selectedVehicle,
    required this.isSelectedVehicleOnRoute,
    required this.isSelectedVehicleAtEnds,
    required this.etasInfo,
    required this.lastEtaFetchTime,
    required this.onRequestStopArrivalTimes,
    required this.removeFromFavorites,
    required this.showOnlyThisRoute,
    required this.onClose,
  });

  @override
  State<VehicleMenu> createState() => _VehicleMenuState();
}

class _VehicleMenuState extends State<VehicleMenu> {
  final ScrollController _scrollController = ScrollController();

  Offset _position = Offset(10.w, 10.h);

  // ar trebui si la alte widget-uri de astea dar nu stiu cum e optim de lucrat
  late double screenWidth;
  late double screenHeight;

  bool _showOnlyThisRoute = false;

  bool _isMinimized = false;
  bool _isTableMinimized = false;

  void _toggleMinimize() {
    setState(() {
      _isMinimized = !_isMinimized;
    });
  }

  void _toggleTableMinimize() {
    setState(() {
      _isTableMinimized = !_isTableMinimized;
    });
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
        widget.nextStop == null ||
        widget.etasInfo.isEmpty) {
      return;
    }

    // daca sunt doua statii cu acelasi id, de ex cand e ciclic traseul, o ia pe ultima
    // (de obicei cea de start doar e repetata) si rezolva unele cazuri ciudate
    final int index = widget.etasInfo.lastIndexWhere(
      (data) => data.stop.stopId == widget.nextStop!.stopId,
    );

    if (index != -1) {
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

  Future<void> _showDeleteConfirmationDialog() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Confirmare inchidere si stergere"),
          content: Text(
            "Sigur vrei sa stergi ${widget.selectedRouteName} din lista de favorite?",
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text("Anuleaza"),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text("Sterge"),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      widget.removeFromFavorites();
      widget.onClose();
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
    screenHeight = MediaQuery.sizeOf(context).height;

    // clamp
    double dxLowerLimit = -200.w;
    double dxUpperLimit = screenWidth - 200.w;
    double dyLowerLimit = -200.h;
    double dyUpperLimit = screenHeight - 200.h;

    if (_isMinimized) {
      dxLowerLimit = 0;
      dyLowerLimit = 0;
    }

    final clampedPosition = Offset(
      _position.dx.clamp(dxLowerLimit, dxUpperLimit),
      _position.dy.clamp(dyLowerLimit, dyUpperLimit),
    );

    final isAtEndAndOnRoute =
        widget.isSelectedVehicleOnRoute == true &&
        widget.isSelectedVehicleAtEnds == true;

    return Positioned(
      left: clampedPosition.dx,
      top: clampedPosition.dy,
      child: GestureDetector(
        onPanUpdate: (dragDetails) {
          setState(() {
            _position += dragDetails.delta;
          });
        },

        child: Stack(
          children: [
            Material(
              elevation: 4.0,
              borderRadius: BorderRadius.circular(6.r),

              child: Column(
                children: [
                  Container(
                    padding: EdgeInsets.all(12.w),
                    color: Colors.white,
                    child: _isMinimized
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.directions_bus, size: 48),
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
                            spacing: 12.w,
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
                                      widget.selectedVehicle?.vehicleType ?? 3,
                                    ),
                                    size: 72.sp,
                                  ),
                                ],
                              ),

                              Text(
                                "Detalii traseu: Linia ${widget.selectedRouteName}",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: calculateFontSize(screenWidth, 24),
                                ),
                              ),

                              Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(40.r),
                                  border: Border.all(
                                    color: _showOnlyThisRoute
                                        ? Theme.of(context).colorScheme.primary
                                        : Colors.grey.shade400,
                                    width: 1.0,
                                  ),
                                  color: _showOnlyThisRoute
                                      ? Theme.of(
                                          context,
                                        ).colorScheme.primary.withAlpha(15)
                                      : Colors.transparent,
                                ),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(8.r),
                                  onTap: () {
                                    setState(
                                      () => _showOnlyThisRoute =
                                          !_showOnlyThisRoute,
                                    );
                                    widget.showOnlyThisRoute();
                                  },
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 10.w,
                                      vertical: 8.h,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          _showOnlyThisRoute
                                              ? Icons.map_outlined
                                              : Icons.layers_outlined,
                                          size: 48.sp,
                                          color: _showOnlyThisRoute
                                              ? Theme.of(
                                                  context,
                                                ).colorScheme.primary
                                              : Colors.grey.shade700,
                                        ),
                                        SizedBox(width: 8.w),
                                        Text(
                                          _showOnlyThisRoute
                                              ? "Afiseaza toate liniile"
                                              : "Ascunde alte linii",
                                          style: TextStyle(
                                            fontSize: calculateFontSize(
                                              screenWidth,
                                              17,
                                            ),
                                            fontWeight: _showOnlyThisRoute
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                            color: _showOnlyThisRoute
                                                ? Theme.of(
                                                    context,
                                                  ).colorScheme.primary
                                                : Colors.grey.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),

                              if (widget.isSelectedVehicleOnRoute == false)
                                Text(
                                  "Datele vehiculului ales sunt eronate",
                                  style: TextStyle(
                                    fontSize: calculateFontSize(
                                      screenWidth,
                                      22,
                                    ),
                                  ),
                                )
                              else
                                Column(
                                  spacing: 12.w,

                                  children: [
                                    Text(
                                      "Statia anterioara: ${widget.previousStop!.stopName}",
                                      style: TextStyle(
                                        fontSize: calculateFontSize(
                                          screenWidth,
                                          18,
                                        ),
                                      ),
                                    ),

                                    Text(
                                      "Statia urmatoare: ${widget.nextStop!.stopName}",
                                      style: TextStyle(
                                        fontSize: calculateFontSize(
                                          screenWidth,
                                          18,
                                        ),
                                      ),
                                    ),

                                    ElevatedButton(
                                      onPressed: () {
                                        if (widget.selectedVehicle != null &&
                                            widget
                                                .selectedRouteName
                                                .isNotEmpty) {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  TimetablePage(
                                                    agencyId: widget.agencyId,
                                                    routeShortName: widget
                                                        .selectedRouteName,
                                                  ),
                                            ),
                                          );
                                        }
                                      },
                                      child: Text(
                                        "Afiseaza orar",
                                        style: TextStyle(
                                          fontSize: calculateFontSize(
                                            screenWidth,
                                            18,
                                          ),
                                        ),
                                      ),
                                    ),

                                    ElevatedButton(
                                      onPressed: isAtEndAndOnRoute
                                          ? null
                                          : widget.onRequestStopArrivalTimes,

                                      child: widget.isLoading
                                          ? SizedBox(
                                              height: 16,
                                              width: 16,

                                              child: CircularProgressIndicator(
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.primary,
                                              ),
                                            )
                                          // better alternative ?
                                          : Column(
                                              children: [
                                                Text(
                                                  isAtEndAndOnRoute
                                                      ? "Timpii de sosire nu se pot"
                                                      : "Estimeaza timpii de sosire",
                                                  style: TextStyle(
                                                    fontSize: calculateFontSize(
                                                      screenWidth,
                                                      16,
                                                    ),
                                                  ),
                                                ),

                                                Text(
                                                  isAtEndAndOnRoute
                                                      ? "estima la capete de linie"
                                                      : "la statiile de pe traseu",
                                                  style: TextStyle(
                                                    fontSize: calculateFontSize(
                                                      screenWidth,
                                                      16,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                    ),

                                    if (widget.etasInfo.isNotEmpty)
                                      _buildEtasTable(context),
                                  ],
                                ),

                              ElevatedButton(
                                onPressed: widget.onClose,
                                child: Text(
                                  "Inchide",
                                  style: TextStyle(
                                    fontSize: calculateFontSize(
                                      screenWidth,
                                      19,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),

                  SizedBox(
                    height: 20,
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

            if (!_isMinimized)
              Positioned(
                top: 0.h,
                right: 0.w,
                child: IconButton(
                  icon: Icon(
                    Icons.close_rounded,
                    color: Colors.red.shade500,
                    size: 84.sp,
                  ),
                  onPressed: _showDeleteConfirmationDialog,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Column _buildEtasTable(BuildContext context) {
    return Column(
      children: [
        if (_isTableMinimized)
          Row(
            mainAxisSize: MainAxisSize.min,

            children: [
              Text(
                "Tabel estimari",
                style: TextStyle(
                  fontSize: calculateFontSize(screenWidth, 18),
                  color: Colors.grey.shade600,
                ),
              ),

              SizedBox(
                height: 80.sp,
                child: IconButton(
                  padding: EdgeInsets.all(0.sp),
                  icon: Icon(Icons.expand_more, size: 48.sp),
                  onPressed: _toggleTableMinimize,
                ),
              ),
            ],
          )
        else
          Column(
            spacing: 4,

            children: [
              // altfel vrea icon button sa ocupe spatiu prea mare, nu am gasit alternativa mai buna
              SizedBox(
                height: 80.sp,
                child: IconButton(
                  padding: EdgeInsets.all(0.sp),
                  icon: Icon(Icons.expand_less, size: 52.sp),
                  onPressed: _toggleTableMinimize,
                ),
              ),

              SizedBox(
                height: widget.etasInfo.length > 3 ? 120 : 100,

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
                      columnSpacing: 28.w,
                      horizontalMargin: 44.w,

                      columns: [
                        DataColumn(
                          label: Text(
                            "Nume statie",
                            style: TextStyle(
                              fontSize: calculateFontSize(screenWidth, 16),
                            ),
                          ),
                        ),
                        DataColumn(
                          label: Text(
                            "Timp estimat",
                            style: TextStyle(
                              fontSize: calculateFontSize(screenWidth, 16),
                            ),
                          ),
                        ),
                      ],

                      rows: widget.etasInfo.asMap().entries.map((entry) {
                        final e = entry.value;
                        final stopId = e.stop.stopId;
                        final stopName = e.stop.stopName;

                        final isNextStop = stopId == widget.nextStop!.stopId;

                        return DataRow(
                          color: stopId == widget.nextStop!.stopId
                              ? WidgetStateProperty.all(
                                  Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerLow,
                                )
                              : null,

                          cells: [
                            DataCell(
                              Text(
                                stopName,
                                style: TextStyle(
                                  fontSize: calculateFontSize(screenWidth, 13),
                                  fontWeight: isNextStop
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                            DataCell(
                              Text(
                                e.etaMessage,
                                style: TextStyle(
                                  fontSize: calculateFontSize(screenWidth, 14),
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
            ],
          ),

        Text(
          "Actualizat la: ${formattedTime(widget.lastEtaFetchTime)}",

          style: TextStyle(
            fontSize: calculateFontSize(screenWidth, 15),
            color: Colors.grey,
          ),
        ),
      ],
    );
  }
}
