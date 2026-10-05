import 'dart:convert';
import 'dart:io';

import 'package:eventlens/ai/anthropic_ai_client.dart';
import 'package:eventlens/ai/graph_builder.dart';
import 'package:eventlens/data/app_database.dart';
import 'package:eventlens/data/graph_repository.dart';
import 'package:eventlens/graph/force_layout.dart';
import 'package:eventlens/models/event.dart';
import 'package:eventlens/models/memory_graph.dart';
import 'package:eventlens/models/memory_item.dart';
import 'package:eventlens/models/ring_palette.dart';
import 'package:eventlens/services/rewards_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
    final builder = GraphBuilder(client: AnthropicAIClient(apiKey: 'k'));
    final body = builder.buildRequest(ordered, const []);
    expect(body['fallbacks'], 'default');
    expect(
      body['output_config']['format']['schema']['required'],
      containsAll(['overview', 'chapters', 'links', 'themes']),
    );
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
          {
            'title': 'Empty',
            'summary': 's',
            'event_refs': ['E42'],
          },
        ],
        'links': [
          {'from': 'E1', 'to': 'E3', 'relation': 'again'},
          {'from': 'E2', 'to': 'E2', 'relation': 'self'},
          {'from': 'E1', 'to': 'X', 'relation': 'bogus'},
        ],
        'themes': [
          {
            'name': 'Walks',
            'description': 'd',
            'event_refs': ['E2'],
          },
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
        {'stop_reason': 'refusal', 'content': []},
        ordered,
        describedCount: 3,
      ),
      throwsA(isA<AIException>()),
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
    expect(
      forceLayout(LayoutInput.fromGraph(const GraphData([], []))),
      isEmpty,
    );
  });

  test('v1 databases upgrade and keep their data', () async {
    sqfliteFfiInit();
    final dir = await Directory.systemTemp.createTemp('eventlens_migrate');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/old.db';
    // A database as version 1 of the app created it.
    final v1 = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) =>
            db.execute('CREATE TABLE events (id TEXT PRIMARY KEY, title TEXT)'),
      ),
    );
    await v1.insert('events', {'id': 'old', 'title': 'Kept'});
    await v1.close();

    final db = await AppDatabase.open(factory: databaseFactoryFfi, path: path);
    expect(await db.getVersion(), AppDatabase.version);
    expect((await db.query('events')).single['title'], 'Kept');
    final repo = GraphRepository(db);
    expect(await repo.latest(), isNull);
    final snapshot = GraphBuilder.parse(
      response({'overview': 'o', 'chapters': [], 'links': [], 'themes': []}),
      ordered,
      describedCount: 3,
    );
    await repo.replace(snapshot);
    await repo.replace(snapshot);
    expect((await db.query('graph_snapshots')), hasLength(1));
    expect((await repo.latest())!.overview, 'o');
    await db.close();
  });

  test('older saved graphs (no ids, "groups", chapter colours) still load', () {
    final row = {
      'id': 'old',
      'created_at': 0,
      'event_count': 2,
      'model': 'm',
      'data': jsonEncode({
        'overview': 'o',
        'chapters': [
          {
            'title': 'A',
            'summary': 's',
            'event_ids': ['a'],
          },
          {
            'id': 'x',
            'title': 'B',
            'summary': 's',
            'event_ids': ['b'],
            'color': 0xFFE53935,
            'group_id': 'g',
            'edited': true,
          },
        ],
        'links': [
          {'from': 'a', 'to': 'b', 'relation': 'r', 'manual': true},
        ],
        'themes': [
          {
            'name': 'T',
            'description': 'd',
            'event_ids': ['a'],
          },
        ],
        'groups': [
          {'id': 'g', 'name': 'Era'},
        ],
      }),
    };
    final snapshot = GraphSnapshot.fromRow(row);
    expect(snapshot.chapters.map((c) => c.id), ['c0', 'x']);
    expect(snapshot.chapters.last.bookId, 'g');
    expect(snapshot.books.single.title, 'Era');
    expect(snapshot.photoCount, 0);
    expect(snapshot.rings, isEmpty);
    expect(snapshot.updatedAt, snapshot.createdAt);
    // Round-trips with the new fields.
    final again = GraphSnapshot.fromRow(
      snapshot.copyWith(rings: const {'a': 3}).toRow(),
    );
    expect(again.books.single.title, 'Era');
    expect(again.rings, {'a': 3});
    expect(again.chapters.first.id, 'c0');
  });

  test('sanitize repairs every kind of bad data', () {
    final dirty = GraphSnapshot(
      id: 's',
      createdAt: DateTime(2026),
      eventCount: 3,
      model: '',
      overview: '  spaced  ',
      books: const [
        Book(id: 'b', title: ' '),
        Book(id: 'b', title: 'Dup id'),
      ],
      chapters: const [
        TimelineChapter(
          id: 'x',
          title: 'One',
          summary: '',
          eventIds: ['a', 'a', 'gone'],
        ),
        TimelineChapter(
          id: 'x',
          title: '',
          summary: '',
          eventIds: ['a', 'b'],
          bookId: 'nope',
        ),
      ],
      links: const [
        EventLink(fromEventId: 'a', toEventId: 'b', relation: ''),
        EventLink(fromEventId: 'a', toEventId: 'b', relation: 'dup'),
        EventLink(fromEventId: 'a', toEventId: 'a', relation: 'self'),
        EventLink(fromEventId: 'a', toEventId: 'gone', relation: 'x'),
      ],
      themes: const [
        StoryTheme(name: '', description: '', eventIds: ['gone']),
        StoryTheme(name: 'Walks', description: '', eventIds: ['b']),
        StoryTheme(name: 'walks', description: 'dup', eventIds: []),
      ],
      rings: const {'a': 1, 'gone': 1, 'b': 99, 'c': -1},
    );
    final clean = dirty.sanitized({'a', 'b', 'c'});
    expect(clean.overview, 'spaced');
    expect(clean.books.map((b) => b.title), [untitledBookTitle, 'Dup id']);
    expect(clean.books.map((b) => b.id).toSet(), hasLength(2));
    expect(clean.chapters.map((c) => c.id).toSet(), hasLength(2));
    expect(clean.chapters.first.eventIds, ['a']);
    // 'a' already sits in the first chapter.
    expect(clean.chapters.last.eventIds, ['b']);
    expect(clean.chapters.last.title, 'Untitled chapter');
    expect(clean.chapters.last.bookId, isNull);
    expect(clean.links, hasLength(1));
    expect(clean.links.single.relation, 'related');
    expect(clean.themes.map((t) => t.name), ['Untitled theme', 'Walks']);
    expect(clean.rings, {'a': 1});
    // Sanitising is stable.
    expect(clean.sanitized({'a', 'b', 'c'}).toRow(), clean.toRow());
  });

  test('withUserLayer cannot change anything the AI wrote', () {
    final ai = GraphSnapshot(
      id: 's',
      createdAt: DateTime(2026),
      eventCount: 2,
      model: 'm',
      overview: 'AI overview',
      chapters: const [
        TimelineChapter(id: 'c', title: 'AI', summary: 'AI', eventIds: ['a']),
      ],
      links: const [EventLink(fromEventId: 'a', toEventId: 'b', relation: 'r')],
      themes: const [
        StoryTheme(name: 'T', description: 'd', eventIds: ['a']),
      ],
    );
    final user = ai.withUserLayer(
      books: const [Book(id: 'b1', title: 'Mine')],
      chapterBooks: const {'c': 'b1', 'unknown': 'b1'},
      rings: const {'a': 0},
    );
    expect(user.overview, ai.overview);
    expect(user.chapters.single.title, 'AI');
    expect(user.chapters.single.summary, 'AI');
    expect(user.chapters.single.eventIds, ['a']);
    expect(user.chapters.single.bookId, 'b1');
    expect(user.links.single.relation, 'r');
    expect(user.themes.single.name, 'T');
    expect(user.books.single.title, 'Mine');
    expect(user.rings, {'a': 0});
    // Taking a chapter out of a book.
    expect(
      user
          .withUserLayer(
            books: user.books,
            chapterBooks: const {'c': null},
            rings: user.rings,
          )
          .chapters
          .single
          .bookId,
      isNull,
    );
  });

  test('AI updates add to the graph and ignore bad references', () {
    final graph = GraphSnapshot(
      id: 's',
      createdAt: DateTime(2026),
      eventCount: 3,
      model: 'm',
      overview: 'Old overview',
      chapters: const [
        TimelineChapter(id: 'c1', title: 'May', summary: 's', eventIds: ['a']),
        TimelineChapter(id: 'c2', title: 'June', summary: 's', eventIds: ['b']),
      ],
      links: const [EventLink(fromEventId: 'a', toEventId: 'b', relation: 'r')],
      themes: const [
        StoryTheme(name: 'Walks', description: 'd', eventIds: ['a']),
      ],
      books: const [Book(id: 'b1', title: 'Mine')],
      rings: const {'a': 0},
    );
    final existing = [described('a', 1), described('b', 2)];
    final fresh = [described('n1', 5), described('n2', 6), described('n3', 7)];
    final updated = GraphBuilder.applyUpdate(
      response({
        'overview': 'New overview',
        'placements': [
          {
            'event': 'N1',
            'chapter': 'C2',
            'new_chapter_title': '',
            'new_chapter_summary': '',
          },
          {
            'event': 'N2',
            'chapter': 'NEW',
            'new_chapter_title': 'July',
            'new_chapter_summary': 'Summer',
          },
          // Duplicate and unknown placements are ignored.
          {
            'event': 'N2',
            'chapter': 'C1',
            'new_chapter_title': '',
            'new_chapter_summary': '',
          },
          {
            'event': 'E1',
            'chapter': 'C2',
            'new_chapter_title': '',
            'new_chapter_summary': '',
          },
          {
            'event': 'N9',
            'chapter': 'C1',
            'new_chapter_title': '',
            'new_chapter_summary': '',
          },
        ],
        'links': [
          {'from': 'N2', 'to': 'E1', 'relation': 'again'},
          // Links between earlier events are not the update's business.
          {'from': 'E1', 'to': 'E2', 'relation': 'rewritten'},
          {'from': 'N1', 'to': 'X', 'relation': 'bad'},
        ],
        'themes': [
          {
            'name': 'walks',
            'description': 'ignored',
            'event_refs': ['N1'],
          },
          {
            'name': 'Heat',
            'description': 'Hot days',
            'event_refs': ['N2'],
          },
          {
            'name': 'Empty',
            'description': '',
            'event_refs': ['Q1'],
          },
        ],
      }),
      graph,
      existing,
      fresh,
      describedCount: 5,
      photoCount: 12,
    );
    expect(updated.chapters.map((c) => c.title), ['May', 'June', 'July']);
    expect(updated.chapters[0].eventIds, ['a']);
    expect(updated.chapters[1].eventIds, ['b', 'n1']);
    // N3 was forgotten by the AI, so it joins the latest chapter.
    expect(updated.chapters[2].eventIds, ['n2', 'n3']);
    expect(updated.chapters[2].summary, 'Summer');
    expect(updated.links.map((l) => l.relation), ['r', 'again']);
    expect(updated.themes.first.description, 'd');
    expect(updated.themes.first.eventIds, ['a', 'n1']);
    expect(updated.themes.map((t) => t.name), ['Walks', 'Heat']);
    expect(updated.overview, 'New overview');
    expect(updated.books.single.title, 'Mine');
    expect(updated.rings, {'a': 0});
    expect(updated.photoCount, 12);
    expect(updated.createdAt, graph.createdAt);
    expect(updated.updatedAt.isAfter(graph.updatedAt), isTrue);
  });

  test('ring colours unlock in order: 1 free, then 5, 6, 7… videos', () {
    expect(ringUnlockCost(0), 0);
    expect(ringUnlockCost(1), 5);
    expect(ringUnlockCost(2), 6);
    expect(ringUnlockCost(ringPalette.length - 1), 4 + ringPalette.length - 1);
    expect(ringColorFor(null), isNull);
    expect(ringColorFor(ringPalette.length), isNull);
  });

  test('watching rewarded videos unlocks the next colour', () async {
    SharedPreferences.setMockInitialValues({});
    final videos = _FakeVideos();
    final unlocks = RingUnlocks(await SharedPreferences.getInstance(), videos);
    expect(unlocks.unlockedCount, 1);
    expect(unlocks.isUnlocked(0), isTrue);
    expect(unlocks.isUnlocked(1), isFalse);
    expect(unlocks.nextLocked, 1);
    expect(unlocks.videosForNext, 5);

    // A skipped or failed video doesn't count.
    videos.finish = false;
    expect(await unlocks.watchVideo(), isFalse);
    expect(unlocks.progress, 0);

    videos.finish = true;
    for (var i = 0; i < 4; i++) {
      await unlocks.watchVideo();
    }
    expect(unlocks.isUnlocked(1), isFalse);
    expect(unlocks.videosForNext, 1);
    await unlocks.watchVideo();
    expect(unlocks.isUnlocked(1), isTrue);
    expect(unlocks.progress, 0);
    expect(unlocks.videosForNext, 6);

    for (var i = 0; i < 100; i++) {
      await unlocks.watchVideo();
    }
    expect(unlocks.unlockedCount, ringPalette.length);
    expect(unlocks.nextLocked, isNull);
    expect(await unlocks.watchVideo(), isFalse);
    expect(videos.shown, 1 + 5 + 6 + 7 + 8 + 9 + 10 + 11);
  });
}

class _FakeVideos implements RewardedVideoProvider {
  bool finish = true;
  int shown = 0;

  @override
  Future<bool> showRewardedVideo() async {
    shown++;
    return finish;
  }
}
