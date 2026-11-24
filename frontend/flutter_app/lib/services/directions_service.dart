import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../config/api_keys.dart';

/// Represents a single step in a navigation route.
class DirectionStep {
  final String instruction; // HTML instructions (e.g., "Turn left onto Main St")
  final String distance;    // e.g., "200 m"
  final String duration;    // e.g., "1 min"
  final String? maneuver;   // e.g., "turn-left", "turn-right", null
  final LatLng startLocation;
  final LatLng endLocation;

  DirectionStep({
    required this.instruction,
    required this.distance,
    required this.duration,
    this.maneuver,
    required this.startLocation,
    required this.endLocation,
  });
}

/// Result from a directions query containing the route polyline and steps.
class DirectionsResult {
  final List<LatLng> polylinePoints;
  final List<DirectionStep> steps;
  final String totalDistance;
  final String totalDuration;

  DirectionsResult({
    required this.polylinePoints,
    required this.steps,
    required this.totalDistance,
    required this.totalDuration,
  });
}

class DirectionsService {
  final String apiKey;

  DirectionsService({String? apiKey})
      : apiKey = apiKey ?? ApiConfig.googleMapsApiKey;

  /// Fetches route from origin to destination with full step-by-step directions.
  Future<DirectionsResult?> getDirections(
      LatLng origin, LatLng destination) async {
    final url = 'https://maps.googleapis.com/maps/api/directions/json'
        '?origin=${origin.latitude},${origin.longitude}'
        '&destination=${destination.latitude},${destination.longitude}'
        '&mode=driving'
        '&key=$apiKey';

    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['routes'] != null && json['routes'].isNotEmpty) {
          final route = json['routes'][0];
          final leg = route['legs'][0];

          // Decode polyline
          final polylinePoints =
              _decodePolyline(route['overview_polyline']['points']);

          // Parse steps
          final List<DirectionStep> steps = [];
          for (var step in leg['steps']) {
            steps.add(DirectionStep(
              instruction:
                  _stripHtml(step['html_instructions'] ?? ''),
              distance: step['distance']['text'] ?? '',
              duration: step['duration']['text'] ?? '',
              maneuver: step['maneuver'],
              startLocation: LatLng(
                step['start_location']['lat'],
                step['start_location']['lng'],
              ),
              endLocation: LatLng(
                step['end_location']['lat'],
                step['end_location']['lng'],
              ),
            ));
          }

          return DirectionsResult(
            polylinePoints: polylinePoints,
            steps: steps,
            totalDistance: leg['distance']['text'] ?? '',
            totalDuration: leg['duration']['text'] ?? '',
          );
        }
      }
    } catch (e) {
      print('DirectionsService error: $e');
    }
    return null;
  }

  /// Simple search for a place name and return its coordinates.
  Future<List<Map<String, dynamic>>> searchPlaces(String query) async {
    final url =
        'https://maps.googleapis.com/maps/api/place/textsearch/json'
        '?query=${Uri.encodeComponent(query)}'
        '&key=$apiKey';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final results = json['results'] as List? ?? [];
        return results.map<Map<String, dynamic>>((r) {
          return {
            'name': r['name'] ?? '',
            'address': r['formatted_address'] ?? '',
            'lat': r['geometry']['location']['lat'],
            'lng': r['geometry']['location']['lng'],
          };
        }).toList();
      }
    } catch (e) {
      print('Place search error: $e');
    }
    return [];
  }

  /// Strips HTML tags from a string.
  String _stripHtml(String html) {
    return html.replaceAll(RegExp(r'<[^>]*>'), '');
  }

  /// Decodes Google Encoded Polyline string into LatLng points.
  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> points = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      points.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return points;
  }
}
