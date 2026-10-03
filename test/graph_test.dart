import 'dart:convert';
import 'dart:io';

import 'package:eventlens/ai/anthropic_client.dart';
import 'package:eventlens/ai/graph_builder.dart';
import 'package:eventlens/data/app_database.dart';
import 'package:eventlens/data/graph_repository.dart';
import 'package:eventlens/graph/force_layout.dart';
import 'package:eventlens/models/event.dart';
import 'package:eventlens/models/memory_graph.dart';
import 'package:eventlens/models/memory_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

LifeEvent described(String id, int day, {List<String> people = const []}) {
  final at = DateTime(2026, 5, day);
  return LifeEvent(
    id: id,
    title: 'Event $id',
    notes: 'notes $id',
    location: '',
    occurredAt: at,
    createdAt: at,
    updatedAt: at,
    summary: 'Summary $id',
    description: 'Account $id',
    people: people,
    status: EventStatus.described,
  );
}

Map<String, dynamic> response(Map<String, dynamic> data) => {
      'model': 'claude-opus-5-5',
      'stop_reason': 'end_turn',
      'content': [
        {'type': 'text', 'text': jsonEncode(data)},
      ],
    };

void main() {
  // Deliberately out of order: the builder sorts by time.
  final events = [described('b', 2), described('a', 1), described('c', 3)];
  final ordered = GraphBuilder.eligible(events);

  test('events are numbered in date order and drafts are skipped', () {
    final draft = LifeEvent(
      id: 'draft',
      title: '',
      notes: '',
      location: '',
      occurredAt: DateTime(2026),
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    final list = GraphBuilder.eligible([...events, draft]);
    expect(list.map((e) => e.id), ['a', 'b', 'c']);
    final text = GraphBuilder.journalText(list, const []);
    expect(text.indexOf('E1 |'), lessThan(text.indexOf('E2 |')));
    expect(text, contains('Event a'));
  });

  test('request is text-only with structured output and fallbacks', () {
    final builder = GraphBuilder(client: AnthropicClient(apiKey: 'k'));
    final body = builder.buildRequest(ordered, const []);
    expect(body['fallbacks'], 'default');
    expect(body['output_config']['format']['schema']['required'],
        containsAll(['overview', 'chapters', 'links', 'themes']));
    expect(body['messages'][0]['content'], isA<String>());
  });

  test('parse maps E-codes to ids and drops bad references', () {
    final snapshot = GraphBuilder.parse(
      response({
        'overview': 'Spring.',
        'chapters': [
          {
            'title': 'May',
            'summary': 's',
            'event_refs': ['E1', 'E2', 'E3', 'E9', 'E2'],
          },
          {'title': 'Empty', 'summary': 's', 'event_refs': ['E42']},
        ],
        'links': [
          {'from': 'E1', 'to': 'E3', 'relation': 'again'},
          {'from': 'E2', 'to': 'E2', 'relation': 'self'},
          {'from': 'E1', 'to': 'X', 'relation': 'bogus'},
        ],
        'themes': [
          {'name': 'Walks', 'description': 'd', 'event_refs': ['E2']},
          {'name': 'Ghost', 'description': 'd', 'event_refs': []},
        ],
      }),
      ordered,
      describedCount: 3,
    );
    expect(snapshot.chapters, hasLength(1));
    expect(snapshot.chapters.single.eventIds, ['a', 'b', 'c']);
    expect(snapshot.links, hasLength(1));
    expect(snapshot.links.single.fromEventId, 'a');
    expect(snapshot.links.single.toEventId, 'c');
    expect(snapshot.themes.single.name, 'Walks');
    expect(snapshot.eventCount, 3);
  });

  test('refusals surface as user-facing errors', () {
    expect(
      () => GraphBuilder.parse(
          {'stop_reason': 'refusal', 'content': []}, ordered,
          describedCount: 3),
      throwsA(isA<AnthropicException>()),
    );
  });

  test('graph marks who supplied each node', () {
    final graph = buildGraph(
      events: [
        described('a', 1, people: ['Sam']).copyWith(notes: 'with Sam'),
        described('b', 2, people: ['Alex']),
      ],
      memories: [
        MemoryItem(
          id: 'm1',
          kind: 'person',
          content: 'Alex is my cousin',
          source: 'ai',
          eventId: 'b',
          createdAt: DateTime(2026),
        ),
      ],
    );
    expect(graph.node('event:a')!.provenance, Provenance.both);
    expect(graph.node('person:sam')!.provenance, Provenance.human);
    expect(graph.node('person:alex')!.provenance, Provenance.ai);
    expect(graph.node('memory:m1')!.provenance, Provenance.ai);
    expect(
      graph.edges.where((e) => e.from == 'memory:m1').map((e) => e.to),
      containsAll(['event:b', 'person:alex']),
    );
  });

  test('layout is deterministic and keeps events in time order', () {
    final graph = buildGraph(
      events: [
        for (var d = 1; d <= 8; d++)
          described('e$d', d, people: [d.isEven ? 'Sam' : 'Alex']),
      ],
      memories: const [],
    );
    final input = LayoutInput.fromGraph(graph);
    final a = forceLayout(input), b = forceLayout(input);
    expect(a, b);
    for (final (x, y) in a.values) {
      expect(x.isFinite && y.isFinite, isTrue);
      expect(x, greaterThanOrEqualTo(0));
      expect(y, greaterThanOrEqualTo(0));
    }
    final xs = [for (var d = 1; d <= 8; d++) a['event:e$d']!.$1];
    for (var i = 1; i < xs.length; i++) {
      expect(xs[i], greaterThan(xs[i - 1]));
    }
    expect(forceLayout(LayoutInput.fromGraph(const GraphData([], []))), isEmpty);
  });

  test('v1 databases upgrade and keep their data', () async {
    sqfliteFfiInit();
    final dir = await Directory.systemTemp.createTemp('eventlens_migrate');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/old.db';
    // A database as version 1 of the app created it.
    final v1 = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) => db.execute(
              'CREATE TABLE events (id TEXT PRIMARY KEY, title TEXT)'),
        ));
    await v1.insert('events', {'id': 'old', 'title': 'Kept'});
    await v1.close();

    final db = await AppDatabase.open(factory: databaseFactoryFfi, path: path);
    expect(await db.getVersion(), AppDatabase.version);
    expect((await db.query('events')).single['title'], 'Kept');
    final repo = GraphRepository(db);
    expect(await repo.latest(), isNull);
    final snapshot = GraphBuilder.parse(
      response({
        'overview': 'o',
        'chapters': [],
        'links': [],
        'themes': [],
      }),
      ordered,
      describedCount: 3,
    );
    await repo.replace(snapshot);
    await repo.replace(snapshot);
    expect((await db.query('graph_snapshots')), hasLength(1));
    expect((await repo.latest())!.overview, 'o');
    await db.close();
  });
}
