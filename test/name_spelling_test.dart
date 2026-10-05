import 'package:eventlens/models/event.dart';
import 'package:eventlens/models/memory_item.dart';
import 'package:eventlens/models/name_spelling.dart';
import 'package:flutter_test/flutter_test.dart';

LifeEvent _event(String id, {List<String> people = const []}) {
  final at = DateTime(2026, 7, 4);
  return LifeEvent(
    id: id,
    title: id,
    notes: '',
    location: '',
    occurredAt: at,
    createdAt: at,
    updatedAt: at,
    people: people,
  );
}

void main() {
  test('only spelling fixes are allowed', () {
    expect(isSpellingFix('Jon', 'John'), isTrue);
    expect(isSpellingFix('sam', 'Sam'), isTrue); // capitals
    expect(isSpellingFix('Fallen Leaf Lak', 'Fallen Leaf Lake'), isTrue);
    expect(isSpellingFix('Sam', 'Jordan'), isFalse); // a different name
    expect(isSpellingFix('Sam', 'Sam Smith'), isFalse); // adds a word
    expect(isSpellingFix('Sam', 'Sam'), isFalse); // no change
    expect(isSpellingFix('Sam', ''), isFalse);
    expect(isSpellingFix('Katherine', 'Catherine'), isTrue);
    expect(isSpellingFix('Katherine', 'Kat'), isFalse);
  });

  test('names come from events and answers, most used first', () {
    final names = knownNames(
      [
        _event('a', people: ['John', 'Ana']),
        _event('b', people: ['John']),
        _event('c', people: ['Jon']),
      ],
      [
        MemoryItem(
          id: 'm',
          kind: 'person',
          content: 'Lee: a man in a hat in "a"',
          source: answerSource,
          createdAt: DateTime(2026),
        ),
      ],
    );
    expect(names.first.name, 'John');
    expect(names.first.events, 2);
    expect(names.map((n) => n.name), containsAll(['Ana', 'Jon', 'Lee']));
  });

  test('a rare near-twin of a common name is suggested as a typo', () {
    final s = spellingSuggestions(const [
      KnownName('John', 'person', 6),
      KnownName('Jon', 'person', 1),
      KnownName('Ana', 'person', 3),
      KnownName('Jon', 'place', 1),
    ]);
    expect(s, hasLength(1));
    expect((s.single.from, s.single.to, s.single.kind), ('Jon', 'John', 'person'));
  });

  test('names are replaced as whole words only', () {
    expect(
      replaceName('Jon met Jonas and jon. Jon!', 'Jon', 'John'),
      'John met Jonas and jon. John!',
    );
    expect(replaceName('', 'Jon', 'John'), '');
  });
}
