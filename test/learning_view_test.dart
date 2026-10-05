import 'package:eventlens/models/event.dart';
import 'package:eventlens/models/learning_view.dart';
import 'package:eventlens/models/memory_graph.dart';
import 'package:eventlens/models/memory_item.dart';
import 'package:flutter_test/flutter_test.dart';

LifeEvent _event(String id, String title, {List<String> people = const []}) {
  final at = DateTime(2026, 7, 4);
  return LifeEvent(
    id: id,
    title: title,
    notes: '',
    location: '',
    occurredAt: at,
    createdAt: at,
    updatedAt: at,
    people: people,
  );
}

MemoryItem _memory(String kind, String content, {String source = 'ai'}) =>
    MemoryItem(
      id: content,
      kind: kind,
      content: content,
      source: source,
      createdAt: DateTime(2026),
    );

void main() {
  final events = [
    for (var i = 0; i < 6; i++)
      _event('e$i', 'Event $i', people: i.isEven ? ['Sam'] : ['Ana']),
  ];
  final graph = GraphSnapshot(
    id: 'g',
    createdAt: DateTime(2026),
    eventCount: 6,
    model: 'm',
    overview: '',
    chapters: const [],
    links: [
      for (var i = 0; i < 5; i++)
        EventLink(fromEventId: 'e$i', toEventId: 'e${i + 1}', relation: 'r$i'),
      const EventLink(fromEventId: 'e0', toEventId: 'gone', relation: 'x'),
    ],
    themes: const [
      StoryTheme(name: 'Lake summers', description: 'd', eventIds: ['e0']),
      StoryTheme(name: 'Work', description: '', eventIds: ['e1', 'e2']),
      StoryTheme(name: 'Empty', description: '', eventIds: []),
    ],
  );
  final memories = [
    _memory('person', 'Sam is my brother'),
    _memory('person', 'Lee: a man in a hat in "Event 1"', source: answerSource),
    _memory('fact', 'I work nights'),
    _memory('place', 'Home is Leeds'),
  ];

  LearningView at(DateTime now) => computeLearning(
    events: events,
    memories: memories,
    graph: graph,
    now: now,
  );

  test('counts what the AI knows and shows a few real findings', () {
    final view = at(DateTime(2026, 10, 5, 10));
    expect(view.people, 3); // Sam, Ana, and Lee from an answer
    expect(view.places, 0);
    expect(view.facts, 3); // memories other than answers
    expect(view.connections, hasLength(shownConnections));
    expect(view.connections, everyElement(isNot(contains('untitled'))));
    expect(view.connections.first, startsWith('“Event '));
    expect(view.threads, hasLength(shownThreads));
    expect(view.threads.map((t) => t.name), isNot(contains('Empty')));
    expect(view.remembers, hasLength(shownRemembers));
  });

  test('the selection holds between change times and rotates at them', () {
    final day = DateTime(2026, 10, 5);
    final rotation = learningRotation(day);
    final next = rotation.next;
    expect(next.isAfter(day), isTrue);
    // Same selection right up to the change, a new seed after it.
    final before = next.subtract(const Duration(minutes: 1));
    expect(learningRotation(before).seed, rotation.seed);
    expect(learningRotation(next).seed, isNot(rotation.seed));
    expect(learningRotation(next).next.isAfter(next), isTrue);
    // Three changes a day.
    var t = day;
    var changes = 0;
    while (true) {
      final r = learningRotation(t);
      if (r.next.day != day.day) break;
      changes++;
      t = r.next;
    }
    expect(changes, 3);
  });

  test('an empty library says the AI starts learning with events', () {
    final view = computeLearning(
      events: const [],
      memories: const [],
      now: DateTime(2026, 10, 5),
    );
    expect(view.isEmpty, isTrue);
  });
}
