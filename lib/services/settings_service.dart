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
  String get _dreamedKey => 'dream_read_events$_scope';
  String get _dreamDayKey => 'dream_last_day$_scope';
  String get _dreamWaitKey => 'dream_wait_until$_scope';
  String get _dreamRetryKey => 'dream_retry_after$_scope';
  String get _dreamMilestoneKey => 'dream_milestone$_scope';
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

  // ---- Dream pass bookkeeping (lib/state/dream_coordinator.dart) ----------

  /// Events a dream pass has already read.
  Set<String> get dreamedEvents =>
      (_prefs.getStringList(_dreamedKey) ?? const []).toSet();

  Future<void> setDreamedEvents(Set<String> ids) =>
      _prefs.setStringList(_dreamedKey, ids.toList()..sort());

  /// The local day (YYYY-MM-DD) of the last finished pass.
  String? get lastDreamDay => _prefs.getString(_dreamDayKey);

  Future<void> setLastDreamDay(String day) =>
      _prefs.setString(_dreamDayKey, day);

  DateTime? _time(String key) => switch (_prefs.getInt(key)) {
    final ms? => DateTime.fromMillisecondsSinceEpoch(ms),
    null => null,
  };

  Future<void> _setTime(String key, DateTime? at) => at == null
      ? _prefs.remove(key)
      : _prefs.setInt(key, at.millisecondsSinceEpoch);

  /// A pass due while the allowance is used up waits until this time.
  DateTime? get dreamWaitUntil => _time(_dreamWaitKey);

  Future<void> setDreamWaitUntil(DateTime? at) => _setTime(_dreamWaitKey, at);

  /// After a failed pass, the next try waits until this time.
  DateTime? get dreamRetryAfter => _time(_dreamRetryKey);

  Future<void> setDreamRetryAfter(DateTime? at) => _setTime(_dreamRetryKey, at);

  /// A milestone (the timeline graph unlocking, an account fully set up)
  /// asked for a pass that hasn't run yet.
  bool get dreamMilestone => _prefs.getBool(_dreamMilestoneKey) ?? false;

  Future<void> setDreamMilestone(bool due) => due
      ? _prefs.setBool(_dreamMilestoneKey, true)
      : _prefs.remove(_dreamMilestoneKey);

  bool get onboarded => _prefs.getBool(_onboardedKey) ?? false;

  Future<void> setOnboarded() => _prefs.setBool(_onboardedKey, true);
}
