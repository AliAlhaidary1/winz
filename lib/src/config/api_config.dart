/// Central configuration for the Laravel API client.
class ApiConfig {
  /// Base URL of the Laravel API.
  ///
  /// After deployment, change this ONE line to the server URL, e.g.
  /// `http://192.168.1.10:8100/api`. For the Android emulator use
  /// `http://10.0.2.2:8100/api`. The app appends `/call` to it.
  static const String baseUrl = 'http://127.0.0.1:8100/api';
}
