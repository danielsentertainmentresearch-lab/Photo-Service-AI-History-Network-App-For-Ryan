import 'package:eventlens/models/event.dart';
import 'package:eventlens/models/insights.dart';
import 'package:eventlens/services/insight_pass.dart';
import 'package:eventlens/services/rewards_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Videos implements RewardedVideoProvider {
  bool finish = true;
  int shown = 0;

  @override
  Future<bool> showRewardedVideo() async {
    shown++;
    return finish;
  }
}

class _Store implements InsightPurchases {
  bool pay = true;

  @override
  bool get available => true;

  @override
  Future<bool> buyInsightPass() async => pay;
}

LifeEvent _event(
  String id,
  DateTime at, {
  List<String> people = const [],
  List<String> places = const [],
  List<String> confirmed = const [],
  int? weatherCode,
  double temp = 20,
}) => LifeEvent(
  id: id,
  title: id,
  notes: '',
  location: '',
  occurredAt: at,
  createdAt: at,
  updatedAt: at,
  people: people,
  places: places,
  confirmedLabels: confirmed,
  weather: weatherCode == null
      ? null
      : EventWeather(
          temperatureC: temp,
          weatherCode: weatherCode,
          precipitationMm: 0,
          windKmh: 5,
          fetchedAt: at,
        ),
);

Insight _one(List<LifeEvent> events, String id, {DateTime? now}) =>
    computeInsights(events, [id], now: now).single;

void main() {
  group('insights', () {
    // Saturdays 4 and 11 Jul 2026, plus a Monday.
    final sat1 = DateTime(2026, 7, 4, 19);
    final sat2 = DateTime(2026, 7, 11, 20);
    final mon = DateTime(2026, 7, 6, 9);

    test('rhythm needs 5 events, then names the day and time of day', () {
      final few = [_event('a', sat1), _event('b', mon)];
      expect(_one(few, 'rhythm').found, isFalse);

      final events = [
        _event('a', sat1),
        _event('b', sat2),
        _event('c', sat1.add(const Duration(days: 14))),
        _event('d', mon),
        _event('e', sat2.add(const Duration(days: 14, hours: 1))),
      ];
      final insight = _one(events, 'rhythm');
      expect(insight.found, isTrue);
      expect(insight.text, contains('Saturdays hold 80% of your events'));
      expect(insight.text, contains('in the evening'));
    });

    test('feelings by person use only confirmed labels', () {
      final events = [
        _event('a', sat1, people: ['Sam'], confirmed: ['calm']),
        _event('b', sat2, people: ['Sam'], confirmed: ['calm', 'tired']),
        _event('c', mon, people: ['Ana'], confirmed: ['tired']),
      ];
      final insight = _one(events, 'feelings_by_person');
      expect(insight.found, isTrue);
      expect(
        insight.text,
        'Events with Sam most often carry the label "calm" (2 events).',
      );
      expect(
        _one([_event('a', sat1, people: ['Sam'])], 'feelings_by_person').found,
        isFalse,
      );
    });

    test('who goes together finds the most frequent pair', () {
      final events = [
        _event('a', sat1, people: ['Sam'], places: ['Lake']),
        _event('b', sat2, people: ['Sam', 'Ana'], places: ['Lake']),
        _event('c', mon, people: ['Ana']),
      ];
      expect(
        _one(events, 'together').text,
        'Lake and Sam appear together in 2 events, more than any other pair.',
      );
    });

    test('weather mood needs 3 events with weather', () {
      final two = [
        _event('a', sat1, weatherCode: 0),
        _event('b', sat2, weatherCode: 61),
      ];
      expect(_one(two, 'weather_mood').found, isFalse);
      final events = [
        ...two,
        _event('c', mon, weatherCode: 1, temp: 24),
        _event('d', mon, weatherCode: 0, temp: 18),
      ];
      final insight = _one(events, 'weather_mood');
      expect(insight.text, contains('75% of your events with weather'));
      expect(insight.text, contains('around 20°C'));
    });

    test('label trend compares the last 3 months with the 3 before', () {
      final now = DateTime(2026, 10, 5);
      final events = [
        for (var i = 0; i < 3; i++)
          _event('r$i', DateTime(2026, 9, 1 + i), confirmed: ['calm']),
        _event('e0', DateTime(2026, 5, 1), confirmed: ['calm']),
      ];
      expect(
        _one(events, 'label_trend', now: now).text,
        '"calm" was on 3 events in the last 3 months, up from 1 in the 3 '
        'before.',
      );
      expect(_one(events.take(1).toList(), 'label_trend', now: now).found,
          isFalse);
    });

    test('the video pass shows 2 insights, the \$1 pass all 5', () {
      expect(videoInsights, hasLength(2));
      expect(passInsights, containsAll(videoInsights));
      expect(passInsights, hasLength(5));
      expect(computeInsights(const [], passInsights), hasLength(5));
    });
  });

  group('insight pass', () {
    late SharedPreferences prefs;
    late DateTime now;
    late _Videos videos;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      now = DateTime(2026, 10, 5, 9);
      videos = _Videos();
    });

    test('3 videos open it for 12 hours, then not again for 48', () async {
      final pass = InsightPass(prefs, videos, scope: 'u1', now: () => now);
      expect(pass.tier, InsightTier.none);
      videos.finish = false;
      expect(await pass.watchVideo(), isFalse);
      expect(pass.progress, 0);
      videos.finish = true;
      await pass.watchVideo();
      await pass.watchVideo();
      expect(pass.tier, InsightTier.none);
      await pass.watchVideo();
      expect(pass.tier, InsightTier.video);
      expect(pass.videoUntil, DateTime(2026, 10, 5, 21));
      expect(pass.canWatch, isFalse);

      now = DateTime(2026, 10, 5, 21);
      expect(pass.tier, InsightTier.none);
      expect(pass.canWatch, isFalse);
      expect(pass.videoAvailableAt, DateTime(2026, 10, 7, 9));
      expect(await pass.watchVideo(), isFalse);

      now = DateTime(2026, 10, 7, 9);
      expect(pass.canWatch, isTrue);
      expect(pass.progress, 0);

      // Another account on the phone has its own pass.
      final other = InsightPass(prefs, videos, scope: 'u2', now: () => now);
      expect(other.videoAvailableAt, isNull);
    });

    test('the \$1 pass opens 72 hours; buying again adds 72 more', () async {
      final store = _Store();
      final pass = InsightPass(prefs, videos, purchases: store, now: () => now);
      store.pay = false;
      expect(await pass.buyPass(), isFalse);
      expect(pass.tier, InsightTier.none);
      store.pay = true;
      expect(await pass.buyPass(), isTrue);
      expect(pass.tier, InsightTier.pass);
      expect(pass.passUntil, DateTime(2026, 10, 8, 9));
      await pass.buyPass();
      expect(pass.passUntil, DateTime(2026, 10, 11, 9));
      now = DateTime(2026, 10, 11, 9);
      expect(pass.tier, InsightTier.none);
    });

    test('until Play Billing is connected the \$1 pass can\'t be bought',
        () async {
      final pass = InsightPass(prefs, videos, now: () => now);
      expect(pass.purchases.available, isFalse);
      expect(await pass.buyPass(), isFalse);
      expect(pass.tier, InsightTier.none);
    });
  });
}
