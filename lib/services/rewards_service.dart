import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/ring_palette.dart';

/// Shows one rewarded video. Kept behind an interface so the ad provider
/// can change later without touching the unlock logic.
abstract class RewardedVideoProvider {
  /// Resolves to true only when the user watched the video to the reward.
  Future<bool> showRewardedVideo();
}

/// Google AdMob rewarded videos.
///
/// Uses Google's public test ad unit unless a real one is passed at build
/// time with `--dart-define=ADMOB_REWARDED_ID=ca-app-pub-…`. Test ads are
/// safe to show during development and earn nothing.
class AdMobRewardedProvider implements RewardedVideoProvider {
  static const _testUnitId = 'ca-app-pub-3940256099942544/5224354917';
  static const unitId = String.fromEnvironment(
    'ADMOB_REWARDED_ID',
    defaultValue: _testUnitId,
  );

  static bool get usingTestAds => unitId == _testUnitId;

  static Future<void> initialize() async {
    await MobileAds.instance.initialize();
  }

  @override
  Future<bool> showRewardedVideo() async {
    final loaded = Completer<RewardedAd?>();
    await RewardedAd.load(
      adUnitId: unitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: loaded.complete,
        onAdFailedToLoad: (error) {
          debugPrint('Rewarded ad failed to load: $error');
          loaded.complete(null);
        },
      ),
    );
    final ad = await loaded.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () => null,
    );
    if (ad == null) return false;

    final done = Completer<bool>();
    var earned = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!done.isCompleted) done.complete(earned);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        if (!done.isCompleted) done.complete(false);
      },
    );
    await ad.show(onUserEarnedReward: (_, _) => earned = true);
    return done.future;
  }
}

/// Which ring colours the user has unlocked, and progress towards the next.
///
/// Colours unlock in palette order. Index 0 is free; the next one needs
/// [ringUnlockCost] watched videos (5, then 6, 7, …). Progress is stored on
/// this device.
class RingUnlocks extends ChangeNotifier {
  final SharedPreferences _prefs;
  final RewardedVideoProvider provider;
  final String _scope;
  bool _watching = false;

  /// [scope] keeps each account's unlocks separate on a shared phone.
  RingUnlocks(this._prefs, this.provider, {String scope = ''})
    : _scope = scope.isEmpty ? '' : '_$scope';

  String get _unlockedKey => 'ring_unlocked_count$_scope';
  String get _progressKey => 'ring_unlock_progress$_scope';

  int get unlockedCount => (_prefs.getInt(_unlockedKey) ?? freeRingColors)
      .clamp(freeRingColors, ringPalette.length);

  /// Videos watched towards [nextLocked].
  int get progress => _prefs.getInt(_progressKey) ?? 0;

  bool get watching => _watching;

  bool isUnlocked(int index) => index >= 0 && index < unlockedCount;

  /// Palette index that unlocks next, or null when all are unlocked.
  int? get nextLocked =>
      unlockedCount < ringPalette.length ? unlockedCount : null;

  int? get videosForNext {
    final next = nextLocked;
    return next == null ? null : ringUnlockCost(next) - progress;
  }

  /// Plays one rewarded video. Returns true if it counted; unlocks the next
  /// colour once enough have been watched.
  Future<bool> watchVideo() async {
    final next = nextLocked;
    if (next == null || _watching) return false;
    _watching = true;
    notifyListeners();
    try {
      final earned = await provider.showRewardedVideo();
      if (!earned) return false;
      final watched = progress + 1;
      if (watched >= ringUnlockCost(next)) {
        await _prefs.setInt(_unlockedKey, next + 1);
        await _prefs.setInt(_progressKey, 0);
      } else {
        await _prefs.setInt(_progressKey, watched);
      }
      return true;
    } finally {
      _watching = false;
      notifyListeners();
    }
  }
}

/// Hour of day (local time) when daily features refresh.
const dailyRefreshHour = 12;

/// Rewarded videos that unlock weather lookups for one day.
const weatherVideosPerDay = 3;

/// Start of the daily window that contains [now]: the most recent 12:00
/// noon at or before it.
DateTime dailyWindowStart(DateTime now) {
  final todayNoon = DateTime(now.year, now.month, now.day, dailyRefreshHour);
  return now.isBefore(todayNoon)
      ? todayNoon.subtract(const Duration(days: 1))
      : todayNoon;
}

/// The optional weather lookup, unlocked for the current day by watching
/// [weatherVideosPerDay] rewarded videos. Progress and the unlock reset at
/// [dailyRefreshHour] (12:00 noon) every day.
class WeatherPass extends ChangeNotifier {
  final SharedPreferences _prefs;
  final RewardedVideoProvider provider;
  final String _scope;
  final DateTime Function() _now;
  bool _watching = false;

  WeatherPass(
    this._prefs,
    this.provider, {
    String scope = '',
    DateTime Function()? now,
  }) : _scope = scope.isEmpty ? '' : '_$scope',
       _now = now ?? DateTime.now;

  String get _windowKey => 'weather_pass_window$_scope';
  String get _progressKey => 'weather_pass_progress$_scope';

  int get _currentWindow => dailyWindowStart(_now()).millisecondsSinceEpoch;

  /// Videos watched in the current daily window.
  int get progress =>
      _prefs.getInt(_windowKey) == _currentWindow
          ? (_prefs.getInt(_progressKey) ?? 0)
          : 0;

  bool get unlocked => progress >= weatherVideosPerDay;

  bool get watching => _watching;

  /// When the current unlock (or progress) resets.
  DateTime get resetsAt =>
      dailyWindowStart(_now()).add(const Duration(days: 1));

  /// Plays one rewarded video; returns true if it counted.
  Future<bool> watchVideo() async {
    if (unlocked || _watching) return false;
    _watching = true;
    notifyListeners();
    try {
      final earned = await provider.showRewardedVideo();
      if (!earned) return false;
      final window = _currentWindow;
      await _prefs.setInt(_progressKey, progress + 1);
      await _prefs.setInt(_windowKey, window);
      return true;
    } finally {
      _watching = false;
      notifyListeners();
    }
  }
}
