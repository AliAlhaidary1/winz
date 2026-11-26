/// Central configuration for the Laravel API client.
class ApiConfig {
  /// Base URL of the Laravel API.
  ///
  /// After deployment, change this ONE line to the server URL, e.g.
  /// `http://192.168.1.10:8100/api`. For the Android emulator use
  /// `http://10.0.2.2:8100/api`. The app appends `/call` to it.
  static const String baseUrl = 'https://winz.sreamart.com/api';

  /// Shared secret sent as the X-API-Key header. Must match WINZ_API_TOKEN
  /// in the Laravel .env on the server.
  static const String apiToken = 'WinzSecure2026!';
}
