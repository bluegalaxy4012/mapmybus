import 'package:flutter/material.dart';
import 'dart:math';

class UserLocationMarker extends StatefulWidget {
  final double heading;

  const UserLocationMarker({super.key, required this.heading});

  @override
  State<UserLocationMarker> createState() => _UserLocationMarkerState();
}

class _UserLocationMarkerState extends State<UserLocationMarker>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    // simple pulse
    _animation = Tween<double>(
      begin: 0.9,
      end: 1.1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,

      children: [
        ScaleTransition(
          scale: _animation,

          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: Colors.lightBlue,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.blueGrey, width: 2),
            ),
          ),
        ),

        if (widget.heading != 0.0) // invalid de obicei
          Transform.rotate(
            angle: widget.heading * (pi / 180),

            child: Transform.translate(
              offset: const Offset(0, -10),
              child: const Icon(Icons.navigation, color: Colors.blue, size: 20),
            ),
          ),
      ],
    );
  }
}
