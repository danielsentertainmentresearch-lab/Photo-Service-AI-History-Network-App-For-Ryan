import 'package:eventlens/ai/anthropic_ai_client.dart';
import 'package:eventlens/ai/experience_labeler.dart';
import 'package:eventlens/models/event.dart';
import 'package:eventlens/models/insights.dart';
import 'package:eventlens/models/learning_view.dart';
import 'package:eventlens/models/name_state.dart';
import 'package:eventlens/models/support_resources.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eventlens/ai/event_describer.dart';
import 'dart:convert';

class _Replies implements AIClient {
  final List<Map<String, dynamic>> replies;
  int calls = 0;

  _Replies(this.replies);

  @override
  Future<Map<String, dynamic>> createMessage(
    Map<String, dynamic> body, {
    List<String> betas = const [],
  }) async => replies[calls++];

  @override
  void close() {}
}

Map<String, dynamic> _reply(Map<String, dynamic> data) => {
  'stop_reason': 'end_turn',
  'content': [
    {'type': 'text', 'text': jsonEncode(data)},
  ],
};

LifeEvent _event(String id, DateTime at, {List<String> people = const []}) =>
    LifeEvent(
      id: id,
      title: id,
      notes: '',
      location: '',
      occurredAt: at,
      createdAt: at,
      updatedAt: at,
      people: people,
    );

void main() {
  group('support reading', () {
    test('a crisis reading comes back even with no labels', () async {
      final client = _Replies([
        _reply({
          'annotations': [],
          'labels': [],
          'support': {
            'level': 'crisis',
            'words': ['I want to end it'],
          },
        }),
      ]);
      final result = await ExperienceLabeler(
        client: client,
      ).labelWithSupport('I want to end it tonight.');
      expect(result.labels, isEmpty);
      expect(result.supportLevel, supportCrisis);
      expect(result.supportWords, ['I want to end it']);
      expect(client.calls, 1); // no review needed without labels
    });

    test('an unknown or missing level reads as none', () {
      expect(
        ExperienceLabeler.parseSupport(
          _reply({
            'annotations': [],
            'labels': [],
            'support': {'level': 'panic', 'words': []},
          }),
        ).level,
        supportNone,
      );
      expect(
        ExperienceLabeler.parseSupport(
          _reply({'annotations': [], 'labels': []}),
        ).level,
        supportNone,
      );
    });

    test('the support line shows until the person puts it away', () {
      final at = DateTime(2026);
      final e = _event('a', at).copyWith(supportLevel: supportDistress);
      expect(e.offersSupport, isTrue);
      expect(e.copyWith(supportDismissed: true).offersSupport, isFalse);
      expect(_event('b', at).offersSupport, isFalse);
      // Stored on the phone, round-trips through the database row.
      final row = LifeEvent.fromRow(e.toRow());
      expect(row.supportLevel, supportDistress);
    });
  });

  group('quiet and honored names', () {
    final events = [
      for (var i = 0; i < 4; i++)
        _event('e$i', DateTime(2026, 6, 1 + i), people: ['Sam', 'Ana']),
    ];
    final quietSam = [
      NameState(
        name: 'Sam',
        kind: 'person',
        state: nameQuiet,
        since: DateTime(2026, 3),
      ),
    ];

    test('a quiet name drops out of insights, nothing else changes', () {
      final quiet = namesIn(quietSam, nameQuiet);
      final together = computeInsights(events, ['together'], quiet: quiet);
      expect(together.single.found, isFalse); // only Ana is left
      expect(events.first.people, ['Sam', 'Ana']); // nothing deleted
    });

    test('honored names get a Remembering entry on the learning page', () {
      final view = computeLearning(
        events: events,
        memories: const [],
        now: DateTime(2026, 10, 6, 10),
        nameStates: [
          NameState(
            name: 'Ana',
            kind: 'person',
            state: nameHonored,
            since: DateTime(2026, 9),
          ),
        ],
      );
      expect(view.remembering.single.name, 'Ana');
      expect(view.remembering.single.moments, 4);
      expect(view.remembering.single.moment, contains('June 2026'));
    });

    test('whole-word matching only', () {
      expect(mentionsAny('Sam and I swam', {'sam'}), isTrue);
      expect(mentionsAny('Samantha came', {'sam'}), isFalse);
    });

    test('the AI is told who is honored, to write about them with care', () {
      final block = EventDescriber.memoryBlock(const [], honored: ['Ana']);
      expect(block, contains('honors and keeps close in memory: Ana'));
    });
  });

  group('support resources', () {
    test('the crisis line and emergency number come first by country', () {
      expect(crisisFirstFor('US').crisisLine.reach.first.target, '988');
      expect(crisisFirstFor('US').emergency, '911');
      expect(crisisFirstFor('gb').emergency, '999');
      expect(crisisFirstFor('AU').crisisLine.name, 'Lifeline');
      expect(crisisFirstFor(null).crisisLine.reach.single.kind, ReachKind.web);
    });

    test('SAMHSA, NAMI and naloxone are on the page', () {
      final names = [
        for (final s in supportSections)
          for (final r in s.resources) r.name,
      ];
      expect(names, contains('SAMHSA National Helpline'));
      expect(names, contains('NAMI HelpLine'));
      expect(names, contains('Naloxone (Narcan)'));
      expect(supportSections.first.title, 'If someone else is a danger to you');
    });

    test('calls and texts open the phone and messages', () {
      const text = Reach.text('Text HOME to 741741', '741741', 'HOME');
      expect(text.uri.toString(), 'sms:741741?body=HOME');
      expect(const Reach.call('Call 988', '988').uri.toString(), 'tel:988');
    });
  });
}
