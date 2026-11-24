import 'dart:typed_data';
import 'dart:math';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:flutter/foundation.dart'; // For compute()
import 'pothole_service.dart';

/// Top-level function for background isolate execution
/// Decodes the heavy JPEG and prepares the 640x640 Float32 tensor 
List<List<List<List<double>>>> _prepareImageTensor(Uint8List imageBytes) {
  final img.Image? decodedImage = img.decodeImage(imageBytes);
  if (decodedImage == null) return [];
  
  final img.Image resized = img.copyResize(decodedImage, width: 640, height: 640);
  
  var input = List.generate(1, (i) => 
    List.generate(640, (y) => 
      List.generate(640, (x) => 
        List.filled(3, 0.0)
      )
    )
  );
  
  for (int y = 0; y < 640; y++) {
    for (int x = 0; x < 640; x++) {
      final pixel = resized.getPixelSafe(x, y);
      input[0][y][x][0] = pixel.r / 255.0; 
      input[0][y][x][1] = pixel.g / 255.0;
      input[0][y][x][2] = pixel.b / 255.0;
    }
  }
  return input;
}

/// Ultra-Fast Full Color RAM Stream Decoder (No Disk I/O, No Image packages)
/// Takes raw YUV420 from Camera, Center-Crops to 1:1, and decodes to RGB Float Tensor
List<List<List<List<double>>>> _prepareYuv420Tensor(Map<String, dynamic> data) {
  final int width = data['width'];
  final int height = data['height'];
  final Uint8List yPlane = data['yPlane'];
  final Uint8List uPlane = data['uPlane'];
  final Uint8List vPlane = data['vPlane'];
  final int yRowStride = data['yRowStride'];
  final int uvRowStride = data['uvRowStride'];
  final int uvPixelStride = data['uvPixelStride'];
  final int sensorOrientation = data['sensorOrientation'] ?? 0;
  
  var input = List.generate(1, (i) => 
    List.generate(640, (y) => 
      List.generate(640, (x) => 
        List.filled(3, 0.0)
      )
    )
  );
  
  // Center-Crop physically prevents the 16:9 distortion squish!
  int cropSize = width < height ? width : height;
  int startX = (width - cropSize) ~/ 2;
  int startY = (height - cropSize) ~/ 2;

  for (int y = 0; y < 640; y++) {
    int srcY = startY + (y * cropSize) ~/ 640;
    int uvY = srcY ~/ 2;
    for (int x = 0; x < 640; x++) {
      int srcX = startX + (x * cropSize) ~/ 640;
      int uvX = srcX ~/ 2;
      
      int yIndex = srcY * yRowStride + srcX;
      int uvIndex = uvY * uvRowStride + uvX * uvPixelStride;

      // Ensure varying Android camera bounds padding doesn't crash the Isolates
      if (yIndex >= yPlane.length) yIndex = yPlane.length - 1;
      if (uvIndex >= uPlane.length) uvIndex = uPlane.length - 1;

      int yp = yPlane[yIndex];
      int up = uPlane[uvIndex];
      int vp = vPlane[uvIndex];

      // Integer Math YUV to RGB conversion
      int c = yp - 16;
      if (c < 0) c = 0;
      int d = up - 128;
      int e = vp - 128;

      int r = (298 * c           + 409 * e + 128) >> 8;
      int g = (298 * c - 100 * d - 208 * e + 128) >> 8;
      int b = (298 * c + 516 * d           + 128) >> 8;

      double fR = r.clamp(0, 255) / 255.0;
      double fG = g.clamp(0, 255) / 255.0;
      double fB = b.clamp(0, 255) / 255.0;

      // Un-rotate the physical sensor hardware rotation so the AI sees the Road upright
      if (sensorOrientation == 90) {
        input[0][x][639 - y][0] = fR;
        input[0][x][639 - y][1] = fG;
        input[0][x][639 - y][2] = fB;
      } else if (sensorOrientation == 270) {
        input[0][639 - x][y][0] = fR;
        input[0][639 - x][y][1] = fG;
        input[0][639 - x][y][2] = fB;
      } else if (sensorOrientation == 180) {
        input[0][639 - y][639 - x][0] = fR;
        input[0][639 - y][639 - x][1] = fG;
        input[0][639 - y][639 - x][2] = fB;
      } else {
        input[0][y][x][0] = fR;
        input[0][y][x][1] = fG;
        input[0][y][x][2] = fB;
      }
    }
  }
  return input;
}

class TFLiteService {
  static final TFLiteService _instance = TFLiteService._internal();
  factory TFLiteService() => _instance;
  TFLiteService._internal();

  Interpreter? _interpreter;
  IsolateInterpreter? _isolateInterpreter; // Runs ML model off the UI thread
  bool _isInit = false;

  /// Initializes the TFLite interpreter with the bundled YOLOv11n INT8 model.
  Future<void> init() async {
    if (_isInit) return;
    try {
      _interpreter = await Interpreter.fromAsset(
        'assets/models/pothole_yolo11n_int8.tflite',
        options: InterpreterOptions(),
      );
      
      // Initialize Isolate to completely shield the UI thread from Inference
      _isolateInterpreter = await IsolateInterpreter.create(address: _interpreter!.address);
      
      _isInit = true;
      print('TFLite Model and Isolate Interpreter Loaded Successfully.');
    } catch (e) {
      print('❌ Error loading TFLite model: $e');
    }
  }

  /// Processes JPEG bytes from the camera, runs inference, and performs Non-Maximum Suppression.
  Future<List<PotholeDetection>> detectPotholes(Uint8List imageBytes, {double confThreshold = 0.25, double iouThreshold = 0.45}) async {
    if (!_isInit || _interpreter == null) {
      print('TFLite Interpreter not initialized yet.');
      return [];
    }

    // 1 & 2. Background Process: Decode, Resize, and Format Input Tensor
    // This removes 400ms of CPU blocking from the main UI thread!
    final input = await compute(_prepareImageTensor, imageBytes);
    if (input.isEmpty) return [];

    // 3. Format Output Tensor
    final outShape = _interpreter!.getOutputTensors()[0].shape;
    
    try {
      if (outShape.length == 3 && outShape[1] == 8400 && outShape[2] == 5) {
         var outputTransposed = List.generate(1, (i) => List.generate(8400, (j) => List.filled(5, 0.0)));
         _interpreter!.run(input, outputTransposed);
         return _parseBoxesTransposed(outputTransposed[0], confThreshold, iouThreshold);
      } else {
         var output = List.generate(1, (i) => List.generate(5, (j) => List.filled(8400, 0.0)));
         _interpreter!.run(input, output);
         return _parseBoxes(output[0], confThreshold, iouThreshold);
      }
    } catch (e) {
      print('TFLite Run Error: $e');
      return [];
    }
  }

  /// Processes raw Camera RAM stream (Y-Plane) to avoid disk I/O completely.
  Future<List<PotholeDetection>> detectPotholesStream(Map<String, dynamic> data, {double confThreshold = 0.25, double iouThreshold = 0.45}) async {
    if (!_isInit || _interpreter == null || _isolateInterpreter == null) return [];

    // Background Process: Full Color YUV -> RGB with Center Cropping
    final input = await compute(_prepareYuv420Tensor, data);
    if (input.isEmpty) return [];

    // 3. Format Output Tensor
    final outShape = _interpreter!.getOutputTensors()[0].shape;
    
    try {
      if (outShape.length == 3 && outShape[1] == 8400 && outShape[2] == 5) {
         var outputTransposed = List.generate(1, (i) => List.generate(8400, (j) => List.filled(5, 0.0)));
         await _isolateInterpreter!.run(input, outputTransposed);
         return _parseBoxesTransposed(outputTransposed[0], confThreshold, iouThreshold);
      } else {
         var output = List.generate(1, (i) => List.generate(5, (j) => List.filled(8400, 0.0)));
         await _isolateInterpreter!.run(input, output);
         return _parseBoxes(output[0], confThreshold, iouThreshold);
      }
    } catch (e) {
      print('TFLite Run Error: $e');
      return [];
    }
  }

  /// Parses [5, 8400] tensor into PotholeDetection objects
  List<PotholeDetection> _parseBoxes(List<List<double>> out, double confThresh, double iouThresh) {
    List<PotholeDetection> candidates = [];
    for (int i = 0; i < 8400; i++) {
        final conf = out[4][i];
        if (conf > confThresh) { 
            candidates.add(PotholeDetection(
                classId: 0,
                className: 'pothole',
                confidence: conf,
                xCenter: out[0][i] / 640.0,
                yCenter: out[1][i] / 640.0,
                width: out[2][i] / 640.0,
                height: out[3][i] / 640.0
            ));
        }
    }
    return _applyNMS(candidates, iouThresh);
  }

  /// Parses [8400, 5] tensor into PotholeDetection objects
  List<PotholeDetection> _parseBoxesTransposed(List<List<double>> out, double confThresh, double iouThresh) {
    List<PotholeDetection> candidates = [];
    for (int i = 0; i < 8400; i++) {
        final conf = out[i][4];
        if (conf > confThresh) {
            candidates.add(PotholeDetection(
                classId: 0, 
                className: 'pothole', 
                confidence: conf,
                xCenter: out[i][0] / 640.0, 
                yCenter: out[i][1] / 640.0, 
                width: out[i][2] / 640.0, 
                height: out[i][3] / 640.0
            ));
        }
    }
    return _applyNMS(candidates, iouThresh);
  }

  /// Non-Maximum Suppression to remove perfectly overlapping duplicate bounding boxes
  List<PotholeDetection> _applyNMS(List<PotholeDetection> boxes, double iouThreshold) {
     if (boxes.isEmpty) return [];
     
     // Sort by highest confidence first
     boxes.sort((a,b) => b.confidence.compareTo(a.confidence));
     
     List<PotholeDetection> finalBoxes = [];
     List<bool> suppressed = List.filled(boxes.length, false);

     for (int i = 0; i < boxes.length; i++) {
         if (suppressed[i]) continue;
         finalBoxes.add(boxes[i]);
         for (int j = i + 1; j < boxes.length; j++) {
             if (suppressed[j]) continue;
             if (_calculateIOU(boxes[i], boxes[j]) > iouThreshold) { 
                 suppressed[j] = true;
             }
         }
     }
     return finalBoxes;
  }

  double _calculateIOU(PotholeDetection box1, PotholeDetection box2) {
      final b1Left = box1.xCenter - box1.width/2;
      final b1Right = box1.xCenter + box1.width/2;
      final b1Top = box1.yCenter - box1.height/2;
      final b1Bottom = box1.yCenter + box1.height/2;

      final b2Left = box2.xCenter - box2.width/2;
      final b2Right = box2.xCenter + box2.width/2;
      final b2Top = box2.yCenter - box2.height/2;
      final b2Bottom = box2.yCenter + box2.height/2;

      final interLeft = max(b1Left, b2Left);
      final interTop = max(b1Top, b2Top);
      final interRight = min(b1Right, b2Right);
      final interBottom = min(b1Bottom, b2Bottom);

      if (interRight < interLeft || interBottom < interTop) return 0.0;

      final interArea = (interRight - interLeft) * (interBottom - interTop);
      final b1Area = box1.width * box1.height;
      final b2Area = box2.width * box2.height;

      return interArea / (b1Area + b2Area - interArea);
  }
}
