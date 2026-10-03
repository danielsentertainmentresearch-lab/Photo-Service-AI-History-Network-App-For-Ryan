import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ai/event_describer.dart';

/// User settings. The API key lives in the Android Keystore-backed secure
/// storage; everything else is plain preferences.
class SettingsService {
  static const _apiKeyKey = 'anthropic_api_key';
  static const _modelKey = 'model';
  static const _effortKey = 'effort';
  static const _onboardedKey = 'onboarded';
  static const _graphEveryKey = 'graph_every_photos';

  /// Choices for how many newly described photos trigger an automatic
  /// rebuild of the timeline graph. 0 turns it off.
  static const graphEveryOptions = [0, 5, 10, 20, 50];
  static const defaultGraphEvery = 10;

  final FlutterSecureStorage _secure;
  final SharedPreferences _prefs;

  SettingsService(this._secure, this._prefs);

  static Future<SettingsService> create() async => SettingsService(
    const FlutterSecureStorage(),
    await SharedPreferences.getInstance(),
  );

  Future<String?> readApiKey() => _secure.read(key: _apiKeyKey);

  Future<void> writeApiKey(String? key) => key == null || key.trim().isEmpty
      ? _secure.delete(key: _apiKeyKey)
      : _secure.write(key: _apiKeyKey, value: key.trim());

  String get model {
    final stored = _prefs.getString(_modelKey);
    return supportedModels.containsKey(stored) ? stored! : defaultModel;
  }

  Future<void> setModel(String value) => _prefs.setString(_modelKey, value);

  String get effort {
    final stored = _prefs.getString(_effortKey);
    return supportedEfforts.contains(stored) ? stored! : defaultEffort;
  }

  Future<void> setEffort(String value) => _prefs.setString(_effortKey, value);

  int get graphEvery {
    final stored = _prefs.getInt(_graphEveryKey);
    return graphEveryOptions.contains(stored) ? stored! : defaultGraphEvery;
  }

  Future<void> setGraphEvery(int value) => _prefs.setInt(_graphEveryKey, value);

  bool get onboarded => _prefs.getBool(_onboardedKey) ?? false;

  Future<void> setOnboarded() => _prefs.setBool(_onboardedKey, true);
}
