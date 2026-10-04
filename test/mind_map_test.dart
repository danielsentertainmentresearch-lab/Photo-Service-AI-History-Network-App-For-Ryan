import 'dart:math';

import 'package:eventlens/mindmap/mind_map.dart';
import 'package:eventlens/models/event.dart';
import 'package:eventlens/models/memory_graph.dart';
import 'package:eventlens/models/memory_item.dart';
import 'package:flutter_test/flutter_test.dart';

LifeEvent _event(
  String id,
  int day, {
  List<String> people = const [],
  List<String> places = const [],
}) {
  final at = DateTime(2026, 6, day);
  return LifeEvent(
    id: id,
    title: 'Event $id',
    notes: '',
    location: '',
    occurredAt: at,
    createdAt: at,
    updatedAt: at,
    summary: 'Summary of $id.',
    description: 'Account of $id.',
    people: people,
    places: places,
    status: EventStatus.described,
  );
}

GraphSnapshot _snapshot({
  List<TimelineChapter> chapters = const [],
  List<EventLink> links = const [],
  List<StoryTheme> themes = const [],
}) => GraphSnapshot(
  id: 'g',
  createdAt: DateTime(2026, 7, 1),
  eventCount: 3,
  model: 'm',
  overview: 'A summer.',
  chapters: chapters,
  links: links,
  themes: themes,
);

List<String> _labels(MindBranch b) => [for (final c in b.children) c.label];

MindBranch _child(MindBranch b, String label) =>
    b.children.firstWhere((c) => c.label == label);

void main() {
  final events = [
    _event('a', 1, people: ['Sam'], places: ['Lake']),
    _event('b', 2, people: ['Sam', 'Ana']),
    _event('c', 3, places: ['Lake']),
  ];
  final snapshot = _snapshot(
    chapters: const [
      TimelineChapter(
        id: 'c1',
        title: 'Early June',
        summary: 'Two days.',
        eventIds: ['a', 'b'],
      ),
      TimelineChapter(
        id: 'c2',
        title: 'Back at the lake',
        summary: 'One day.',
        eventIds: ['c'],
      ),
    ],
    links: const [
      EventLink(fromEventId: 'a', toEventId: 'c', relation: 'same lake'),
      EventLink(fromEventId: 'a', toEventId: 'b', relation: 'the next morning'),
    ],
    themes: const [
      StoryTheme(name: 'Water', description: 'Swims.', eventIds: ['a', 'c']),
    ],
  );
  final index = MindMapIndex(
    buildGraph(events: events, memories: const [], snapshot: snapshot),
    snapshot,
  );

  group('mind map', () {
    test('your story branches into chapters, themes, people and places', () {
      final root = index.build();
      expect(root.kind, BranchKind.story);
      expect(root.isOpen, isTrue);
      expect(root.detail, 'A summer.');
      expect(_labels(root), ['Chapters', 'Themes', 'People', 'Places']);
      expect(_labels(_child(root, 'Chapters')), [
        'Early June',
        'Back at the lake',
      ]);
      // Most connected first: Sam is on two events, Ana on one.
      expect(_labels(_child(root, 'People')), ['Sam', 'Ana']);
      // Deeper branches stay closed until opened.
      final sam = _child(_child(root, 'People'), 'Sam');
      expect(sam.canOpen, isTrue);
      expect(sam.isOpen, isFalse);
      expect(sam.children, isEmpty);
    });

    test('opening a branch shows what grows from it, never its own path', () {
      final closed = index.build();
      final samKey = _child(_child(closed, 'People'), 'Sam').key;
      final root = index.build(open: {samKey});
      final sam = _child(_child(root, 'People'), 'Sam');
      expect(sam.isOpen, isTrue);
      // Only one kind of idea grows from Sam, so no group label.
      expect(_labels(sam), ['Event a', 'Event b']);
    });

    test('an event branches into its chapter, related events and people', () {
      final root = index.build(focus: 'event:a');
      expect(root.label, 'Event a');
      expect(_labels(root), [
        'Chapters',
        'Events',
        'Themes',
        'People',
        'Places',
      ]);
      expect(_labels(_child(root, 'Chapters')), ['Early June']);
      final related = _child(root, 'Events');
      // The AI's relation wins over "next event" for the same pair.
      expect(
        {for (final c in related.children) c.label: c.detail},
        {'Event b': 'the next morning', 'Event c': 'same lake'},
      );
    });

    test('a chapter branches into its events', () {
      final root = index.build(focus: chapterFocus('c1'));
      expect(root.kind, BranchKind.chapter);
      expect(root.detail, 'Two days.');
      expect(_labels(root), ['Event a', 'Event b']);
    });

    test('a missing centre falls back to your story', () {
      expect(index.has('event:gone'), isFalse);
      expect(index.build(focus: 'event:gone').kind, BranchKind.story);
    });

    test('long groups show a "more" branch until shown in full', () {
      final many = [
        for (var i = 1; i <= maxPerGroup + 3; i++)
          _event('e$i', i, people: ['Person $i']),
      ];
      final big = MindMapIndex(
        buildGraph(events: many, memories: const <MemoryItem>[]),
        null,
      );
      final root = big.build();
      // Without chapters the story branches into events directly.
      final people = _child(root, 'People');
      expect(people.children.length, maxPerGroup + 1);
      final more = people.children.last;
      expect(more.kind, BranchKind.more);
      expect(more.label, '3 more');
      final full = big.build(showAll: {more.target!});
      expect(_child(full, 'People').children.length, maxPerGroup + 3);
    });

    test('layout puts the centre in the middle and rings outward', () {
      final root = index.build(
        open: {_child(_child(index.build(), 'People'), 'Sam').key},
      );
      final placed = layoutMindMap(root);
      expect(placed.length, greaterThan(8));
      expect(placed.first.x, 0);
      expect(placed.first.y, 0);
      double r(PlacedBranch p) => sqrt(p.x * p.x + p.y * p.y);
      for (final p in placed.skip(1)) {
        final parent = placed.firstWhere((q) => q.branch.key == p.parentKey);
        expect(r(p), greaterThan(r(parent)));
        expect(p.depth, parent.depth + 1);
      }
      // Branches on one ring never sit on top of each other.
      for (final p in placed) {
        for (final q in placed) {
          if (identical(p, q) || p.depth != q.depth) continue;
          final d = sqrt(pow(p.x - q.x, 2) + pow(p.y - q.y, 2));
          expect(d, greaterThan(30), reason: '${p.branch.key} ${q.branch.key}');
        }
      }
    });

    test('every limb keeps the index of the branch it grows from', () {
      final root = index.build(
        open: {_child(_child(index.build(), 'People'), 'Sam').key},
      );
      final placed = layoutMindMap(root);
      final limbOf = {
        for (final p in placed.where((p) => p.depth == 1)) p.branch.key: p.limb,
      };
      for (final p in placed.where((p) => p.depth > 1)) {
        final top = p.branch.key.split('/').take(2).join('/');
        expect(p.limb, limbOf[top]);
      }
    });
  });
}
