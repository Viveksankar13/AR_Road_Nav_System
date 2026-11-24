import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/directions_service.dart';
import '../services/pothole_service.dart';
import '../services/location_service.dart';
import '../widgets/ar_painter.dart';

class ARNavigationScreen extends StatefulWidget {
  final DirectionsResult directionsResult;
  final LatLng destination;

  const ARNavigationScreen({
    super.key,
    required this.directionsResult,
    required this.destination,
  });

  @override
  State<ARNavigationScreen> createState() => _ARNavigationScreenState();
}

class _ARNavigationScreenState extends State<ARNavigationScreen> {
  CameraController? _cameraController;
  double? _compassHeading;
  Position? _currentPosition;
  int _currentStepIndex = 0;
  double? _distanceToNextWaypoint;
  double? _bearingToNextWaypoint;
  List<Map<String, dynamic>> _potholeWarnings = [];
  LocationService? _locationService;
  StreamSubscription<CompassEvent>? _compassSub;
  final PotholeService _potholeService = PotholeService();
  bool _isCameraReady = false;
  Timer? _potholeCheckTimer;
  final ValueNotifier<List<PotholeDetection>> _liveDetectionsNotifier = ValueNotifier([]);
  Timer? _liveScanTimer;
  bool _isScanning = false;
  int _lastScanTime = 0; // Throttles the CPU stream
  
  int _lastAccelTime = 0;
  int _lastCompassTime = 0;
  double _internalPitch = 0.0;
  
  StreamSubscription<AccelerometerEvent>? _accelSub;
  final ValueNotifier<double> _devicePitchNotifier = ValueNotifier(0.0); // 0 = Vertical, 90 = Flat on table
  final ValueNotifier<double?> _compassNotifier = ValueNotifier(null);
  Orientation _currentOrientation = Orientation.portrait;

  @override
  void initState() {
    super.initState();
    _initCamera();
    _initCompass();
    _initSensors();
    _initLocation();
  }

  void _initSensors() {
    _accelSub = accelerometerEvents.listen((AccelerometerEvent event) {
      if (!mounted) return;
      
      // Calculate absolute tilt based on how the tablet is mounted
      double absoluteTilt;
      if (_currentOrientation == Orientation.landscape) {
        absoluteTilt = atan2(event.z, event.x.abs()) * 180 / pi;
      } else {
        absoluteTilt = atan2(event.z, event.y.abs()) * 180 / pi;
      }
      
      _internalPitch = _internalPitch * 0.90 + absoluteTilt * 0.10; 
      
      // Throttle UI Redraws to 30 FPS to stop Graphics Glitching
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastAccelTime > 32) {
        _devicePitchNotifier.value = _internalPitch;
        _lastAccelTime = now;
      }
    });
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

      _cameraController = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _cameraController!.initialize();
      if (mounted) {
        setState(() => _isCameraReady = true);
        
        // Start pure RAM video stream to avoid disk writing FPS limits
        _cameraController!.startImageStream((CameraImage image) {
          if (_isScanning || !mounted) return;
          _isScanning = true;
          _runLiveInferenceStream(image);
        });
      }
    } catch (e) {
      debugPrint('Camera init error: $e');
    }
  }

  void _initCompass() {
    _compassSub = FlutterCompass.events?.listen((CompassEvent event) {
      if (mounted && event.heading != null) {
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - _lastCompassTime > 32) {
          _compassNotifier.value = event.heading;
          _lastCompassTime = now;
        }
      }
    });
  }

  void _initLocation() {
    _locationService = LocationService(
      onLocationUpdate: (position) {
        if (!mounted) return;
        setState(() {
          _currentPosition = position;
        });
        _updateNavigation();
      },
    );
    _locationService!.startTracking().then((pos) {
      setState(() => _currentPosition = pos);
      _updateNavigation();
    });

    // Periodically check for potholes along the route
    _potholeCheckTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _checkForPotholes();
    });
  }

  Future<void> _runLiveInferenceStream(CameraImage image) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    // Throttle inference: Only process 1 frame every 600 milliseconds to avoid 100% CPU lock / thermal throttling!
    if (now - _lastScanTime < 600) {
      _isScanning = false;
      return;
    }
    _lastScanTime = now;

    // Failsafe: Ensure format is strictly YUV420 (Android Standard)
    if (image.format.group != ImageFormatGroup.yuv420) {
      _isScanning = false;
      return;
    }

    try {
      final Map<String, dynamic> data = {
        'width': image.width,
        'height': image.height,
        'yPlane': image.planes[0].bytes,
        'uPlane': image.planes[1].bytes,
        'vPlane': image.planes[2].bytes,
        'yRowStride': image.planes[0].bytesPerRow,
        'uvRowStride': image.planes[1].bytesPerRow,
        'uvPixelStride': image.planes[1].bytesPerPixel ?? 1,
        'sensorOrientation': _cameraController?.description.sensorOrientation ?? 0,
      };
      
      final detections = await _potholeService.detectPotholesStream(data);
      if (mounted) {
        _liveDetectionsNotifier.value = detections;
      }
    } catch (e) {
      debugPrint('Live ML error: $e');
    } finally {
      _isScanning = false;
    }
  }

  void _updateNavigation() {
    if (_currentPosition == null) return;

    final steps = widget.directionsResult.steps;
    if (_currentStepIndex >= steps.length) return;

    final currentStep = steps[_currentStepIndex];
    final targetLat = currentStep.endLocation.latitude;
    final targetLng = currentStep.endLocation.longitude;

    // Calculate distance to the end of the current step
    final distance = Geolocator.distanceBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      targetLat,
      targetLng,
    );

    // Calculate bearing
    final bearing = _calculateBearing(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      targetLat,
      targetLng,
    );

    setState(() {
      _distanceToNextWaypoint = distance;
      _bearingToNextWaypoint = bearing;
    });

    // Advance to next step if close enough (within 25 meters)
    if (distance < 25 && _currentStepIndex < steps.length - 1) {
      setState(() {
        _currentStepIndex++;
      });
    }

    // Check if arrived at destination
    final distToDest = Geolocator.distanceBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      widget.destination.latitude,
      widget.destination.longitude,
    );
    if (distToDest < 30) {
      _showArrivalDialog();
    }
  }

  double _calculateBearing(
      double lat1, double lon1, double lat2, double lon2) {
    final dLon = (lon2 - lon1) * pi / 180;
    final lat1Rad = lat1 * pi / 180;
    final lat2Rad = lat2 * pi / 180;

    final y = sin(dLon) * cos(lat2Rad);
    final x = cos(lat1Rad) * sin(lat2Rad) -
        sin(lat1Rad) * cos(lat2Rad) * cos(dLon);

    var bearing = atan2(y, x) * 180 / pi;
    bearing = (bearing + 360) % 360;
    return bearing;
  }

  Future<void> _checkForPotholes() async {
    if (_currentPosition == null) return;
    final potholes = await _potholeService.getNearbyPotholes(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      radiusKm: 1.0,
    );

    if (mounted) {
      setState(() {
        _potholeWarnings = potholes.map((p) {
          final dist = Geolocator.distanceBetween(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
            p.latitude,
            p.longitude,
          );
          return {
            'latitude': p.latitude,
            'longitude': p.longitude,
            'distance': dist,
            'severity': p.severity,
          };
        }).toList();
        _potholeWarnings.sort(
            (a, b) => (a['distance'] as double).compareTo(b['distance'] as double));
      });
    }
  }

  void _showArrivalDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F38),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Color(0xFF00D4FF), size: 28),
            SizedBox(width: 10),
            Text('Arrived!', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Text(
          'You have reached your destination.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('DONE', style: TextStyle(color: Color(0xFF00D4FF))),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _compassSub?.cancel();
    _locationService?.stopTracking();
    _potholeCheckTimer?.cancel();
    _liveScanTimer?.cancel();
    _accelSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final steps = widget.directionsResult.steps;
    final currentStep =
        _currentStepIndex < steps.length ? steps[_currentStepIndex] : null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: OrientationBuilder(
        builder: (context, orientation) {
          _currentOrientation = orientation;
          final isLandscape = orientation == Orientation.landscape;

          return Stack(
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

              // AR Overlay decoupled from root widget using Listeners!
              ValueListenableBuilder<double>(
                valueListenable: _devicePitchNotifier,
                builder: (context, pitch, _) {
                  return ValueListenableBuilder<List<PotholeDetection>>(
                    valueListenable: _liveDetectionsNotifier,
                    builder: (context, detections, _) {
                      return ValueListenableBuilder<double?>(
                        valueListenable: _compassNotifier,
                        builder: (context, heading, _) {
                          return CustomPaint(
                            size: Size.infinite,
                            painter: ARPainter(
                              compassHeading: heading,
                              bearingToTarget: _bearingToNextWaypoint,
                              distanceToTarget: _distanceToNextWaypoint,
                              currentInstruction: currentStep?.instruction,
                              maneuver: currentStep?.maneuver,
                              potholeWarnings: _potholeWarnings,
                              liveDetections: detections,
                              devicePitch: pitch,
                              isLandscape: isLandscape,
                            ),
                          );
                        }
                      );
                    }
                  );
                }
              ),

              // Top bar
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: EdgeInsets.fromLTRB(
                      8, MediaQuery.of(context).padding.top + 4, 8, 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.7),
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
                          'AR NAVIGATION',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF00D4FF),
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 48), // Balance back button
                    ],
                  ),
                ),
              ),

              // Step counter
              Positioned(
                bottom: MediaQuery.of(context).padding.bottom + 20,
                left: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A0E21).withOpacity(0.85),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFF7C4DFF).withOpacity(0.5),
                    ),
                  ),
                  child: Text(
                    'Step ${_currentStepIndex + 1} of ${steps.length}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          );
        }
      ),
    );
  }
}
