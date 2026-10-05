import 'package:intl/intl.dart';

import 'event.dart';

/// A sneak peek at what the full export's data can show (owner, 5 Oct 2026):
/// worked out on the phone from the person's own events, before the full
/// export unlocks at 100 events.
class Insight {
  final String id;
  final String title;

  /// The finding, or why there isn't one yet.
  final String text;

  /// False when there isn't enough data for this one yet.
  final bool found;

  const Insight(this.id, this.title, this.text, {this.found = true});
}

/// Insight ids in display order. The video pass shows [videoInsights]; the
/// $1 pass shows all of [passInsights].
const videoInsights = ['rhythm', 'feelings_by_person'];
const passInsights = [
  'rhythm',
  'feelings_by_person',
  'together',
  'weather_mood',
  'label_trend',
];

const insightTitles = {
  'rhythm': 'Your rhythm',
  'feelings_by_person': 'Feelings by person',
  'together': 'Who goes together',
  'weather_mood': 'Weather and your days',
  'label_trend': 'A label on the rise',
};

/// Computes the insights named in [ids] from [events]. [now] sets "recent"
/// for the label trend.
List<Insight> computeInsights(
  List<LifeEvent> events,
  List<String> ids, {
  DateTime? now,
}) => [
  for (final id in ids)
    switch (id) {
      'rhythm' => _rhythm(events),
      'feelings_by_person' => _feelingsByPerson(events),
      'together' => _together(events),
      'weather_mood' => _weatherMood(events),
      'label_trend' => _labelTrend(events, now ?? DateTime.now()),
      _ => throw ArgumentError.value(id, 'id', 'unknown insight'),
    },
];

Insight _notYet(String id, String why) =>
    Insight(id, insightTitles[id]!, why, found: false);

String _times(int n) => n == 1 ? '1 event' : '$n events';

/// The most counted key, ties broken alphabetically so results are stable.
MapEntry<String, int>? _top(Map<String, int> counts) {
  if (counts.isEmpty) return null;
  return counts.entries.reduce(
    (a, b) =>
        b.value > a.value || (b.value == a.value && b.key.compareTo(a.key) < 0)
        ? b
        : a,
  );
}

String _partOfDay(int hour) => switch (hour) {
  >= 5 && < 12 => 'in the morning',
  >= 12 && < 17 => 'in the afternoon',
  >= 17 && < 22 => 'in the evening',
  _ => 'at night',
};

Insight _rhythm(List<LifeEvent> events) {
  const id = 'rhythm';
  if (events.length < 5) {
    return _notYet(id, 'Record 5 events to see when your life happens most.');
  }
  final days = <String, int>{};
  final parts = <String, int>{};
  for (final e in events) {
    final day = DateFormat.EEEE().format(e.occurredAt);
    days[day] = (days[day] ?? 0) + 1;
    final part = _partOfDay(e.occurredAt.hour);
    parts[part] = (parts[part] ?? 0) + 1;
  }
  final day = _top(days)!;
  final part = _top(parts)!;
  final share = (day.value * 100 / events.length).round();
  return Insight(
    id,
    insightTitles[id]!,
    '${day.key}s hold $share% of your events, and most of your moments '
    'happen ${part.key}.',
  );
}

/// The people and places of an event, trimmed and without blanks.
Iterable<String> _who(LifeEvent e) => {
  ...e.people.map((x) => x.trim()),
  ...e.places.map((x) => x.trim()),
}.where((x) => x.isNotEmpty);

Insight _feelingsByPerson(List<LifeEvent> events) {
  const id = 'feelings_by_person';
  final pairs = <String, int>{};
  for (final e in events) {
    for (final who in _who(e)) {
      for (final label in e.confirmedLabels) {
        final key = '$who\u0000${label.trim()}';
        pairs[key] = (pairs[key] ?? 0) + 1;
      }
    }
  }
  final best = _top(pairs);
  if (best == null || best.value < 2) {
    return _notYet(
      id,
      'Confirm the labels on a few free writes ("Fits") to see which '
      'feelings go with which people and places.',
    );
  }
  final [who, label] = best.key.split('\u0000');
  return Insight(
    id,
    insightTitles[id]!,
    'Events with $who most often carry the label "$label" '
    '(${_times(best.value)}).',
  );
}

Insight _together(List<LifeEvent> events) {
  const id = 'together';
  final pairs = <String, int>{};
  for (final e in events) {
    final names = _who(e).toList()..sort();
    for (var i = 0; i < names.length; i++) {
      for (var j = i + 1; j < names.length; j++) {
        final key = '${names[i]}\u0000${names[j]}';
        pairs[key] = (pairs[key] ?? 0) + 1;
      }
    }
  }
  final best = _top(pairs);
  if (best == null || best.value < 2) {
    return _notYet(
      id,
      'Once the same people and places turn up together twice, they show '
      'here.',
    );
  }
  final [a, b] = best.key.split('\u0000');
  return Insight(
    id,
    insightTitles[id]!,
    '$a and $b appear together in ${_times(best.value)}, more than any other '
    'pair.',
  );
}

/// WMO weather codes 0 and 1: clear or mainly clear.
bool _clear(int code) => code <= 1;

Insight _weatherMood(List<LifeEvent> events) {
  const id = 'weather_mood';
  final withWeather = events.where((e) => e.weather != null).toList();
  if (withWeather.length < 3) {
    return _notYet(
      id,
      'Look up the weather on 3 events to see how it lines up with your days.',
    );
  }
  final clear = withWeather.where((e) => _clear(e.weather!.weatherCode));
  final share = (clear.length * 100 / withWeather.length).round();
  final temps = withWeather.map((e) => e.weather!.temperatureC).toList()
    ..sort();
  final median = temps[temps.length ~/ 2].round();
  return Insight(
    id,
    insightTitles[id]!,
    '$share% of your events with weather were on clear days, and your '
    'typical event happens around $median°C.',
  );
}

Insight _labelTrend(List<LifeEvent> events, DateTime now) {
  const id = 'label_trend';
  final recentStart = DateTime(now.year, now.month - 3, now.day);
  final earlierStart = DateTime(now.year, now.month - 6, now.day);
  final recent = <String, int>{};
  final earlier = <String, int>{};
  for (final e in events) {
    final bucket = !e.occurredAt.isBefore(recentStart)
        ? recent
        : !e.occurredAt.isBefore(earlierStart)
        ? earlier
        : null;
    if (bucket == null) continue;
    for (final label in e.confirmedLabels) {
      final key = label.trim();
      if (key.isNotEmpty) bucket[key] = (bucket[key] ?? 0) + 1;
    }
  }
  final rises = {
    for (final entry in recent.entries)
      entry.key: entry.value - (earlier[entry.key] ?? 0),
  }..removeWhere((_, rise) => rise < 2);
  final best = _top(rises);
  if (best == null) {
    return _notYet(
      id,
      'Keep confirming labels for a few months to see which ones grow.',
    );
  }
  return Insight(
    id,
    insightTitles[id]!,
    '"${best.key}" was on ${_times(recent[best.key]!)} in the last 3 months, '
    'up from ${earlier[best.key] ?? 0} in the 3 before.',
  );
}
