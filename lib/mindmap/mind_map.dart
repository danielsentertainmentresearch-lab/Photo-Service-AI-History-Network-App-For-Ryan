import 'dart:math';

import '../models/memory_graph.dart';

/// The centre of the whole map: the person's story, branching into
/// chapters, themes, people and places.
const storyFocus = 'story';

/// Members shown per group before a "more" branch takes over.
const maxPerGroup = 8;

String chapterFocus(String chapterId) => 'chapter:$chapterId';

enum BranchKind { story, group, chapter, node, more }

/// One branch of the mind map as currently opened.
class MindBranch {
  /// Path from the centre; unique within one map.
  final String key;
  final String label;
  final BranchKind kind;

  /// Set on node branches and on groups of nodes.
  final NodeKind? nodeKind;

  /// What the branch stands for: [storyFocus], a [chapterFocus] id or a
  /// graph node id. Null for groups and "more" branches.
  final String? target;

  /// The relation that led here ("same summit", "next event") or a summary.
  final String detail;
  final bool canOpen;
  final bool isOpen;
  final List<MindBranch> children;

  const MindBranch({
    required this.key,
    required this.label,
    required this.kind,
    this.nodeKind,
    this.target,
    this.detail = '',
    this.canOpen = false,
    this.isOpen = false,
    this.children = const [],
  });

  int get leaves =>
      children.isEmpty ? 1 : children.fold(0, (sum, c) => sum + c.leaves);
}

enum _Category { chapters, events, themes, people, places, tags, memories }

const _categoryLabels = {
  _Category.chapters: 'Chapters',
  _Category.events: 'Events',
  _Category.themes: 'Themes',
  _Category.people: 'People',
  _Category.places: 'Places',
  _Category.tags: 'Tags',
  _Category.memories: 'Memories',
};

_Category _categoryOf(NodeKind kind) => switch (kind) {
  NodeKind.event => _Category.events,
  NodeKind.theme => _Category.themes,
  NodeKind.person => _Category.people,
  NodeKind.place => _Category.places,
  NodeKind.tag => _Category.tags,
  NodeKind.memory => _Category.memories,
};

class _Neighbour {
  final String id;
  final String relation;

  const _Neighbour(this.id, this.relation);
}

/// Everything the mind map needs to branch out from any idea, built once
/// per graph. Read-only: it never changes what the AI or the user wrote.
class MindMapIndex {
  final GraphData graph;
  final GraphSnapshot? snapshot;
  final Map<String, GraphNode> _nodes;
  final Map<String, TimelineChapter> _chapters;
  final Map<String, String> _chapterOfEvent;
  final Map<String, Map<String, String>> _adjacent;

  MindMapIndex._(
    this.graph,
    this.snapshot,
    this._nodes,
    this._chapters,
    this._chapterOfEvent,
    this._adjacent,
  );

  factory MindMapIndex(GraphData graph, GraphSnapshot? snapshot) {
    final nodes = {for (final n in graph.nodes) n.id: n};
    final adjacent = <String, Map<String, String>>{};
    final strength = <String, int>{};
    // When two events are linked twice, the AI's relation ("same summit")
    // says more than "next event".
    void link(String a, String b, String relation, int rank) {
      final pair = '$a>$b';
      if ((strength[pair] ?? -1) >= rank) return;
      strength[pair] = rank;
      adjacent.putIfAbsent(a, () => {})[b] = relation;
    }

    for (final e in graph.edges) {
      if (!nodes.containsKey(e.from) || !nodes.containsKey(e.to)) continue;
      final (forward, backward, rank) = switch (e.kind) {
        EdgeKind.aiLink => (e.label, e.label, 2),
        EdgeKind.chronology => ('next event', 'previous event', 1),
        _ => ('', '', 0),
      };
      link(e.from, e.to, forward, rank);
      link(e.to, e.from, backward, rank);
    }

    final chapters = <String, TimelineChapter>{};
    final chapterOfEvent = <String, String>{};
    for (final c in snapshot?.chapters ?? const <TimelineChapter>[]) {
      final events = c.eventIds.where((id) => nodes.containsKey('event:$id'));
      if (events.isEmpty) continue;
      chapters[c.id] = c;
      for (final id in events) {
        chapterOfEvent.putIfAbsent('event:$id', () => chapterFocus(c.id));
      }
    }
    return MindMapIndex._(
      graph,
      snapshot,
      nodes,
      chapters,
      chapterOfEvent,
      adjacent,
    );
  }

  /// Whether [focus] still exists, e.g. after an event was deleted.
  bool has(String focus) =>
      focus == storyFocus ||
      _nodes.containsKey(focus) ||
      _chapters.containsKey(_chapterId(focus));

  GraphNode? node(String id) => _nodes[id];

  TimelineChapter? chapter(String focus) => _chapters[_chapterId(focus)];

  String labelOf(String focus) {
    if (focus == storyFocus) return 'Your story';
    final c = chapter(focus);
    if (c != null) return c.title;
    return _nodes[focus]?.label ?? '';
  }

  static String? _chapterId(String focus) =>
      focus.startsWith('chapter:') ? focus.substring(8) : null;

  int _degree(String id) => _adjacent[id]?.length ?? 0;

  /// Ideas that branch out of [focus], grouped and ordered.
  Map<_Category, List<_Neighbour>> _branchesOf(String focus) {
    final out = <_Category, List<_Neighbour>>{};
    void add(_Category c, String id, [String relation = '']) =>
        out.putIfAbsent(c, () => []).add(_Neighbour(id, relation));

    if (focus == storyFocus) {
      for (final c in _chapters.keys) {
        add(_Category.chapters, chapterFocus(c));
      }
      for (final n in graph.nodes) {
        switch (n.kind) {
          case NodeKind.theme:
            add(_Category.themes, n.id);
          case NodeKind.person:
            add(_Category.people, n.id);
          case NodeKind.place:
            add(_Category.places, n.id);
          case NodeKind.event when _chapters.isEmpty:
            add(_Category.events, n.id);
          default:
            break;
        }
      }
    } else if (chapter(focus) case final c?) {
      for (final id in c.eventIds) {
        if (_nodes.containsKey('event:$id')) add(_Category.events, 'event:$id');
      }
    } else {
      final inChapter = _chapterOfEvent[focus];
      if (inChapter != null) add(_Category.chapters, inChapter);
      for (final MapEntry(key: id, value: relation)
          in (_adjacent[focus] ?? const <String, String>{}).entries) {
        add(_categoryOf(_nodes[id]!.kind), id, relation);
      }
    }

    for (final MapEntry(key: category, value: list) in out.entries) {
      if (category == _Category.chapters) continue;
      if (category == _Category.events) {
        if (focus.startsWith('chapter:')) continue;
        list.sort(
          (a, b) => (_nodes[a.id]!.time ?? DateTime(0)).compareTo(
            _nodes[b.id]!.time ?? DateTime(0),
          ),
        );
      } else {
        list.sort((a, b) {
          final byDegree = _degree(b.id).compareTo(_degree(a.id));
          return byDegree != 0
              ? byDegree
              : _nodes[a.id]!.label.toLowerCase().compareTo(
                  _nodes[b.id]!.label.toLowerCase(),
                );
        });
      }
    }
    return out;
  }

  bool _hasBranches(String focus, Set<String> path) =>
      _branchesOf(focus).values
          .any((list) => list.any((n) => !path.contains(n.id)));

  /// The map as opened: [focus] in the centre; the centre's branches are
  /// always open, deeper ones only when their key is in [open]. Groups in
  /// [showAll] list every member instead of the first [maxPerGroup].
  /// An idea never branches back into one already on its path.
  MindBranch build({
    String focus = storyFocus,
    Set<String> open = const {},
    Set<String> showAll = const {},
  }) {
    final centre = has(focus) ? focus : storyFocus;
    return _branch(
      key: centre,
      target: centre,
      relation: '',
      path: {centre},
      open: open,
      showAll: showAll,
      isCentre: true,
    );
  }

  MindBranch _branch({
    required String key,
    required String target,
    required String relation,
    required Set<String> path,
    required Set<String> open,
    required Set<String> showAll,
    bool isCentre = false,
  }) {
    final node = _nodes[target];
    final c = chapter(target);
    final kind = target == storyFocus
        ? BranchKind.story
        : c != null
        ? BranchKind.chapter
        : BranchKind.node;
    final detail = relation.isNotEmpty
        ? relation
        : kind == BranchKind.story
        ? snapshot?.overview ?? ''
        : c?.summary ?? node?.detail ?? '';
    final canOpen = _hasBranches(target, path);
    final isOpen = canOpen && (isCentre || open.contains(key));

    final children = <MindBranch>[];
    if (isOpen) {
      final groups = _branchesOf(target);
      final useGroups = groups.length > 1;
      for (final category in _Category.values) {
        final members = [
          for (final n in groups[category] ?? const <_Neighbour>[])
            if (!path.contains(n.id)) n,
        ];
        if (members.isEmpty) continue;
        final groupKey = '$key/${category.name}';
        final shown = showAll.contains(groupKey)
            ? members
            : members.take(maxPerGroup).toList();
        final parentKey = useGroups ? groupKey : key;
        final branches = [
          for (final n in shown)
            _branch(
              key: '$parentKey/${n.id}',
              target: n.id,
              relation: n.relation,
              path: {...path, n.id},
              open: open,
              showAll: showAll,
            ),
          if (shown.length < members.length)
            MindBranch(
              key: '$groupKey/+more',
              label: '${members.length - shown.length} more',
              kind: BranchKind.more,
              target: groupKey,
            ),
        ];
        if (useGroups) {
          children.add(
            MindBranch(
              key: groupKey,
              label: _categoryLabels[category]!,
              kind: BranchKind.group,
              nodeKind: category == _Category.chapters
                  ? null
                  : _nodes[members.first.id]!.kind,
              children: branches,
            ),
          );
        } else {
          children.addAll(branches);
        }
      }
    }

    return MindBranch(
      key: key,
      label: labelOf(target),
      kind: kind,
      nodeKind: node?.kind,
      target: target,
      detail: detail,
      canOpen: canOpen,
      isOpen: isOpen,
      children: children,
    );
  }
}

/// A branch placed on the page.
class PlacedBranch {
  final MindBranch branch;
  final double x;
  final double y;
  final int depth;
  final String? parentKey;

  /// Which of the centre's branches this one grows from, for colouring
  /// whole limbs alike, as in a hand-drawn mind map. -1 for the centre.
  final int limb;

  const PlacedBranch(
    this.branch,
    this.x,
    this.y,
    this.depth,
    this.parentKey,
    this.limb,
  );
}

/// Radial layout: the centre at (0, 0), each ring of branches further out,
/// and every branch given a slice of the circle in proportion to the
/// branches beyond it. Rings widen when there are many leaves, so labels
/// on the outer ring keep at least [leafSpacing] apart.
List<PlacedBranch> layoutMindMap(
  MindBranch root, {
  double firstRing = 150,
  double ringGap = 170,
  double leafSpacing = 64,
}) {
  var maxDepth = 0;
  void measure(MindBranch b, int depth) {
    maxDepth = max(maxDepth, depth);
    for (final c in b.children) {
      measure(c, depth + 1);
    }
  }

  measure(root, 0);
  double ring(int depth) => depth == 0 ? 0 : firstRing + (depth - 1) * ringGap;
  final outer = ring(max(maxDepth, 1));
  final needed = root.leaves * leafSpacing / (2 * pi);
  final scale = max(1.0, needed / outer);

  final placed = <PlacedBranch>[];
  void place(
    MindBranch b,
    int depth,
    double from,
    double to,
    String? parent,
    int limb,
  ) {
    final angle = (from + to) / 2;
    final r = ring(depth) * scale;
    placed.add(
      PlacedBranch(b, r * cos(angle), r * sin(angle), depth, parent, limb),
    );
    var start = from;
    final total = b.leaves;
    for (var i = 0; i < b.children.length; i++) {
      final c = b.children[i];
      final span = (to - from) * c.leaves / total;
      place(c, depth + 1, start, start + span, b.key, depth == 0 ? i : limb);
      start += span;
    }
  }

  place(root, 0, -pi / 2, 3 * pi / 2, null, -1);
  return placed;
}
