import 'package:shared_preferences/shared_preferences.dart';

/// 4-digit PIN that protects leaving a kids profile. Synced with the cloud
/// settings so every device asks for the same PIN.
class KidsPinService {
  static const key = 'kids_pin';

  static Future<String?> get() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(key);
    return v != null && RegExp(r'^\d{4}$').hasMatch(v) ? v : null;
  }

  static Future<void> set(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, pin);
  }
}
