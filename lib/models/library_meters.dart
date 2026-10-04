import 'package:intl/intl.dart';

import '../ai/graph_builder.dart';
import 'event.dart';
import 'memory_graph.dart';
import 'memory_item.dart';

/// One measure on the Your data dashboard.
class Meter {
  final String id;
  final String label;
  final String value;

  /// Optional second line ("in 12 events", "Jun 2025").
  final String? detail;

  const Meter(this.id, this.label, this.value, [this.detail]);
}

/// Every meter the dashboard can show, in display order. People can hide
/// any of them and bring them back later; all are free.
const meterIds = <String>[
  'events',
  'photos',
  'described',
  'people',
  'places',
  'tags',
  'memories',
  'span',
  'busiest_month',
  'top_person',
  'top_place',
  'photos_per_event',
  'words_ai',
  'words_mine',
  'graph',
  'chapters',
  'books',
  'rings',
  'weather',
  'free_writes',
  'top_label',
];

String? _top(Iterable<String> items) {
  final counts = <String, int>{};
  for (final item in items) {
    final key = item.trim();
    if (key.isNotEmpty) counts[key] = (counts[key] ?? 0) + 1;
  }
  if (counts.isEmpty) return null;
  final best = counts.entries.reduce(
    (a, b) => b.value > a.value || (b.value == a.value && b.key.compareTo(a.key) < 0) ? b : a,
  );
  return '${best.key}\u0000${best.value}';
}

int _words(String text) =>
    text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;

/// Computes every meter for a library.
List<Meter> computeMeters({
  required List<LifeEvent> events,
  required List<MemoryItem> memories,
  GraphSnapshot? graph,
}) {
  final number = NumberFormat.decimalPattern();
  String n(int v) => number.format(v);
  String times(int v) => v == 1 ? 'in 1 event' : 'in ${n(v)} events';

  final photos = events.fold<int>(0, (sum, e) => sum + e.images.length);
  final described = events.where((e) => e.hasAccount).length;
  final people = {for (final e in events) ...e.people.map((x) => x.trim())}
    ..remove('');
  final places = {for (final e in events) ...e.places.map((x) => x.trim())}
    ..remove('');
  final tags = {for (final e in events) ...e.tags.map((x) => x.trim())}
    ..remove('');

  final dates = events.map((e) => e.occurredAt).toList()..sort();
  final month = DateFormat.yMMM();
  final day = DateFormat.yMMMd();

  final busiest = _top(events.map((e) => month.format(e.occurredAt)));
  final topPerson = _top(events.expand((e) => e.people));
  final topPlace = _top(events.expand((e) => e.places));
  final topLabel = _top(events.expand((e) => e.experienceLabels));
  (String, String?) split(String? top, String empty) {
    if (top == null) return (empty, null);
    final parts = top.split('\u0000');
    return (parts[0], times(int.parse(parts[1])));
  }

  final (busiestValue, busiestDetail) = split(busiest, 'None yet');
  final (personValue, personDetail) = split(topPerson, 'None yet');
  final (placeValue, placeDetail) = split(topPlace, 'None yet');
  final (labelValue, labelDetail) = split(topLabel, 'None yet');

  final describedPhotos = describedPhotoCount(events);
  final graphValue = graph != null
      ? 'Unlocked'
      : '${n(describedPhotos)} of $graphUnlockPhotos photos';

  return [
    Meter('events', 'Events', n(events.length)),
    Meter('photos', 'Photos', n(photos)),
    Meter(
      'described',
      'Accounts written by AI',
      n(described),
      events.isEmpty ? null : '${(described * 100 / events.length).round()}% of events',
    ),
    Meter('people', 'People', n(people.length)),
    Meter('places', 'Places', n(places.length)),
    Meter('tags', 'Tags', n(tags.length)),
    Meter('memories', 'Saved memories', n(memories.length)),
    Meter(
      'span',
      'Time covered',
      dates.isEmpty ? 'None yet' : _span(dates.first, dates.last),
      dates.isEmpty ? null : '${day.format(dates.first)} to ${day.format(dates.last)}',
    ),
    Meter('busiest_month', 'Busiest month', busiestValue, busiestDetail),
    Meter('top_person', 'Most recorded person', personValue, personDetail),
    Meter('top_place', 'Most recorded place', placeValue, placeDetail),
    Meter(
      'photos_per_event',
      'Photos per event',
      events.isEmpty ? '0' : (photos / events.length).toStringAsFixed(1),
    ),
    Meter(
      'words_ai',
      'Words written by AI',
      n(events.fold<int>(0, (s, e) => s + _words(e.description))),
    ),
    Meter(
      'words_mine',
      'Words in your AI Notes',
      n(events.fold<int>(0, (s, e) => s + _words(e.notes))),
    ),
    Meter('graph', 'Timeline graph', graphValue),
    Meter('chapters', 'Chapters', n(graph?.chapters.length ?? 0)),
    Meter('books', 'Books', n(graph?.books.length ?? 0)),
    Meter('rings', 'Events with rings', n(graph?.rings.length ?? 0)),
    Meter(
      'weather',
      'Events with weather',
      n(events.where((e) => e.weather != null).length),
    ),
    Meter(
      'free_writes',
      'Events with a free write',
      n(events.where((e) => e.experience.trim().isNotEmpty).length),
    ),
    Meter('top_label', 'Most common free-write label', labelValue, labelDetail),
  ];
}

String _span(DateTime first, DateTime last) {
  final days = last.difference(first).inDays;
  if (days < 1) return '1 day';
  if (days < 60) return '${days + 1} days';
  final months = (last.year - first.year) * 12 + last.month - first.month;
  if (months < 24) return '$months months';
  return '${(months / 12).floor()} years';
}
