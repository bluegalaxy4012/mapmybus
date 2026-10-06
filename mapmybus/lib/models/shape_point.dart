class ShapePoint {
  final String shapeId;
  final double latitude;
  final double longitude;
  final int sequence;

  const ShapePoint({
    required this.shapeId,
    required this.latitude,
    required this.longitude,
    required this.sequence,
  });

  factory ShapePoint.fromJson(Map<String, dynamic> json) {
    return ShapePoint(
      shapeId: json['shape_id'] as String,
      latitude: (json['shape_pt_lat'] as num).toDouble(),
      longitude: (json['shape_pt_lon'] as num).toDouble(),
      sequence: (json['shape_pt_sequence'] as num).toInt(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'shape_id': shapeId,
      'shape_pt_lat': latitude,
      'shape_pt_lon': longitude,
      'shape_pt_sequence': sequence,
    };
  }
}
