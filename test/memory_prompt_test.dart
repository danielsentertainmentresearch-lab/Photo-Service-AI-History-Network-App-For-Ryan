import 'package:eventlens/models/learned_point.dart';
import 'package:eventlens/models/memory_prompt.dart';
import 'package:flutter_test/flutter_test.dart';

LearnedPoint _point(
  String id,
  String content, {
  List<String> eventIds = const [],
  String status = pointActive,
  String kind = 'person',
  String source = 'ai',
  DateTime? created,
}) => LearnedPoint(
  id: id,
  pointId: id,
  version: 1,
  kind: kind,
  content: content,
  sentiment: const Sentiment(
    polarity: 'positive',
    intensity: 'medium',
    source: dreamSentiment,
  ),
  source: source,
  eventIds: eventIds,
  status: status,
  createdAt: created ?? DateTime(2026, 9, 1),
);

List<String> _contents(String block) => [
  for (final m in RegExp(r'cont: "([^"]*)"').allMatches(block)) m.group(1)!,
];

void main() {
  final dates = {
    'e-old': DateTime(2026, 1, 5),
    'e-mid': DateTime(2026, 6, 5),
    'e-new': DateTime(2026, 10, 5),
  };

  group('Memory for prompts (2.3)', () {
    test('renders the compact format with the dream state', () {
      final block = MemoryPrompt.render(
        points: [
          _point(
            'a',
            'Ana wears red',
            eventIds: ['e-new', 'e-old'],
            source: 'answer',
          ),
        ],
        dream: DreamState(
          id: 'd',
          version: 2,
          foundationStatements: const ['Ana is the closest friend'],
          themes: const ['Growth'],
          eventIds: const [],
          createdAt: DateTime(2026, 10, 1),
        ),
        eventDates: dates,
      );
      expect(
        block,
        'MEMORY_V8:\n'
        '[DREAM: Ana is the closest friend. Themes: Growth.]\n'
        '[ACTIVE:\n'
        '- {kind: person, sent: pos:med, cont: "Ana wears red", src: answer, '
        'ev: [2026-01-05, 2026-10-05]}\n'
        ']',
      );
    });

    test('empty memory reads as none', () {
      expect(
        MemoryPrompt.render(points: const []),
        'MEMORY_V8:\n[DREAM: none yet]\n[ACTIVE: none]',
      );
    });

    test('shows only active points', () {
      final block = MemoryPrompt.render(
        points: [
          _point('a', 'Active one'),
          _point('b', 'Archived one', status: pointArchived),
          _point('c', 'Retired one', status: pointRetired),
        ],
      );
      expect(_contents(block), ['Active one']);
    });

    test(
      'orders by request names, then recent evidence, then evidence count',
      () {
        final block = MemoryPrompt.render(
          points: [
            _point('old', 'Old evidence', eventIds: ['e-old']),
            _point('none', 'No evidence'),
            _point('two', 'Two pieces', eventIds: ['e-mid', 'e-old']),
            _point('one', 'One piece', eventIds: ['e-mid']),
            _point('ana', 'Ana likes the lake', eventIds: ['e-old']),
            _point('new', 'Newest evidence', eventIds: ['e-new']),
          ],
          requestNames: const ['Ana'],
          eventDates: dates,
        );
        expect(_contents(block), [
          'Ana likes the lake',
          'Newest evidence',
          'Two pieces',
          'One piece',
          'Old evidence',
          'No evidence',
        ]);
      },
    );

    test('keeps Quiet names out unless the request involves them', () {
      final points = [
        _point('ben', 'Ben coaches on Sundays'),
        _point('ana', 'Ana likes the lake'),
      ];
      final dream = DreamState(
        id: 'd',
        version: 1,
        foundationStatements: const ['Ben was a mentor', 'Ana is close'],
        themes: const [],
        eventIds: const [],
        createdAt: DateTime(2026, 9, 1),
      );
      final quiet = MemoryPrompt.render(
        points: points,
        dream: dream,
        quietNames: const {'ben'},
      );
      expect(_contents(quiet), ['Ana likes the lake']);
      expect(quiet, isNot(contains('Ben')));

      final involved = MemoryPrompt.render(
        points: points,
        dream: dream,
        quietNames: const {'ben'},
        requestNames: const ['Ben'],
      );
      expect(_contents(involved).first, 'Ben coaches on Sundays');
      expect(involved, contains('Ben was a mentor'));
    });

    test('marks Honored names', () {
      final block = MemoryPrompt.render(
        points: [_point('g', 'Grandma Rose taught me to bake')],
        honoredNames: const {'grandma rose'},
      );
      expect(block, endsWith('ev: []} [Honored]\n]'));
    });

    test('stays within 20 points and 2000 characters', () {
      final many = [
        for (var i = 0; i < 40; i++)
          _point('p$i', 'Point number $i about something short'),
      ];
      expect(
        _contents(MemoryPrompt.render(points: many)),
        hasLength(MemoryPrompt.maxPoints),
      );

      final long = [
        for (var i = 0; i < 40; i++) _point('p$i', '${'x' * 110} $i'),
      ];
      final block = MemoryPrompt.render(points: long);
      final active = block.substring(block.indexOf('[ACTIVE:'));
      expect(active.length, lessThanOrEqualTo(MemoryPrompt.maxChars + 20));
      expect(_contents(block).length, lessThan(MemoryPrompt.maxPoints));
    });
  });
}
