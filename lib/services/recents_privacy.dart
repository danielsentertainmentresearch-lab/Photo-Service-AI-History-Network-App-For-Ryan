import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Hides the app's content in the recent-apps switcher, so photos aren't
/// visible when the phone is handed to someone. On Android this also blocks
/// screenshots of the app, so it's a setting (on by default).
class RecentsPrivacy extends ChangeNotifier {
  static const _key = 'hide_in_recents';
  static const _channel = MethodChannel('eventlens/privacy');

  final SharedPreferences _prefs;

  RecentsPrivacy(this._prefs);

  bool get enabled => _prefs.getBool(_key) ?? true;

  /// Applies the current setting to the app window.
  Future<void> apply() async {
    try {
      await _channel.invokeMethod('setSecure', {'on': enabled});
    } catch (_) {
      // Not available (tests, other platforms): nothing to hide.
    }
  }

  Future<void> setEnabled(bool on) async {
    await _prefs.setBool(_key, on);
    await apply();
    notifyListeners();
  }
}
