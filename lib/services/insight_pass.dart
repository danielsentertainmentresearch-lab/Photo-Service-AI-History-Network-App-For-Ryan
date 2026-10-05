import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'rewards_service.dart';

/// Videos that open the insight sneak peek.
const insightVideos = 3;

/// How long the video sneak peek stays open.
const insightVideoHours = 12;

/// The video sneak peek can be opened once in this many hours.
const insightVideoCooldownHours = 48;

/// How long the $1 pass stays open; buying again adds this much.
const insightPassHours = 72;

/// Price shown for the $1 pass until the store supplies its own.
const insightPassPrice = r'$1';

/// Buys the $1 insight pass. Kept behind an interface so Google Play
/// Billing (the paywall stage, docs/LAUNCH_CHECKLIST.md) plugs in later.
abstract class InsightPurchases {
  /// False while purchases aren't connected in this build.
  bool get available;

  /// Resolves to true only when the purchase went through.
  Future<bool> buyInsightPass();
}

/// Purchases before Play Billing is connected: the $1 pass is built in but
/// can't be bought yet.
class PurchasesNotConnected implements InsightPurchases {
  const PurchasesNotConnected();

  @override
  bool get available => false;

  @override
  Future<bool> buyInsightPass() async => false;
}

/// Which sneak peek is open now.
enum InsightTier { none, video, pass }

/// The insight sneak peek before the full export unlocks (owner,
/// 5 Oct 2026): [insightVideos] rewarded videos open the video peek for
/// [insightVideoHours] hours, at most once every [insightVideoCooldownHours]
/// hours; the $1 pass opens every insight for [insightPassHours] hours.
/// Kept per account on this device, like the weather pass.
class InsightPass extends ChangeNotifier {
  final SharedPreferences _prefs;
  final RewardedVideoProvider videos;
  final InsightPurchases purchases;
  final String _scope;
  final DateTime Function() _now;
  bool _busy = false;

  InsightPass(
    this._prefs,
    this.videos, {
    this.purchases = const PurchasesNotConnected(),
    String scope = '',
    DateTime Function()? now,
  }) : _scope = scope.isEmpty ? '' : '_$scope',
       _now = now ?? DateTime.now;

  String get _progressKey => 'insight_video_progress$_scope';
  String get _videoOpenedKey => 'insight_video_opened$_scope';
  String get _passUntilKey => 'insight_pass_until$_scope';

  DateTime? _time(String key) {
    final ms = _prefs.getInt(key);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  DateTime? get _videoOpened => _time(_videoOpenedKey);

  /// When the open video peek closes (null when none is open).
  DateTime? get videoUntil {
    final opened = _videoOpened;
    if (opened == null) return null;
    final until = opened.add(const Duration(hours: insightVideoHours));
    return _now().isBefore(until) ? until : null;
  }

  /// When the $1 pass closes (null when none is open).
  DateTime? get passUntil {
    final until = _time(_passUntilKey);
    return until != null && _now().isBefore(until) ? until : null;
  }

  InsightTier get tier => passUntil != null
      ? InsightTier.pass
      : videoUntil != null
      ? InsightTier.video
      : InsightTier.none;

  /// When the video peek can be opened again (null when it can be now).
  DateTime? get videoAvailableAt {
    final opened = _videoOpened;
    if (opened == null) return null;
    final next = opened.add(const Duration(hours: insightVideoCooldownHours));
    return _now().isBefore(next) ? next : null;
  }

  /// Videos watched towards the next video peek.
  int get progress => _prefs.getInt(_progressKey) ?? 0;

  bool get busy => _busy;

  bool get canWatch =>
      !_busy && tier == InsightTier.none && videoAvailableAt == null;

  /// Plays one rewarded video. Returns true if it counted; the
  /// [insightVideos]th opens the video peek.
  Future<bool> watchVideo() async {
    if (!canWatch) return false;
    _busy = true;
    notifyListeners();
    try {
      final earned = await videos.showRewardedVideo();
      if (!earned) return false;
      final watched = progress + 1;
      if (watched >= insightVideos) {
        await _prefs.setInt(_videoOpenedKey, _now().millisecondsSinceEpoch);
        await _prefs.setInt(_progressKey, 0);
      } else {
        await _prefs.setInt(_progressKey, watched);
      }
      return true;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Buys the $1 pass. Buying while one is open adds [insightPassHours] to
  /// it. Returns true if the purchase went through.
  Future<bool> buyPass() async {
    if (_busy || !purchases.available) return false;
    _busy = true;
    notifyListeners();
    try {
      if (!await purchases.buyInsightPass()) return false;
      final from = passUntil ?? _now();
      await _prefs.setInt(
        _passUntilKey,
        from.add(const Duration(hours: insightPassHours)).millisecondsSinceEpoch,
      );
      return true;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
