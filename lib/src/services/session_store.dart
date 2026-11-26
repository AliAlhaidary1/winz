import 'package:shared_preferences/shared_preferences.dart';

/// Server-issued session token. Identity/role are resolved by the server from
/// this token, never from the client-sent user envelope.
class SessionStore {
  static const _key = 'winz_session_token';
  static String? _token;

  static String? get token => _token;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_key);
  }

  static Future<void> save(String? token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    if (token == null || token.isEmpty) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, token);
    }
  }

  static Map<String, String> get headers => _token == null || _token!.isEmpty
      ? const {}
      : {'X-Session-Token': _token!};
}
