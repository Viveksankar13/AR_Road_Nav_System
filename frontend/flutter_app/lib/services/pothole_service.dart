import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../config/api_keys.dart';
import 'tflite_service.dart';

/// A detected pothole from the backend inference.
class PotholeDetection {
  final int classId;
  final String className;
  final double confidence;
  final double xCenter;
  final double yCenter;
  final double width;
  final double height;

  PotholeDetection({
    required this.classId,
    required this.className,
    required this.confidence,
    required this.xCenter,
    required this.yCenter,
    required this.width,
    required this.height,
  });

  factory PotholeDetection.fromJson(Map<String, dynamic> json) {
    final bbox = json['bbox'] as List;
    return PotholeDetection(
      classId: json['class_id'],
      className: json['class_name'],
      confidence: (json['confidence'] as num).toDouble(),
      xCenter: (bbox[0] as num).toDouble(),
      yCenter: (bbox[1] as num).toDouble(),
      width: (bbox[2] as num).toDouble(),
      height: (bbox[3] as num).toDouble(),
    );
  }
}

/// A pothole report from the database.
class PotholeReport {
  final double latitude;
  final double longitude;
  final String severity;
  final String reportedAt;

  PotholeReport({
    required this.latitude,
    required this.longitude,
    required this.severity,
    required this.reportedAt,
  });

  factory PotholeReport.fromJson(Map<String, dynamic> json) {
    return PotholeReport(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      severity: json['severity'] ?? 'medium',
      reportedAt: json['reported_at'] ?? '',
    );
  }
}

class PotholeService {
  final String baseUrl;
  final TFLiteService _tfliteService = TFLiteService();

  PotholeService({String? baseUrl})
      : baseUrl = baseUrl ?? ApiConfig.backendBaseUrl {
    // Initialize the offline TFLite AI model when the service is created
    _tfliteService.init();
  }

  /// Send an image (as JPEG bytes) to the local on-device TFLite model.
  Future<List<PotholeDetection>> detectPotholes(Uint8List imageBytes) async {
    // Inference runs offline on the tablet CPU! No internet required.
    return await _tfliteService.detectPotholes(imageBytes);
  }

  /// Process a raw Y-plane from the RAM stream
  Future<List<PotholeDetection>> detectPotholesStream(Map<String, dynamic> data) async {
    return await _tfliteService.detectPotholesStream(data);
  }

  /// Report a pothole at the given GPS coordinates.
  Future<bool> reportPothole(
      double latitude, double longitude, String severity) async {
    try {
      final uri = Uri.parse('$baseUrl/report_pothole');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'latitude': latitude,
          'longitude': longitude,
          'severity': severity,
          'timestamp': DateTime.now().millisecondsSinceEpoch / 1000,
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('PotholeService.reportPothole error: $e');
      return false;
    }
  }

  /// Get reported potholes near a location.
  Future<List<PotholeReport>> getNearbyPotholes(
      double lat, double lng,
      {double radiusKm = 5.0}) async {
    try {
      final uri = Uri.parse(
          '$baseUrl/get_potholes?lat=$lat&lng=$lng&radius_km=$radiusKm');
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final potholes = data['potholes'] as List? ?? [];
        return potholes.map((p) => PotholeReport.fromJson(p)).toList();
      }
    } catch (e) {
      print('PotholeService.getNearbyPotholes error: $e');
    }
    return [];
  }
}
