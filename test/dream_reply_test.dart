import 'dart:convert';

import 'package:eventlens/ai/ai_client.dart';
import 'package:eventlens/ai/dream_pass.dart';
import 'package:eventlens/ai/dream_reply.dart';
import 'package:eventlens/models/learned_point.dart';
import 'package:flutter_test/flutter_test.dart';

/// A fake AI that answers every dream pass with [reply].
class _FakeAI implements AIClient {
  final Map<String, dynamic> reply;
  Map<String, dynamic>? sent;

  _FakeAI(this.reply);

  @override
  Future<Map<String, dynamic>> createMessage(
    Map<String, dynamic> body, {
    List<String> betas = const [],
  }) async {
    sent = body;
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

LearnedPoint _point(String id, String content, {String status = pointActive}) =>
    LearnedPoint(
      id: '$id-v1',
      pointId: id,
      version: 1,
      kind: 'person',
      content: content,
      sentiment: const Sentiment(
        polarity: 'neutral',
        intensity: 'low',
        source: 'migrated',
      ),
      source: 'ai',
      eventIds: const [],
      status: status,
      createdAt: DateTime(2026, 9, 1),
    );

final _input = DreamInput(
  today: DateTime(2026, 10, 12),
  newEvents: [
    DreamEvent(id: 'event-a', occurredAt: DateTime(2026, 10, 1), title: 'A'),
    DreamEvent(id: 'event-b', occurredAt: DateTime(2026, 10, 2), title: 'B'),
  ],
  active: [
    _point('pt-ana', 'Ana is a close friend'),
    _point('pt-ben', 'Ben coaches the Sunday team'),
  ],
  archived: [_point('pt-job', 'Works at the bakery', status: pointArchived)],
  quietNames: const {'ben'},
);

const _freeWrite =
    'I sat on the dock and felt the whole week finally slip away from me';

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
  'reasoning': 'Private working notes that must never be kept.',
};

Map<String, dynamic> _add(
  String content, {
  List<String> ev = const ['e1'],
  String kind = 'person',
}) => {
  'kind': kind,
  'content': content,
  'polarity': 'positive',
  'intensity': 'high',
  'event_ids': ev,
  'reason': 'seen at the lake',
};

Future<DreamChanges> _run(Map<String, dynamic> reply) async {
  final ai = _FakeAI(reply);
  final pass = DreamPass(client: ai);
  final request = pass.buildRequest(_input);
  final response = await pass.send(request);
  expect(ai.sent, same(request.body));
  return DreamChanges.parse(
    response,
    request: request,
    input: _input,
    freeWrites: const [_freeWrite],
  );
}

void main() {
  group('Dream reply checker (2.2)', () {
    test(
      'keeps a valid add with mapped evidence and a dream sentiment',
      () async {
        final c = await _run(
          _reply(
            add: [
              _add('Cara runs the bookshop', ev: ['e1', 'E2', 'e1']),
            ],
          ),
        );
        expect(c.rejected, 0);
        final add = c.adds.single;
        expect(add.content, 'Cara runs the bookshop');
        expect(add.eventIds, ['event-a', 'event-b']);
        expect(add.sentiment.polarity, 'positive');
        expect(add.sentiment.intensity, 'high');
        expect(add.sentiment.source, dreamSentiment);
        expect(add.reason, 'seen at the lake');
      },
    );

    test('turns down changes with no real evidence', () async {
      final c = await _run(
        _reply(
          add: [
            _add('No evidence', ev: const []),
            _add('Made-up evidence', ev: const ['e9', 'event-a']),
          ],
        ),
      );
      expect(c.adds, isEmpty);
      expect(c.rejected, 2);
    });

    test('turns down unknown kinds, long content and duplicates', () async {
      final c = await _run(
        _reply(
          add: [
            _add('A diagnosis', kind: 'diagnosis'),
            _add('x' * (DreamPass.maxContent + 1)),
            _add('ana is a close friend'),
            _add('Cara runs the bookshop'),
            _add('Cara runs the bookshop'),
          ],
        ),
      );
      expect(c.adds.map((a) => a.content), ['Cara runs the bookshop']);
      expect(c.rejected, 4);
    });

    test('turns down quotes of six or more words from a free write', () async {
      final c = await _run(
        _reply(
          add: [
            _add('Felt the whole week finally slip away'),
            _add('Felt the week slip away at the dock'),
          ],
        ),
      );
      expect(c.adds.map((a) => a.content), [
        'Felt the week slip away at the dock',
      ]);
      expect(c.rejected, 1);
    });

    test('strips echoed name marks', () async {
      final c = await _run(
        _reply(add: [_add('Ana [Honored] visits on Sundays')]),
      );
      expect(c.adds.single.content, 'Ana visits on Sundays');
    });

    test('caps each change type at maxChanges', () async {
      final c = await _run(
        _reply(add: [for (var i = 0; i < 12; i++) _add('Point number $i')]),
      );
      expect(c.adds, hasLength(DreamPass.maxChanges));
      expect(c.rejected, 2);
    });

    test(
      'revises known points, revives archived ones, ignores strangers',
      () async {
        Map<String, dynamic> rev(String id, String content) => {
          'id': id,
          'new_content': content,
          'polarity': 'mixed',
          'intensity': 'medium',
          'event_ids': ['e2'],
          'reason': 'new events',
        };
        final c = await _run(
          _reply(
            revise: [
              rev('p1', 'Ana is the closest friend'),
              rev('p3', 'Works at the bakery again'),
              rev('p9', 'Unknown point'),
              rev('pt-ana', 'Raw ids are not references'),
            ],
          ),
        );
        expect(c.revisions.map((r) => (r.pointId, r.revives)), [
          ('pt-ana', false),
          ('pt-job', true),
        ]);
        expect(c.revisions.first.sentiment.polarity, 'mixed');
        expect(c.rejected, 2);
      },
    );

    test(
      'archives and retires active points only, one change per point',
      () async {
        Map<String, dynamic> change(String id) => {
          'id': id,
          'event_ids': ['e1'],
          'reason': 'moved away',
        };
        final c = await _run(
          _reply(
            revise: [
              {
                'id': 'p1',
                'new_content': 'Ana moved away',
                'polarity': 'neutral',
                'intensity': 'low',
                'event_ids': ['e1'],
                'reason': 'moved',
              },
            ],
            archive: [change('p1'), change('p2'), change('p3')],
            retire: [
              change('p2'),
              {'id': 'p2', 'event_ids': <String>[], 'reason': ''},
            ],
          ),
        );
        expect(c.statusChanges.map((s) => (s.pointId, s.status)), [
          ('pt-ben', pointArchived),
        ]);
        // p1 already revised, p3 archived, p2 twice, and one with no evidence.
        expect(c.rejected, 4);
      },
    );

    test('keeps the dream update but drops Quiet names and quotes', () async {
      final c = await _run(
        _reply(
          dream: {
            'changed': true,
            'foundation_statements': [
              'Ana is the closest friend',
              'Ben matters on Sundays',
              'Felt the whole week finally slip away from me',
              'Ana is the closest friend',
            ],
            'themes': ['Time by the water', 'y' * (DreamPass.maxDreamLine + 1)],
            'event_ids': ['e1'],
          },
        ),
      );
      expect(c.dream!.foundationStatements, ['Ana is the closest friend']);
      expect(c.dream!.themes, ['Time by the water']);
      expect(c.dream!.eventIds, ['event-a']);
      expect(c.rejected, 4);
    });

    test('an unchanged or unsupported dream is no update', () async {
      expect((await _run(_reply())).dream, isNull);
      final c = await _run(
        _reply(
          dream: {
            'changed': true,
            'foundation_statements': ['Ana is the closest friend'],
            'themes': <String>[],
            'event_ids': ['e7'],
          },
        ),
      );
      expect(c.dream, isNull);
      expect(c.isEmpty, isTrue);
    });

    test('a refusal surfaces as an AI error', () async {
      final request = DreamPass(client: _FakeAI(const {})).buildRequest(_input);
      expect(
        () => DreamChanges.parse(
          {'stop_reason': 'refusal', 'content': []},
          request: request,
          input: _input,
        ),
        throwsA(isA<AIException>()),
      );
    });
  });
}
