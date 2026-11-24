import 'dart:math';
import 'package:flutter/material.dart';
import '../services/pothole_service.dart';

/// Custom painter that renders AR-style direction arrows, distance info,
/// and pothole warnings on top of the camera preview.
class ARPainter extends CustomPainter {
  final double? compassHeading; // Device compass heading in degrees (0-360)
  final double? bearingToTarget; // Bearing from current position to next waypoint
  final double? distanceToTarget; // Distance in meters to next waypoint
  final String? currentInstruction; // Current navigation step text
  final String? maneuver; // turn-left, turn-right, etc.
  final List<Map<String, dynamic>> potholeWarnings; // Nearby pothole markers
  final List<PotholeDetection> liveDetections; // AI Pothole Bounding Boxes
  final double devicePitch; // Hardware Tilt (0 = upright, 90 = flat)
  final bool isLandscape; // Screen orientation

  ARPainter({
    this.compassHeading,
    this.bearingToTarget,
    this.distanceToTarget,
    this.currentInstruction,
    this.maneuver,
    this.potholeWarnings = const [],
    this.liveDetections = const [],
    this.devicePitch = 0.0,
    this.isLandscape = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawLiveDetections(canvas, size);
    _drawDirectionArrow(canvas, size);
    _drawNavigationInfo(canvas, size);
    _drawPotholeWarnings(canvas, size);
    _drawHUD(canvas, size);
  }

  void _drawDirectionArrow(Canvas canvas, Size size) {
    if (compassHeading == null || bearingToTarget == null) return;

    final centerX = size.width / 2;
    
    // Dynamic Horizon Mapping based on Physics
    // As you tilt the device flat, the arrow slides down to the "floor"
    final dynamicYPos = 0.4 + (min(devicePitch, 80) / 90.0) * 0.45;
    final centerY = size.height * dynamicYPos;

    // Calculate relative angle: how much must user turn
    double relativeAngle = bearingToTarget! - compassHeading!;
    // Normalize to -180..180
    while (relativeAngle > 180) relativeAngle -= 360;
    while (relativeAngle < -180) relativeAngle += 360;

    final angleRad = relativeAngle * pi / 180;

    // Arrow properties
    final arrowLength = size.width * 0.18;
    final arrowPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF00D4FF), Color(0xFF7C4DFF)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromCenter(
          center: Offset(centerX, centerY),
          width: arrowLength * 2,
          height: arrowLength * 2));
    arrowPaint.style = PaintingStyle.fill;

    // Glow effect
    final glowPaint = Paint()
      ..color = const Color(0xFF00D4FF).withOpacity(0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);

    canvas.save();
    canvas.translate(centerX, centerY);
    
    // 3D Perspective Transform
    final Matrix4 matrix = Matrix4.identity()
      ..setEntry(3, 2, 0.003) // Deep perspective warp
      ..rotateX((min(devicePitch, 70)) * pi / 180); // Tilt flat on physical road plane
      
    canvas.transform(matrix.storage);
    canvas.rotate(angleRad);

    // Draw glow
    final glowPath = _createArrowPath(arrowLength * 1.1);
    canvas.drawPath(glowPath, glowPaint);

    // Draw arrow
    final arrowPath = _createArrowPath(arrowLength);
    canvas.drawPath(arrowPath, arrowPaint);

    // Arrow outline
    final outlinePaint = Paint()
      ..color = Colors.white.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawPath(arrowPath, outlinePaint);

    canvas.restore();

    // Draw pulsing circle around arrow
    final pulsePaint = Paint()
      ..color = const Color(0xFF00D4FF).withOpacity(0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(Offset(centerX, centerY), arrowLength * 1.5, pulsePaint);
  }

  Path _createArrowPath(double length) {
    final path = Path();
    final halfWidth = length * 0.45;
    final notchDepth = length * 0.25;

    path.moveTo(0, -length); // Tip
    path.lineTo(halfWidth, length * 0.3);
    path.lineTo(halfWidth * 0.5, length * 0.1);
    path.lineTo(0, notchDepth); // Notch center
    path.lineTo(-halfWidth * 0.5, length * 0.1);
    path.lineTo(-halfWidth, length * 0.3);
    path.close();

    return path;
  }

  void _drawNavigationInfo(Canvas canvas, Size size) {
    // Distance badge
    if (distanceToTarget != null) {
      final distText = distanceToTarget! > 1000
          ? '${(distanceToTarget! / 1000).toStringAsFixed(1)} km'
          : '${distanceToTarget!.toInt()} m';

      final bgPaint = Paint()
        ..color = const Color(0xFF0A0E21).withOpacity(0.85)
        ..style = PaintingStyle.fill;

      final badgeRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(size.width / 2, size.height * 0.62),
          width: 160,
          height: 50,
        ),
        const Radius.circular(25),
      );

      // Badge border
      final borderPaint = Paint()
        ..color = const Color(0xFF00D4FF).withOpacity(0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      canvas.drawRRect(badgeRect, bgPaint);
      canvas.drawRRect(badgeRect, borderPaint);

      final textPainter = TextPainter(
        text: TextSpan(
          text: distText,
          style: const TextStyle(
            color: Color(0xFF00D4FF),
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          size.width / 2 - textPainter.width / 2,
          size.height * 0.62 - textPainter.height / 2,
        ),
      );
    }

    // Instruction text
    if (currentInstruction != null && currentInstruction!.isNotEmpty) {
      final bgPaint = Paint()
        ..color = const Color(0xFF0A0E21).withOpacity(0.85);

      final instructRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(20, size.height * 0.78, size.width - 40, 70),
        const Radius.circular(16),
      );
      canvas.drawRRect(instructRect, bgPaint);

      final borderPaint = Paint()
        ..color = const Color(0xFF7C4DFF).withOpacity(0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawRRect(instructRect, borderPaint);

      // Maneuver icon
      String maneuverIcon = '➡️';
      if (maneuver != null) {
        if (maneuver!.contains('left')) maneuverIcon = '⬅️';
        if (maneuver!.contains('right')) maneuverIcon = '➡️';
        if (maneuver!.contains('straight') || maneuver!.contains('continue')) {
          maneuverIcon = '⬆️';
        }
        if (maneuver!.contains('uturn')) maneuverIcon = '↩️';
      }

      final iconPainter = TextPainter(
        text: TextSpan(
          text: maneuverIcon,
          style: const TextStyle(fontSize: 24),
        ),
        textDirection: TextDirection.ltr,
      );
      iconPainter.layout();
      iconPainter.paint(canvas, Offset(35, size.height * 0.78 + 20));

      final instrPainter = TextPainter(
        text: TextSpan(
          text: currentInstruction,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 2,
        ellipsis: '...',
      );
      instrPainter.layout(maxWidth: size.width - 110);
      instrPainter.paint(canvas, Offset(70, size.height * 0.78 + 18));
    }
  }

  void _drawPotholeWarnings(Canvas canvas, Size size) {
    if (potholeWarnings.isEmpty) return;

    for (final warning in potholeWarnings) {
      final distance = (warning['distance'] as num?)?.toDouble() ?? 100;
      final severity = warning['severity'] as String? ?? 'medium';

      // Only show nearby potholes (< 500m)
      if (distance > 500) continue;

      Color warningColor;
      String label;
      double iconSize;

      if (distance < 50) {
        warningColor = const Color(0xFFFF1744);
        label = '⚠️ POTHOLE ${distance.toInt()}m';
        iconSize = 32;
      } else if (distance < 200) {
        warningColor = const Color(0xFFFF9100);
        label = '⚠️ Pothole ${distance.toInt()}m';
        iconSize = 24;
      } else {
        warningColor = const Color(0xFFFFD600);
        label = 'Pothole ahead ${distance.toInt()}m';
        iconSize = 18;
      }

      // Warning banner at top
      final bannerPaint = Paint()
        ..color = warningColor.withOpacity(0.9);

      final bannerRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(size.width / 2, size.height * 0.12),
          width: size.width * 0.8,
          height: 44,
        ),
        const Radius.circular(22),
      );
      canvas.drawRRect(bannerRect, bannerPaint);

      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: Colors.white,
            fontSize: iconSize * 0.6,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          size.width / 2 - textPainter.width / 2,
          size.height * 0.12 - textPainter.height / 2,
        ),
      );
      break; // Show only nearest pothole warning
    }
  }

  void _drawHUD(Canvas canvas, Size size) {
    // Top-left compass heading
    if (compassHeading != null) {
      final headingText = '${compassHeading!.toInt()}°';
      final dirs = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
      final dirIndex = ((compassHeading! + 22.5) ~/ 45) % 8;
      final direction = dirs[dirIndex];

      final tp = TextPainter(
        text: TextSpan(
          text: '$headingText $direction',
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, const Offset(20, 50));
    }
  }

  void _drawLiveDetections(Canvas canvas, Size size) {
    if (liveDetections.isEmpty) return;

    for (final det in liveDetections) {
      // Direct 1:1 Mapping: The AI input tensor was mathematically un-rotated 
      // in the background thread, meaning YOLO X and Y coordinates now 
      // perfectly map to the physical screen pixels!
      double tfliteX = det.xCenter;
      double tfliteY = det.yCenter;
      double tfliteW = det.width;
      double tfliteH = det.height;

      final x = tfliteX * size.width;
      final y = tfliteY * size.height;
      final w = tfliteW * size.width;
      final h = tfliteH * size.height;

      final rect = Rect.fromCenter(
        center: Offset(x, y),
        width: w,
        height: h,
      );

      // AR Projection Glow
      final glowPaint = Paint()
        ..color = const Color(0xFFFF5252).withOpacity(0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 15);
      
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(8)),
        glowPaint,
      );

      // Box Outline
      final boxPaint = Paint()
        ..color = const Color(0xFFFF1744).withOpacity(0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5;
      
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(8)),
        boxPaint,
      );

      // Inner Tint
      final fillPaint = Paint()
        ..color = const Color(0xFFFF1744).withOpacity(0.2)
        ..style = PaintingStyle.fill;
      
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(8)),
        fillPaint,
      );

      // Cyberpunk confidence label
      final confidence = (det.confidence * 100).toStringAsFixed(0);
      final labelPaint = Paint()..color = const Color(0xFFFF1744);
      
      final labelRect = Rect.fromLTWH(rect.left, rect.top - 20, 95, 20);
      canvas.drawRect(labelRect, labelPaint);

      final tp = TextPainter(
        text: TextSpan(
          text: 'POTHOLE $confidence%',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.0,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(rect.left + 5, rect.top - 18));
      
      // Draw gridlines inside the box for AR effect 
      final gridPaint = Paint()
        ..color = const Color(0xFFFF1744).withOpacity(0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
        
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), gridPaint);
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), gridPaint);
    }
  }

  @override
  bool shouldRepaint(covariant ARPainter oldDelegate) {
    return oldDelegate.compassHeading != compassHeading ||
        oldDelegate.bearingToTarget != bearingToTarget ||
        oldDelegate.distanceToTarget != distanceToTarget ||
        oldDelegate.currentInstruction != currentInstruction ||
        oldDelegate.potholeWarnings != potholeWarnings ||
        oldDelegate.liveDetections != liveDetections ||
        oldDelegate.devicePitch != devicePitch ||
        oldDelegate.isLandscape != isLandscape;
  }
}
