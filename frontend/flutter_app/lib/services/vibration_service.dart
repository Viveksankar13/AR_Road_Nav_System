import 'dart:async';
import 'dart:math';
import 'package:sensors_plus/sensors_plus.dart';

class VibrationService {
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  final double threshold;
  final Function(double intensity) onRoughRoadDetected;

  VibrationService({
    required this.onRoughRoadDetected,
    this.threshold = 12.0,
  });

  void startMonitoring() {
    _accelerometerSubscription =
        accelerometerEvents.listen((AccelerometerEvent event) {
      double magnitude =
          sqrt(event.x * event.x + event.y * event.y + event.z * event.z);

      // Deviation from gravity (~9.8) indicates a bump
      if ((magnitude - 9.8).abs() > threshold) {
        onRoughRoadDetected((magnitude - 9.8).abs());
      }
    });
  }

  void stopMonitoring() {
    _accelerometerSubscription?.cancel();
  }
}
