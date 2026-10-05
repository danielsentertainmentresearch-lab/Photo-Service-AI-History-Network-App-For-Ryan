import 'dart:math';

import 'event.dart';
import 'memory_graph.dart';
import 'memory_item.dart';
import 'name_state.dart';

/// What the "What the AI is learning" page shows (owner, 5 Oct 2026): the
/// AI's own findings, read-only, a few at a time. The selection rotates at
/// unplanned times during the day, so the page keeps showing something new
/// even when the app isn't used. Everything shown is real: connections and
/// threads the AI wrote into the timeline graph, and what it remembers.
class LearningView {
  final int people;
  final int places;
  final int facts;

  /// "“Sunset swim” and “Night swim”: same lake".
  final List<String> connections;

  /// Recurring threads: name, description and how many events.
  final List<StoryTheme> threads;

  /// A few things the AI remembers.
  final List<String> remembers;

  /// The people and places the person honors, each with how many moments
  /// they share and one moment that rotates.
  final List<Remembering> remembering;

  /// When the selection changes next.
  final DateTime nextChange;

  const LearningView({
    required this.people,
    required this.places,
    required this.facts,
    required this.connections,
    required this.threads,
    required this.remembers,
    this.remembering = const [],
    required this.nextChange,
  });

  bool get isEmpty =>
      people + places + facts == 0 &&
      connections.isEmpty &&
      threads.isEmpty &&
      remembers.isEmpty &&
      remembering.isEmpty;
}

/// Someone (or somewhere) the person honors, on the learning page.
class Remembering {
  final String name;
  final int moments;

  /// One shared moment ("Sunset swim, June 2026"), rotating; null when none.
  final String? moment;

  const Remembering(this.name, this.moments, this.moment);
}

/// How many of each the page shows at once.
const shownConnections = 3;
const shownThreads = 2;
const shownRemembers = 3;

/// The day's three change times: random hours, the same all day so the
/// page holds still between them.
List<int> _changeHours(DateTime day) {
  final random = Random(day.year * 10000 + day.month * 100 + day.day);
  final hours = <int>{};
  while (hours.length < 3) {
    hours.add(random.nextInt(24));
  }
  return hours.toList()..sort();
}

/// Which selection is showing at [now] (the seed), and when it changes.
({int seed, DateTime next}) learningRotation(DateTime now) {
  final day = DateTime(now.year, now.month, now.day);
  final hours = _changeHours(day);
  final passed = hours.where((h) => h <= now.hour).length;
  final seed = (day.year * 10000 + day.month * 100 + day.day) * 4 + passed;
  final next = passed < hours.length
      ? DateTime(day.year, day.month, day.day, hours[passed])
      : () {
          final tomorrow = DateTime(day.year, day.month, day.day + 1);
          return DateTime(
            tomorrow.year,
            tomorrow.month,
            tomorrow.day,
            _changeHours(tomorrow).first,
          );
        }();
  return (seed: seed, next: next);
}

List<T> _pick<T>(List<T> items, int count, Random random) =>
    (List<T>.of(items)..shuffle(random)).take(count).toList();

LearningView computeLearning({
  required List<LifeEvent> events,
  required List<MemoryItem> memories,
  GraphSnapshot? graph,
  required DateTime now,
  List<NameState> nameStates = const [],
}) {
  final rotation = learningRotation(now);
  // Quiet names don't come up on their own; nothing about them is deleted.
  final quiet = namesIn(nameStates, nameQuiet);
  bool features(LifeEvent e) => [
    ...e.people,
    ...e.places,
  ].any((n) => quiet.contains(n.trim().toLowerCase()));
  final quietEvents = {
    for (final e in events)
      if (features(e)) e.id,
  };
  final random = Random(rotation.seed);

  String key(String s) => s.trim().toLowerCase();
  // Names the AI identified in events, plus names the person gave when it
  // asked who or where ("Ana: a friend in a red jacket in …").
  Set<String> named(String kind, Iterable<String> fromEvents) => {
    ...fromEvents.map(key),
    for (final m in memories)
      if (m.source == answerSource && m.kind == kind)
        key(m.content.split(':').first),
  }..remove('');
  final people = named('person', [for (final e in events) ...e.people]);
  final places = named('place', [for (final e in events) ...e.places]);
  final facts = memories.where((m) => m.source != answerSource).length;

  final titles = {
    for (final e in events)
      e.id: e.title.trim().isEmpty ? 'an untitled event' : e.title.trim(),
  };
  final connections = [
    for (final link in graph?.links ?? const <EventLink>[])
      if (titles.containsKey(link.fromEventId) &&
          titles.containsKey(link.toEventId) &&
          !quietEvents.contains(link.fromEventId) &&
          !quietEvents.contains(link.toEventId) &&
          !mentionsAny(link.relation, quiet) &&
          link.relation.trim().isNotEmpty)
        '“${titles[link.fromEventId]}” and “${titles[link.toEventId]}”: '
            '${link.relation.trim()}',
  ];
  final threads = [
    for (final t in graph?.themes ?? const <StoryTheme>[])
      if (t.name.trim().isNotEmpty &&
          t.eventIds.isNotEmpty &&
          !mentionsAny('${t.name} ${t.description}', quiet))
        t,
  ];
  final remembering = [
    for (final n in nameStates.where((n) => n.state == nameHonored))
      () {
        final shared = [
          for (final e in events)
            if ([
              ...e.people,
              ...e.places,
            ].any((x) => x.trim().toLowerCase() == n.name.toLowerCase()))
              e,
        ];
        final moment = shared.isEmpty
            ? null
            : shared[random.nextInt(shared.length)];
        return Remembering(
          n.name,
          shared.length,
          moment == null
              ? null
              : '${titles[moment.id]}, '
                    '${_monthYear(moment.occurredAt)}',
        );
      }(),
  ];

  return LearningView(
    people: people.length,
    places: places.length,
    facts: facts,
    connections: _pick(connections, shownConnections, random),
    threads: _pick(threads, shownThreads, random),
    remembers: _pick(
      [
        for (final m in memories)
          if (!mentionsAny(m.content, quiet)) m.content,
      ],
      shownRemembers,
      random,
    ),
    remembering: remembering,
    nextChange: rotation.next,
  );
}

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String _monthYear(DateTime d) => '${_months[d.month - 1]} ${d.year}';
