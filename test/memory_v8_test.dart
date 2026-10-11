import 'dart:convert';
import 'dart:io';

import 'package:eventlens/data/app_database.dart';
import 'package:eventlens/data/event_repository.dart';
import 'package:eventlens/data/graph_repository.dart';
import 'package:eventlens/data/image_vault.dart';
import 'package:eventlens/data/memory_repository.dart';
import 'package:eventlens/models/learned_point.dart';
import 'package:eventlens/models/memory_file.dart';
import 'package:eventlens/models/memory_item.dart';
import 'package:eventlens/services/export_service.dart';
import 'package:eventlens/services/settings_service.dart';
import 'package:eventlens/state/app_state.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _calm = Sentiment(polarity: 'neutral', intensity: 'low', source: 'test');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory tmp;
  late Database db;
  late MemoryRepository repo;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('eventlens_memory_v8');
    db = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: '${tmp.path}/test.db',
    );
    repo = MemoryRepository(db);
  });

  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  test('a v7 library upgrades: every memory moves in with its source and '
      'event, and the old table is gone', () async {
    final path = '${tmp.path}/v7.db';
    final v7 = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 7,
        onCreate: (db, _) async {
          await db.execute('CREATE TABLE events (id TEXT PRIMARY KEY)');
          await db.execute('''
            CREATE TABLE memories (
              id TEXT PRIMARY KEY,
              kind TEXT NOT NULL,
              content TEXT NOT NULL,
              source TEXT NOT NULL,
              event_id TEXT,
              created_at INTEGER NOT NULL
            )
          ''');
        },
      ),
    );
    await v7.insert('events', {'id': 'e1'});
    for (final (id, source, eventId) in [
      ('m1', 'ai', null),
      ('m2', answerSource, 'e1'),
      ('m3', 'user', null),
    ]) {
      await v7.insert('memories', {
        'id': id,
        'kind': 'person',
        'content': 'Ana: friend ($id)',
        'source': source,
        'event_id': eventId,
        'created_at': 1000,
      });
    }
    await v7.close();

    final upgraded = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    addTearDown(upgraded.close);
    expect(await upgraded.getVersion(), 8);
    final tables = await upgraded.query(
      'sqlite_master',
      where: 'type = ? AND name = ?',
      whereArgs: ['table', 'memories'],
    );
    expect(tables, isEmpty);

    final points = await MemoryRepository(upgraded).current();
    expect(points.map((p) => p.pointId), ['m1', 'm2', 'm3']);
    expect(points.map((p) => p.source), ['ai', answerSource, 'user']);
    expect(points[1].eventIds, ['e1']);
    expect(points[0].eventIds, isEmpty);
    for (final p in points) {
      expect(p.version, 1);
      expect(p.parentId, isNull);
      expect(p.status, pointActive);
      expect(p.sentiment.source, migratedSentiment);
      expect(p.sentiment.compact, 'neut:low');
    }
  });

  test('a revision keeps the old version and links back to it', () async {
    final first = await repo.add(
      kind: 'person',
      content: 'Ana wears red',
      source: answerSource,
      sentiment: _calm,
      eventIds: ['e5'],
    );
    final second = await repo.revise(
      first.pointId,
      content: 'Ana is my closest friend',
      sentiment: const Sentiment(
        polarity: 'positive',
        intensity: 'medium',
        source: 'dream',
      ),
      eventIds: ['e5', 'e12'],
      reason: 'seen together often',
    );

    expect(second!.version, 2);
    expect(second.parentId, first.id);
    expect(second.source, answerSource);
    expect(second.sentiment.compact, 'pos:med');
    final history = await repo.history(first.pointId);
    expect(history.map((p) => p.content), [
      'Ana wears red',
      'Ana is my closest friend',
    ]);
    expect((await repo.all()).single.content, 'Ana is my closest friend');
    expect((await repo.all()).single.id, first.pointId);
    expect(await repo.revise('missing', reason: 'x'), isNull);
  });

  test('archiving is a new version; the AI stops using the point', () async {
    final p = await repo.add(
      kind: 'fact',
      content: 'Works nights',
      source: 'ai',
      sentiment: _calm,
    );
    await repo.archive(p.pointId, 'changed jobs');

    expect(await repo.all(), isEmpty);
    expect((await repo.current()).single.status, pointArchived);
    expect((await repo.current()).single.reason, 'changed jobs');
    expect(await repo.history(p.pointId), hasLength(2));
  });

  test('the dream state keeps every version', () async {
    expect(await repo.dream(), isNull);
    final one = await repo.saveDream(
      foundationStatements: ['Ana is a close friend.'],
      themes: ['Growth'],
      eventIds: ['e1'],
    );
    final two = await repo.saveDream(
      foundationStatements: ['Ana is the closest friend.'],
      themes: ['Growth', 'Home'],
      eventIds: ['e1', 'e2'],
    );
    expect(two.version, 2);
    expect(two.parentId, one.id);
    expect((await repo.dream())!.themes, ['Growth', 'Home']);
    expect(await repo.dreamHistory(), hasLength(2));
  });

  test('a spelling fix reaches every version and the dream state', () async {
    final p = await repo.add(
      kind: 'person',
      content: 'Ana wears red',
      source: 'ai',
      sentiment: _calm,
    );
    await repo.revise(p.pointId, content: 'Ana loves the lake', reason: 'r');
    await repo.saveDream(
      foundationStatements: ['Ana is a close friend.'],
      themes: ['Ana and home'],
      eventIds: const [],
    );

    final changed = await repo.fixSpelling((t) => t.replaceAll('Ana', 'Anna'));
    expect(changed, 3);
    expect((await repo.history(p.pointId)).map((v) => v.content), [
      'Anna wears red',
      'Anna loves the lake',
    ]);
    final dream = (await repo.dream())!;
    expect(dream.foundationStatements, ['Anna is a close friend.']);
    expect(dream.themes, ['Anna and home']);
  });

  test('erase removes every point, every version and the dream', () async {
    final p = await repo.add(
      kind: 'fact',
      content: 'x',
      source: 'ai',
      sentiment: _calm,
    );
    await repo.revise(p.pointId, content: 'y', reason: 'r');
    await repo.archive(p.pointId, 'old');
    await repo.saveDream(
      foundationStatements: ['s'],
      themes: const [],
      eventIds: const [],
    );

    await repo.deleteAll();
    expect(await db.query('learned_points'), isEmpty);
    expect(await db.query('dream_states'), isEmpty);
  });

  group('through the app', () {
    late AppState state;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      state = AppState(
        events: EventRepository(db),
        memoryRepo: repo,
        graphRepo: GraphRepository(db),
        vault: ImageVault(Directory('${tmp.path}/vault')),
        settings: SettingsService(
          const FlutterSecureStorage(),
          await SharedPreferences.getInstance(),
        ),
      );
      await state.load();
    });

    test('an answer is saved as a first version with its event', () async {
      await state.addMemory(
        'person',
        'Ana: the friend in the red jacket',
        source: answerSource,
        eventId: 'e1',
      );
      final point = state.learnedPoints.single;
      expect(point.source, answerSource);
      expect(point.eventIds, ['e1']);
      expect(point.version, 1);
      expect(point.sentiment.source, pendingSentiment);
      expect(state.memories.single.eventId, 'e1');
    });

    test('fixing a spelling and erasing reach the whole memory', () async {
      final p = await repo.add(
        kind: 'person',
        content: 'Ana wears red',
        source: 'ai',
        sentiment: _calm,
      );
      await repo.revise(p.pointId, content: 'Ana loves the lake', reason: 'r');
      await repo.saveDream(
        foundationStatements: ['Ana is a close friend.'],
        themes: const [],
        eventIds: const [],
      );
      await state.load();

      await state.fixNameSpelling('Ana', 'Anna');
      expect((await repo.history(p.pointId)).map((v) => v.content), [
        'Anna wears red',
        'Anna loves the lake',
      ]);
      expect(state.dream!.foundationStatements, ['Anna is a close friend.']);
      expect(state.memories.single.content, 'Anna loves the lake');

      await state.eraseAiMemory();
      expect(state.memories, isEmpty);
      expect(state.learnedPoints, isEmpty);
      expect(state.dream, isNull);
      expect(await db.query('learned_points'), isEmpty);
      expect(await db.query('dream_states'), isEmpty);
    });
  });

  test('the export includes a readable memory.md', () async {
    final p = await repo.add(
      kind: 'person',
      content: 'Ana is my closest friend',
      source: 'ai',
      sentiment: const Sentiment(
        polarity: 'positive',
        intensity: 'high',
        source: 'dream',
      ),
    );
    final gone = await repo.add(
      kind: 'fact',
      content: 'Works nights',
      source: 'ai',
      sentiment: _calm,
    );
    await repo.archive(gone.pointId, 'changed jobs');
    await repo.saveDream(
      foundationStatements: ['Friendship carries the story.'],
      themes: ['Growth'],
      eventIds: const [],
    );

    final file = memoryMarkdown(await repo.current(), await repo.dream());
    expect(file, contains('Friendship carries the story.'));
    expect(file, contains('Themes: Growth'));
    expect(file, contains('- ${p.content} (feeling: positive, high)'));
    expect(file, isNot(contains('Works nights')));
    expect(memoryMarkdown(const [], null), contains('doesn\'t remember'));

    final archive = await LibraryExporter(
      ImageVault(Directory('${tmp.path}/vault')),
    ).build(events: const [], memories: await repo.all(), memoryFile: file);
    final entry = archive.findFile('EventLens/memory.md')!;
    expect(utf8.decode(entry.content as List<int>), file);
  });
}
