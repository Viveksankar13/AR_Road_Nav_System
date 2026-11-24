/// Central configuration for API keys and backend URLs.
/// Replace placeholder values with your actual keys before running.
class ApiConfig {
  // Google Maps Platform API Key
  // Get one at: https://console.cloud.google.com/apis/credentials
  // Enable: Maps SDK for Android/iOS, Directions API, Places API
  static const String googleMapsApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: 'YOUR_GOOGLE_MAPS_API_KEY',
  );

  // Backend server URL (use your machine's local IP for device testing)
  // e.g., 'http://192.168.1.100:8000' for local network
  static const String backendBaseUrl = 'http://10.0.2.2:8000'; // Android emulator localhost

  // Detection confidence threshold
  static const double detectionConfidence = 0.25;
}
