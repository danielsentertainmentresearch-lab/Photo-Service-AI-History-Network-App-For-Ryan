import 'dart:math';

import 'event.dart';
import 'learned_point.dart';
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

  /// The dream state's foundation statements and themes: the story so far
  /// (Section 3.2). Empty before the first dream pass.
  final List<String> story;
  final List<String> themes;

  /// What the dream pass changed since the person's last visit, newest
  /// first, at most [shownChanges].
  final List<LearnedChange> changes;

  /// True once any dream pass has changed the memory, so "since your last
  /// visit" has something to report on.
  final bool hasDreamed;

  const LearningView({
    required this.people,
    required this.places,
    required this.facts,
    required this.connections,
    required this.threads,
    required this.remembers,
    this.remembering = const [],
    required this.nextChange,
    this.story = const [],
    this.themes = const [],
    this.changes = const [],
    this.hasDreamed = false,
  });

  bool get isEmpty =>
      people + places + facts == 0 &&
      connections.isEmpty &&
      threads.isEmpty &&
      remembers.isEmpty &&
      remembering.isEmpty &&
      story.isEmpty &&
      themes.isEmpty &&
      !hasDreamed;
}

/// A point the dream pass learned for the first time.
const changeNew = 'new';

/// A point the dream pass revised, or brought back from the archive.
const changeUpdated = 'updated';

/// A point archived: true, but no longer current.
const changeNoLongerCurrent = 'no longer current';

/// A point retired: no longer held true.
const changeNoLongerHeld = 'no longer held';

/// One change the dream pass made, in the AI's own words. Sentiment is
/// never part of it (owner, 12 Oct 2026).
class LearnedChange {
  final String kind;
  final String content;
  final DateTime at;

  const LearnedChange(this.kind, this.content, this.at);
}

/// How many changes "since your last visit" shows.
const shownChanges = 5;

/// The lead-in for a change line. Placeholder wording until Hermes writes
/// the page's words (docs/MEMORY_WORKFLOW.md, Section 4.3).
String changeLead(String kind) => switch (kind) {
  changeNew => 'New',
  changeUpdated => 'Updated',
  changeNoLongerCurrent => 'No longer current',
  _ => 'No longer held',
};

/// What kind of dream-pass change [p] records, or null when the dream pass
/// didn't make it (a migrated point, or an answer to the AI's question).
String? _changeKind(LearnedPoint p) {
  if (p.version == 1) {
    return p.sentiment.source == dreamSentiment ? changeNew : null;
  }
  if (p.reason.startsWith('revised:') || p.reason.startsWith('revived:')) {
    return changeUpdated;
  }
  if (p.reason.startsWith('archived:')) return changeNoLongerCurrent;
  if (p.reason.startsWith('retired:')) return changeNoLongerHeld;
  return null;
}

/// What the dream pass changed after [since], newest first, one line per
/// point (its latest change), at most [shownChanges]. With no [since] (a
/// first visit) it shows the latest pass. Points naming a Quiet name are
/// left out.
List<LearnedChange> learnedChanges(
  List<LearnedPoint> versions, {
  DateTime? since,
  Set<String> quiet = const {},
}) {
  final dreamed = [
    for (final p in versions)
      if (_changeKind(p) != null) p,
  ];
  if (dreamed.isEmpty) return const [];
  final latest = dreamed
      .map((p) => p.createdAt)
      .reduce((a, b) => a.isAfter(b) ? a : b);
  final picked = [
    for (final p in dreamed)
      if (since == null ? p.createdAt == latest : p.createdAt.isAfter(since)) p,
  ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  final seen = <String>{};
  return [
    for (final p in picked)
      if (seen.add(p.pointId) && !mentionsAny(p.content, quiet))
        LearnedChange(_changeKind(p)!, p.content, p.createdAt),
  ].take(shownChanges).toList();
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
  DreamState? dream,
  List<LearnedPoint> versions = const [],
  DateTime? lastVisit,
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
    story: [
      for (final s in dream?.foundationStatements ?? const <String>[])
        if (s.trim().isNotEmpty && !mentionsAny(s, quiet)) s.trim(),
    ],
    themes: [
      for (final t in dream?.themes ?? const <String>[])
        if (t.trim().isNotEmpty && !mentionsAny(t, quiet)) t.trim(),
    ],
    changes: learnedChanges(versions, since: lastVisit, quiet: quiet),
    hasDreamed: versions.any((p) => _changeKind(p) != null),
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
