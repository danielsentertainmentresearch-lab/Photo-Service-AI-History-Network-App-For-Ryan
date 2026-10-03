import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ai/event_describer.dart';

/// User settings. The API key lives in the Android Keystore-backed secure
/// storage; everything else is plain preferences.
///
/// [scope] (the account) keeps each account's settings and API key separate
/// on a shared phone; empty means the unscoped, pre-account keys.
class SettingsService {
  final FlutterSecureStorage _secure;
  final SharedPreferences _prefs;
  final String _scope;

  SettingsService(this._secure, this._prefs, {String scope = ''})
    : _scope = scope.isEmpty ? '' : '_$scope';

  String get _apiKeyKey => 'anthropic_api_key$_scope';
  String get _modelKey => 'model$_scope';
  String get _effortKey => 'effort$_scope';
  String get _exportUnlockedKey => 'export_unlocked$_scope';
  String get _hiddenMetersKey => 'hidden_meters$_scope';
  String get _platformAdviceKey => 'data_platform_advice$_scope';
  static const _onboardedKey = 'onboarded';

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

  /// True once this account has reached the full-export threshold. It
  /// stays true even if events are deleted later.
  bool get exportUnlocked => _prefs.getBool(_exportUnlockedKey) ?? false;

  Future<void> setExportUnlocked() => _prefs.setBool(_exportUnlockedKey, true);

  /// Meters the person removed from the Your data dashboard.
  Set<String> get hiddenMeters =>
      (_prefs.getStringList(_hiddenMetersKey) ?? const []).toSet();

  Future<void> setHiddenMeters(Set<String> ids) =>
      _prefs.setStringList(_hiddenMetersKey, ids.toList()..sort());

  /// Cached AI answer about which Python data platforms fit the analysis
  /// file (JSON), so the AI isn't asked every time the guide opens.
  String? get platformAdvice => _prefs.getString(_platformAdviceKey);

  Future<void> setPlatformAdvice(String? json) => json == null
      ? _prefs.remove(_platformAdviceKey)
      : _prefs.setString(_platformAdviceKey, json);

  bool get onboarded => _prefs.getBool(_onboardedKey) ?? false;

  Future<void> setOnboarded() => _prefs.setBool(_onboardedKey, true);
}
