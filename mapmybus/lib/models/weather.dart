import 'package:flutter/material.dart';

class WeatherInfo {
  final String reliability; // good | reduced | poor
  final String? message;
  final String label;
  final double temperature;

  WeatherInfo({
    required this.reliability,
    this.message,
    required this.label,
    required this.temperature,
  });

  factory WeatherInfo.fromJson(Map<String, dynamic> j) => WeatherInfo(
    reliability: j['eta_reliability'] as String? ?? 'good',
    message: j['message'] as String?,
    label: j['label'] as String? ?? '',
    temperature: (j['temperature'] as num?)?.toDouble() ?? 0,
  );

  bool get shouldWarn => reliability != 'good' && message != null;

  Color get color =>
      reliability == 'poor' ? Colors.red.shade100 : Colors.amber.shade100;
}
