import 'dart:convert';
import 'dart:io';

import 'package:eventlens/ai/ai_client.dart';
import 'package:eventlens/ai/dream_pass.dart';
import 'package:eventlens/data/app_database.dart';
import 'package:eventlens/data/memory_repository.dart';
import 'package:eventlens/models/event.dart';
import 'package:eventlens/models/learned_point.dart';
import 'package:eventlens/services/settings_service.dart';
import 'package:eventlens/state/dream_coordinator.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A fake AI: answers with [reply], or throws [error].
class _FakeAI implements AIClient {
  Map<String, dynamic> reply;
  AIException? error;
  final sent = <Map<String, dynamic>>[];

  _FakeAI(this.reply);

  @override
  Future<Map<String, dynamic>> createMessage(
    Map<String, dynamic> body, {
    List<String> betas = const [],
  }) async {
    sent.add(body);
    if (error case final e?) throw e;
    return {
      'stop_reason': 'end_turn',
      'content': [
        {'type': 'text', 'text': jsonEncode(reply)},
      ],
    };
  }

  @override
  void close() {}
}

Map<String, dynamic> _reply({
  List<Map<String, dynamic>> add = const [],
  List<Map<String, dynamic>> revise = const [],
  List<Map<String, dynamic>> archive = const [],
  List<Map<String, dynamic>> retire = const [],
  Map<String, dynamic>? dream,
}) => {
  'add_active': add,
  'revise_active': revise,
  'archive_active': archive,
  'retire_active': retire,
  'update_dream':
      dream ??
      {
        'changed': false,
        'foundation_statements': <String>[],
        'themes': <String>[],
        'event_ids': <String>[],
      },
  'reasoning': 'never kept',
};

LifeEvent _event(int i, {bool described = true, String experience = ''}) {
  final at = DateTime(2026, 9, i + 1, 12);
  return LifeEvent(
    id: 'ev$i',
    title: 'Event $i',
    notes: '',
    location: 'Lake',
    occurredAt: at,
    createdAt: at,
    updatedAt: at,
    description: described ? 'Account of event $i.' : '',
    experience: experience,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory tmp;
  late Database db;
  late MemoryRepository memory;
  late SettingsService book;
  late _FakeAI ai;
  late DateTime now;
  late DreamCoordinator dreams;
  var aiReady = true;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('eventlens_dream');
    db = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: '${tmp.path}/test.db',
    );
    memory = MemoryRepository(db);
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    book = SettingsService(
      const FlutterSecureStorage(),
      await SharedPreferences.getInstance(),
    );
    ai = _FakeAI(_reply());
    now = DateTime(2026, 10, 12, 9);
    aiReady = true;
    dreams = DreamCoordinator(
      memory: memory,
      book: book,
      makePass: () async => aiReady ? DreamPass(client: ai) : null,
      clock: () => now,
    );
  });

  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  final five = [for (var i = 0; i < 5; i++) _event(i)];

  group('Dream coordinator (2.5)', () {
    test('is due after five newly described events, not before', () async {
      final four = [
        for (var i = 0; i < 4; i++) _event(i),
        _event(9, described: false),
      ];
      expect(await dreams.runIfDue(events: four), DreamOutcome.notDue);
      expect(ai.sent, isEmpty);
      expect(await dreams.runIfDue(events: five), DreamOutcome.ran);
      expect(ai.sent, hasLength(1));
      expect(book.dreamedEvents, {for (final e in five) e.id});
    });

    test('a milestone makes one unread event enough', () async {
      final one = [_event(0)];
      expect(await dreams.runIfDue(events: one), DreamOutcome.notDue);
      await dreams.milestone();
      expect(await dreams.runIfDue(events: one), DreamOutcome.ran);
      expect(book.dreamMilestone, isFalse);
    });

    test('runs at most once a day', () async {
      expect(await dreams.runIfDue(events: five), DreamOutcome.ran);
      final ten = [for (var i = 0; i < 10; i++) _event(i)];
      expect(await dreams.runIfDue(events: ten), DreamOutcome.notDue);
      now = now.add(const Duration(days: 1));
      expect(await dreams.runIfDue(events: ten), DreamOutcome.ran);
      expect(ai.sent, hasLength(2));
    });

    test('runs one pass at a time', () async {
      final first = dreams.runIfDue(events: five);
      expect(dreams.running, isTrue);
      expect(await dreams.runIfDue(events: five), DreamOutcome.busy);
      expect(await first, DreamOutcome.ran);
      expect(ai.sent, hasLength(1));
    });

    test('saves the checked changes as new versions', () async {
      final ana = await memory.add(
        kind: 'person',
        content: 'Ana is a friend',
        source: 'answer',
        sentiment: const Sentiment(
          polarity: 'neutral',
          intensity: 'low',
          source: pendingSentiment,
        ),
        eventIds: ['ev0'],
      );
      final job = await memory.add(
        kind: 'fact',
        content: 'Works at the bakery',
        source: 'ai',
        sentiment: const Sentiment(
          polarity: 'neutral',
          intensity: 'low',
          source: migratedSentiment,
        ),
      );
      ai.reply = _reply(
        add: [
          {
            'kind': 'place',
            'content': 'The lake is a favourite spot',
            'polarity': 'positive',
            'intensity': 'high',
            'event_ids': ['e1', 'e2'],
            'reason': 'visited often',
          },
        ],
        revise: [
          {
            // Points are listed by kind: p1 is the fact, p2 is Ana.
            'id': 'p2',
            'new_content': 'Ana is a close friend',
            'polarity': 'positive',
            'intensity': 'medium',
            'event_ids': ['e3'],
            'reason': 'seen together often',
          },
        ],
        retire: [
          {
            'id': 'p1',
            'event_ids': ['e4'],
            'reason': 'left the bakery',
          },
        ],
        dream: {
          'changed': true,
          'foundation_statements': ['Time by the lake matters'],
          'themes': ['Friendship'],
          'event_ids': ['e1'],
        },
      );
      expect(await dreams.runIfDue(events: five), DreamOutcome.ran);

      final anaHistory = await memory.history(ana.pointId);
      expect(anaHistory.map((p) => p.content), [
        'Ana is a friend',
        'Ana is a close friend',
      ]);
      final revised = anaHistory.last;
      expect(revised.parentId, ana.id);
      expect(revised.eventIds, ['ev0', 'ev2']);
      expect(revised.sentiment.source, dreamSentiment);
      expect(revised.source, 'answer');
      expect(revised.reason, 'revised: seen together often');

      final jobNow = (await memory.history(job.pointId)).last;
      expect(jobNow.status, pointRetired);
      expect(jobNow.content, 'Works at the bakery');

      final lake = (await memory.current()).singleWhere(
        (p) => p.kind == 'place',
      );
      expect(lake.eventIds, ['ev0', 'ev1']);
      expect(lake.source, 'ai');
      expect(lake.reason, 'visited often');

      final dream = await memory.dream();
      expect(dream!.foundationStatements, ['Time by the lake matters']);
      expect(dream.version, 1);
    });

    test('sends no free write and turns down quotes of one', () async {
      final writes = [
        _event(0, experience: 'the light on the water made me feel at home'),
        for (var i = 1; i < 5; i++) _event(i),
      ];
      ai.reply = _reply(
        add: [
          {
            'kind': 'fact',
            'content': 'The light on the water made me feel at home',
            'polarity': 'positive',
            'intensity': 'high',
            'event_ids': ['e1'],
            'reason': 'quote',
          },
        ],
      );
      expect(await dreams.runIfDue(events: writes), DreamOutcome.ran);
      final sentText = jsonEncode(ai.sent.single);
      expect(sentText, isNot(contains('feel at home')));
      expect(await memory.current(), isEmpty);
    });

    test('waits for the next reset when the allowance is used up', () async {
      ai.error = const AIException('used up', statusCode: 402);
      expect(await dreams.runIfDue(events: five), DreamOutcome.waiting);
      expect(book.dreamedEvents, isEmpty, reason: 'nothing is lost');
      ai.error = null;
      expect(await dreams.runIfDue(events: five), DreamOutcome.waiting);
      expect(ai.sent, hasLength(1));
      now = DateTime.utc(2026, 10, 13, 0, 1).toLocal();
      expect(await dreams.runIfDue(events: five), DreamOutcome.ran);
      expect(book.dreamWaitUntil, isNull);
    });

    test('other failures retry after an hour', () async {
      ai.error = const AIException('busy', statusCode: 503);
      expect(await dreams.runIfDue(events: five), DreamOutcome.failed);
      ai.error = null;
      expect(await dreams.runIfDue(events: five), DreamOutcome.notDue);
      now = now.add(DreamCoordinator.retryDelay);
      expect(await dreams.runIfDue(events: five), DreamOutcome.ran);
    });

    test('without an AI it waits and reads nothing', () async {
      aiReady = false;
      expect(await dreams.runIfDue(events: five), DreamOutcome.noAi);
      expect(book.dreamedEvents, isEmpty);
    });

    test('after erase, only later events are read', () async {
      await dreams.markAllRead(five);
      expect(dreams.unread(five), isEmpty);
      final later = [...five, for (var i = 5; i < 10; i++) _event(i)];
      expect(dreams.unread(later).map((e) => e.id), [
        for (var i = 5; i < 10; i++) 'ev$i',
      ]);
    });

    test('reads at most maxEvents a pass; the rest wait', () async {
      final many = [for (var i = 0; i < 25; i++) _event(i % 28)];
      final unique = {for (final e in many) e.id: e}.values.toList();
      expect(await dreams.runIfDue(events: unique), DreamOutcome.ran);
      expect(book.dreamedEvents, hasLength(DreamPass.maxEvents));
      expect(dreams.unread(unique), hasLength(unique.length - 20));
    });
  });
}
