import 'package:eventlens/ai/ai_client.dart';
import 'package:eventlens/ai/dream_pass.dart';
import 'package:eventlens/models/event.dart';
import 'package:eventlens/models/learned_point.dart';
import 'package:eventlens/models/memory_item.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoClient implements AIClient {
  @override
  Future<Map<String, dynamic>> createMessage(
    Map<String, dynamic> body, {
    List<String> betas = const [],
  }) => throw UnimplementedError();

  @override
  void close() {}
}

LearnedPoint _point(
  String id,
  String content, {
  String kind = 'person',
  List<String> eventIds = const [],
  String status = pointActive,
}) => LearnedPoint(
  id: '$id-v1',
  pointId: id,
  version: 1,
  kind: kind,
  content: content,
  sentiment: const Sentiment(
    polarity: 'positive',
    intensity: 'medium',
    source: 'dream',
  ),
  source: 'ai',
  eventIds: eventIds,
  status: status,
  createdAt: DateTime(2026, 9, 1),
);

LifeEvent _lifeEvent() {
  final at = DateTime(2026, 10, 3, 12);
  return LifeEvent(
    id: 'event-new-1',
    title: 'Lunch at the lake',
    notes: 'private notes',
    location: 'Lake Tahoe',
    occurredAt: at,
    createdAt: at,
    updatedAt: at,
    summary: 'Lunch with Ana by the water.',
    description: 'I had lunch with Ana on the dock.',
    people: const ['Ana'],
    places: const ['Lake Tahoe'],
    experience: 'SECRET FREE WRITE about how it felt',
    experienceLabels: const ['calm'],
    confirmedLabels: const ['calm'],
    rejectedLabels: const ['lonely'],
    supportLevel: supportDistress,
  );
}

void main() {
  final pass = DreamPass(client: _NoClient());

  DreamInput input() => DreamInput(
    today: DateTime(2026, 10, 12),
    newEvents: [DreamEvent.from(_lifeEvent())],
    earlierEvents: [
      DreamEvent(
        id: 'event-old-1',
        occurredAt: DateTime(2026, 8, 2),
        title: 'Ana moves in nearby',
      ),
    ],
    active: [
      _point('pt-ana', 'Ana is a close friend', eventIds: ['event-old-1']),
      _point('pt-ben', 'Ben coaches the Sunday team'),
    ],
    archived: [
      _point(
        'pt-job',
        'Works at the bakery',
        kind: 'fact',
        status: pointArchived,
      ),
    ],
    dream: DreamState(
      id: 'd1',
      version: 1,
      foundationStatements: const ['Ana is the closest friend'],
      themes: const ['Ben and Sunday football'],
      eventIds: const [],
      createdAt: DateTime(2026, 9, 1),
    ),
    honoredNames: const {'ana'},
    quietNames: const {'ben'},
  );

  String content(DreamRequest r) =>
      (r.body['messages'] as List).single['content'] as String;

  group('Dream pass request (2.1)', () {
    test('builds a structured request with the instructions', () {
      final r = pass.buildRequest(input());
      expect(r.body['system'], DreamPass.instructions);
      expect(r.body['output_config']['effort'], 'medium');
      final format = r.body['output_config']['format'] as Map;
      expect(format['type'], 'json_schema');
      expect(format['schema'], same(DreamPass.schema));
    });

    test('names events and points by short references', () {
      final r = pass.buildRequest(input());
      expect(r.eventRefs, {'e1': 'event-new-1', 'e2': 'event-old-1'});
      expect(r.pointRefs, {'p1': 'pt-ana', 'p2': 'pt-ben', 'p3': 'pt-job'});
      final text = content(r);
      expect(text, contains('p1 | person | pos:med | Ana is a close friend'));
      expect(text, contains('evidence: e2'));
      expect(text, contains('e2 | 2026-08-02 | Ana moves in nearby'));
      expect(text, contains('p3 | fact | pos:med | Works at the bakery'));
    });

    test('reads the account and labels, never the free write or support', () {
      final text = content(pass.buildRequest(input()));
      expect(text, contains('I had lunch with Ana on the dock.'));
      expect(text, contains('Confirmed labels: calm'));
      expect(text, contains('Turned-down labels: lonely'));
      expect(text, isNot(contains('SECRET FREE WRITE')));
      expect(text, isNot(contains('private notes')));
      expect(text, isNot(contains(supportDistress)));
    });

    test('marks Honored and Quiet names', () {
      final text = content(pass.buildRequest(input()));
      expect(text, contains('Ana is a close friend [Honored]'));
      expect(text, contains('Ben coaches the Sunday team [Quiet]'));
      expect(text, contains('- Ben and Sunday football [Quiet]'));
      expect(text, contains('Lunch at the lake [Honored]'));
    });

    test('first pass and empty memory read as none', () {
      final r = pass.buildRequest(
        DreamInput(
          today: DateTime(2026, 10, 12),
          newEvents: const [],
          active: const [],
        ),
      );
      final text = content(r);
      expect(text, contains('none yet (this is the first pass)'));
      expect(text, contains('<active_points>\nnone\n</active_points>'));
      expect(text, contains('<new_events>\nnone\n</new_events>'));
    });

    test('reads at most maxEvents new events and cuts long accounts', () {
      final at = DateTime(2026, 1, 1);
      final many = [
        for (var i = 0; i < DreamPass.maxEvents + 5; i++)
          DreamEvent(
            id: 'ev$i',
            occurredAt: at,
            title: 'Event $i',
            account: 'word ' * 600,
          ),
      ];
      final r = pass.buildRequest(
        DreamInput(today: at, newEvents: many, active: const []),
      );
      expect(r.eventRefs.length, DreamPass.maxEvents);
      final account = content(r)
          .split('\n')
          .firstWhere((l) => l.startsWith('Account: '));
      expect(account.length, lessThan(DreamPass.maxAccount + 20));
    });
  });

  group('Dream pass reply schema (2.1)', () {
    final props = DreamPass.schema['properties'] as Map<String, dynamic>;

    test('has every change type, the dream and the reasoning', () {
      expect(DreamPass.schema['required'], [
        'add_active',
        'revise_active',
        'archive_active',
        'retire_active',
        'update_dream',
        'reasoning',
      ]);
      expect(DreamPass.schema['additionalProperties'], false);
    });

    test('uses the app\'s kinds and sentiment values', () {
      final add = props['add_active']['items']['properties'] as Map;
      expect(add['kind']['enum'], memoryKinds);
      expect(add['polarity']['enum'], polarities);
      expect(add['intensity']['enum'], intensities);
      expect(add.containsKey('source'), isFalse, reason: 'the app fills it');
    });

    test('every change cites evidence and a reason', () {
      for (final key in [
        'add_active',
        'revise_active',
        'archive_active',
        'retire_active',
      ]) {
        final item = props[key]['items'] as Map;
        expect(
          item['required'],
          containsAll(['event_ids', 'reason']),
          reason: key,
        );
        expect(item['additionalProperties'], false, reason: key);
      }
      expect(props['update_dream']['required'], [
        'changed',
        'foundation_statements',
        'themes',
        'event_ids',
      ]);
    });
  });
}
