import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../services/directions_service.dart';
import '../services/pothole_service.dart';
import '../services/location_service.dart';
import 'ar_navigation_screen.dart';
import 'pothole_detection_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  GoogleMapController? _mapController;
  LatLng _currentLocation = const LatLng(12.9716, 77.5946); // Default Bangalore
  LatLng? _destination;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  final TextEditingController _searchController = TextEditingController();
  final DirectionsService _directionsService = DirectionsService();
  final PotholeService _potholeService = PotholeService();
  DirectionsResult? _directionsResult;
  bool _isLoading = false;

  List<Map<String, dynamic>> _searchResults = [];
  List<PotholeReport> _nearbyPotholes = [];
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _initLocation();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initLocation() async {
    try {
      final position = await LocationService.getCurrentPosition();
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
        _markers.add(Marker(
          markerId: const MarkerId('current'),
          position: _currentLocation,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan),
          infoWindow: const InfoWindow(title: 'You are here'),
        ));
      });
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: _currentLocation, zoom: 15),
        ),
      );
      _fetchNearbyPotholes();
    } catch (e) {
      debugPrint('Location error: $e');
    }
  }

  Future<void> _fetchNearbyPotholes() async {
    final potholes = await _potholeService.getNearbyPotholes(
      _currentLocation.latitude,
      _currentLocation.longitude,
    );
    setState(() {
      _nearbyPotholes = potholes;
      // Add pothole markers
      for (int i = 0; i < potholes.length; i++) {
        _markers.add(Marker(
          markerId: MarkerId('pothole_$i'),
          position: LatLng(potholes[i].latitude, potholes[i].longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(
            title: '⚠️ Pothole',
            snippet: 'Severity: ${potholes[i].severity}',
          ),
        ));
      }
    });
  }

  Future<void> _searchPlaces(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
      });
      return;
    }

    final results = await _directionsService.searchPlaces(query);
    setState(() {
      _searchResults = results;
    });
  }

  Future<void> _selectDestination(double lat, double lng, String name) async {
    setState(() {
      _destination = LatLng(lat, lng);
      _searchResults = [];
      _searchController.text = name;
      _isLoading = true;
      // Clear old destination marker and route
      _markers.removeWhere((m) => m.markerId.value == 'destination');
      _polylines.clear();
    });

    // Add destination marker
    _markers.add(Marker(
      markerId: const MarkerId('destination'),
      position: _destination!,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
      infoWindow: InfoWindow(title: name),
    ));

    // Get directions
    final result = await _directionsService.getDirections(
      _currentLocation,
      _destination!,
    );

    setState(() {
      _isLoading = false;
      _directionsResult = result;
      if (result != null) {
        _polylines.add(Polyline(
          polylineId: const PolylineId('route'),
          points: result.polylinePoints,
          color: const Color(0xFF00D4FF),
          width: 5,
          patterns: [PatternItem.dot, PatternItem.gap(10)],
        ));
      }
    });

    // Zoom to show both origin and destination
    if (_destination != null) {
      _mapController?.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(
              min(_currentLocation.latitude, _destination!.latitude),
              min(_currentLocation.longitude, _destination!.longitude),
            ),
            northeast: LatLng(
              max(_currentLocation.latitude, _destination!.latitude),
              max(_currentLocation.longitude, _destination!.longitude),
            ),
          ),
          80,
        ),
      );
    }
  }

  void _startARNavigation() {
    if (_directionsResult == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ARNavigationScreen(
          directionsResult: _directionsResult!,
          destination: _destination!,
        ),
      ),
    );
  }

  void _openPotholeDetection() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const PotholeDetectionScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // Google Map
          GoogleMap(
            onMapCreated: (controller) {
              _mapController = controller;
              controller.setMapStyle(_mapStyle);
            },
            initialCameraPosition: CameraPosition(
              target: _currentLocation,
              zoom: 14,
            ),
            markers: _markers,
            polylines: _polylines,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            onTap: (latLng) {
              _selectDestination(
                latLng.latitude,
                latLng.longitude,
                '${latLng.latitude.toStringAsFixed(4)}, ${latLng.longitude.toStringAsFixed(4)}',
              );
            },
          ),

          // Top gradient overlay
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 160,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF0A0E21).withOpacity(0.95),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Search bar
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            right: 16,
            child: Column(
              children: [
                // Title
                const Text(
                  'AR ROAD NAVIGATOR',
                  style: TextStyle(
                    color: Color(0xFF00D4FF),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 10),
                // Search field
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00D4FF).withOpacity(0.15),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    decoration: InputDecoration(
                      hintText: 'Search destination...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, color: Colors.white54),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchResults = []);
                              },
                            )
                          : null,
                    ),
                    onChanged: (value) {
                      if (value.length > 2) {
                        _searchPlaces(value);
                      }
                    },
                    onSubmitted: _searchPlaces,
                  ),
                ),
                // Search results dropdown
                if (_searchResults.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1F38).withOpacity(0.95),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.4),
                          blurRadius: 16,
                        ),
                      ],
                    ),
                    constraints: const BoxConstraints(maxHeight: 250),
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: _searchResults.length,
                      itemBuilder: (context, index) {
                        final place = _searchResults[index];
                        return ListTile(
                          leading: const Icon(Icons.place, color: Color(0xFF7C4DFF)),
                          title: Text(
                            place['name'],
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            place['address'],
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _selectDestination(
                            place['lat'],
                            place['lng'],
                            place['name'],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),

          // Loading indicator
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(color: Color(0xFF00D4FF)),
            ),

          // Bottom panel - Route info & controls
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    const Color(0xFF0A0E21).withOpacity(0.98),
                    const Color(0xFF0A0E21).withOpacity(0.85),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.7, 1.0],
                ),
              ),
              padding: const EdgeInsets.fromLTRB(20, 40, 20, 30),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Pothole alert chip
                  if (_nearbyPotholes.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF5252).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFFFF5252).withOpacity(0.5),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.warning_amber_rounded,
                              color: Color(0xFFFF5252), size: 18),
                          const SizedBox(width: 8),
                          Text(
                            '${_nearbyPotholes.length} potholes reported nearby',
                            style: const TextStyle(
                              color: Color(0xFFFF5252),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Route info
                  if (_directionsResult != null) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _infoChip(Icons.straighten,
                            _directionsResult!.totalDistance),
                        const SizedBox(width: 16),
                        _infoChip(Icons.access_time,
                            _directionsResult!.totalDuration),
                        const SizedBox(width: 16),
                        _infoChip(Icons.navigation,
                            '${_directionsResult!.steps.length} steps'),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Action buttons
                  Row(
                    children: [
                      // Pothole scanner button
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _openPotholeDetection,
                          icon: const Icon(Icons.camera_alt),
                          label: const Text('SCAN'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFFF5252),
                            side: const BorderSide(
                              color: Color(0xFFFF5252),
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
                      // AR Navigate button
                      Expanded(
                        flex: 2,
                        child: AnimatedBuilder(
                          animation: _pulseController,
                          builder: (context, child) {
                            return Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(30),
                                boxShadow: _directionsResult != null
                                    ? [
                                        BoxShadow(
                                          color: const Color(0xFF00D4FF)
                                              .withOpacity(
                                                  0.3 * _pulseController.value),
                                          blurRadius: 20,
                                          spreadRadius: 2,
                                        ),
                                      ]
                                    : null,
                              ),
                              child: ElevatedButton.icon(
                                onPressed: _directionsResult != null
                                    ? _startARNavigation
                                    : null,
                                icon: const Icon(Icons.navigation),
                                label: const Text('AR NAVIGATE'),
                              ),
                            );
                          },
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

  Widget _infoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F38).withOpacity(0.8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF00D4FF).withOpacity(0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFF00D4FF), size: 16),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // Dark map style
  static const String _mapStyle = '''[
    {"elementType":"geometry","stylers":[{"color":"#1d2c4d"}]},
    {"elementType":"labels.text.fill","stylers":[{"color":"#8ec3b9"}]},
    {"elementType":"labels.text.stroke","stylers":[{"color":"#1a3646"}]},
    {"featureType":"administrative.country","elementType":"geometry.stroke","stylers":[{"color":"#4b6878"}]},
    {"featureType":"land_parcel","elementType":"labels.text.fill","stylers":[{"color":"#64779e"}]},
    {"featureType":"poi","elementType":"geometry","stylers":[{"color":"#283d6a"}]},
    {"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#6f9ba5"}]},
    {"featureType":"poi.park","elementType":"geometry.fill","stylers":[{"color":"#023e58"}]},
    {"featureType":"road","elementType":"geometry","stylers":[{"color":"#304a7d"}]},
    {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#98a5be"}]},
    {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#2c6675"}]},
    {"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#255763"}]},
    {"featureType":"transit","elementType":"labels.text.fill","stylers":[{"color":"#98a5be"}]},
    {"featureType":"water","elementType":"geometry","stylers":[{"color":"#0e1626"}]},
    {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#4e6d70"}]}
  ]''';
}
