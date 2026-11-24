import 'dart:async';

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import '../services/pothole_service.dart';
import '../services/location_service.dart';

class PotholeDetectionScreen extends StatefulWidget {
  const PotholeDetectionScreen({super.key});

  @override
  State<PotholeDetectionScreen> createState() => _PotholeDetectionScreenState();
}

class _PotholeDetectionScreenState extends State<PotholeDetectionScreen>
    with SingleTickerProviderStateMixin {
  CameraController? _cameraController;
  bool _isCameraReady = false;
  bool _isDetecting = false;
  bool _autoDetect = false;
  Timer? _autoDetectTimer;
  List<PotholeDetection> _detections = [];
  Position? _currentPosition;
  final PotholeService _potholeService = PotholeService();
  int _totalDetected = 0;
  int _totalReported = 0;
  late AnimationController _scanAnimController;

  @override
  void initState() {
    super.initState();
    _scanAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _initCamera();
    _initLocation();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

      _cameraController = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _cameraController!.initialize();
      if (mounted) {
        setState(() => _isCameraReady = true);
      }
    } catch (e) {
      debugPrint('Camera error: $e');
    }
  }

  void _initLocation() async {
    try {
      _currentPosition = await LocationService.getCurrentPosition();
    } catch (e) {
      debugPrint('Location error: $e');
    }
  }

  Future<void> _captureAndDetect() async {
    if (_cameraController == null || _isDetecting) return;

    setState(() => _isDetecting = true);

    try {
      final image = await _cameraController!.takePicture();
      final bytes = await image.readAsBytes();

      final detections = await _potholeService.detectPotholes(bytes);

      setState(() {
        _detections = detections;
        _totalDetected += detections.length;
        _isDetecting = false;
      });

      // Auto-report detected potholes
      if (detections.isNotEmpty && _currentPosition != null) {
        for (final detection in detections) {
          // Only report high-confidence detections
          if (detection.confidence > 0.5) {
            final severity = detection.confidence > 0.8
                ? 'high'
                : detection.confidence > 0.6
                    ? 'medium'
                    : 'low';

            await _potholeService.reportPothole(
              _currentPosition!.latitude,
              _currentPosition!.longitude,
              severity,
            );
            setState(() => _totalReported++);
          }
        }
      }
    } catch (e) {
      debugPrint('Detection error: $e');
      setState(() => _isDetecting = false);
    }
  }

  void _toggleAutoDetect() {
    setState(() => _autoDetect = !_autoDetect);
    if (_autoDetect) {
      _autoDetectTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        _captureAndDetect();
      });
    } else {
      _autoDetectTimer?.cancel();
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _autoDetectTimer?.cancel();
    _scanAnimController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Camera preview
          if (_isCameraReady && _cameraController != null)
            ClipRect(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _cameraController!.value.previewSize?.height ?? 1,
                  height: _cameraController!.value.previewSize?.width ?? 1,
                  child: CameraPreview(_cameraController!),
                ),
              ),
            )
          else
            const Center(
              child: CircularProgressIndicator(color: Color(0xFF00D4FF)),
            ),

          // Detection bounding boxes
          if (_detections.isNotEmpty)
            CustomPaint(
              size: Size.infinite,
              painter: _DetectionBoxPainter(detections: _detections),
            ),

          // Scanning overlay animation
          if (_isDetecting)
            AnimatedBuilder(
              animation: _scanAnimController,
              builder: (context, _) {
                return Positioned(
                  top: MediaQuery.of(context).size.height *
                      _scanAnimController.value,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          const Color(0xFF00D4FF).withOpacity(0.8),
                          Colors.transparent,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00D4FF).withOpacity(0.4),
                          blurRadius: 20,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

          // Top bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                  8, MediaQuery.of(context).padding.top + 4, 8, 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.8),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Expanded(
                    child: Text(
                      'POTHOLE SCANNER',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFFFF5252),
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
          ),

          // Detection status + crosshair
          Center(
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(
                  color: _detections.isNotEmpty
                      ? const Color(0xFFFF5252).withOpacity(0.8)
                      : const Color(0xFF00D4FF).withOpacity(0.3),
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),

          // Bottom panel
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                  20, 20, 20, MediaQuery.of(context).padding.bottom + 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    const Color(0xFF0A0E21).withOpacity(0.95),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Stats row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _statBadge(
                        Icons.visibility,
                        '$_totalDetected',
                        'Detected',
                        const Color(0xFF00D4FF),
                      ),
                      _statBadge(
                        Icons.report,
                        '$_totalReported',
                        'Reported',
                        const Color(0xFFFF9100),
                      ),
                      _statBadge(
                        Icons.gps_fixed,
                        _currentPosition != null ? 'Active' : 'Off',
                        'GPS',
                        const Color(0xFF69F0AE),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Detection results
                  if (_detections.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF5252).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFFF5252).withOpacity(0.5),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded,
                              color: Color(0xFFFF5252)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '${_detections.length} pothole(s) detected! '
                              'Confidence: ${(_detections.first.confidence * 100).toStringAsFixed(0)}%',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Control buttons
                  Row(
                    children: [
                      // Auto-detect toggle
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _toggleAutoDetect,
                          icon: Icon(
                            _autoDetect ? Icons.stop : Icons.loop,
                          ),
                          label: Text(_autoDetect ? 'STOP' : 'AUTO'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _autoDetect
                                ? const Color(0xFFFF5252)
                                : const Color(0xFF00D4FF),
                            side: BorderSide(
                              color: _autoDetect
                                  ? const Color(0xFFFF5252)
                                  : const Color(0xFF00D4FF),
                              width: 1.5,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Manual capture button
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: _isDetecting ? null : _captureAndDetect,
                          icon: _isDetecting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.black,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.camera),
                          label: Text(
                              _isDetecting ? 'SCANNING...' : 'SCAN ROAD'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF5252),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statBadge(
      IconData icon, String value, String label, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(color: color.withOpacity(0.5)),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.5),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

/// Draws bounding boxes on detected potholes.
class _DetectionBoxPainter extends CustomPainter {
  final List<PotholeDetection> detections;

  _DetectionBoxPainter({required this.detections});

  @override
  void paint(Canvas canvas, Size size) {
    for (final det in detections) {
      // Convert normalized coordinates to screen coordinates
      final x = det.xCenter * size.width;
      final y = det.yCenter * size.height;
      final w = det.width * size.width;
      final h = det.height * size.height;

      final rect = Rect.fromCenter(
        center: Offset(x, y),
        width: w,
        height: h,
      );

      // Box
      final boxPaint = Paint()
        ..color = const Color(0xFFFF1744).withOpacity(0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        boxPaint,
      );

      // Fill
      final fillPaint = Paint()
        ..color = const Color(0xFFFF1744).withOpacity(0.1)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        fillPaint,
      );

      // Label
      final confidence = (det.confidence * 100).toStringAsFixed(0);
      final tp = TextPainter(
        text: TextSpan(
          text: '${det.className} $confidence%',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            backgroundColor: Color(0xAAFF1744),
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(rect.left, rect.top - tp.height - 2));
    }
  }

  @override
  bool shouldRepaint(covariant _DetectionBoxPainter oldDelegate) {
    return oldDelegate.detections != detections;
  }
}
