import 'dart:convert';

import 'event.dart';
import 'memory_item.dart';

/// Who supplied a piece of the graph: the user, the AI, or both.
enum Provenance { human, ai, both }

enum NodeKind { event, person, place, tag, theme, memory }

enum EdgeKind {
  /// Event → person/place/tag it mentions.
  mention,

  /// One event to the next in time.
  chronology,

  /// A connection between two events found by the AI.
  aiLink,

  /// Theme → event that belongs to it.
  theme,

  /// Memory → the event it was learned from.
  learnedFrom,
}

/// Placeholder name for the larger groupings chapters can be put into.
/// The final name hasn't been decided; change it here and it changes
/// everywhere in the app.
const groupingLabel = 'Group';
const untitledGroupName = 'Untitled group';

/// Colours the user can mark a chapter with (ARGB). Events in a coloured
/// chapter get a ring of that colour in the graph.
const chapterColors = [
  0xFFE53935,
  0xFFFB8C00,
  0xFFFDD835,
  0xFF43A047,
  0xFF00ACC1,
  0xFF1E88E5,
  0xFF8E24AA,
  0xFF6D4C41,
];

/// A user-made grouping of chapters (see [groupingLabel]).
class ChapterGroup {
  final String id;
  final String name;

  const ChapterGroup({required this.id, required this.name});

  ChapterGroup copyWith({String? name}) =>
      ChapterGroup(id: id, name: name ?? this.name);

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  factory ChapterGroup.fromJson(Map<String, dynamic> j) => ChapterGroup(
    id: j['id'] as String,
    name: (j['name'] as String?) ?? untitledGroupName,
  );
}

/// A stretch of the timeline grouped together, by the AI or the user.
class TimelineChapter {
  final String id;
  final String title;
  final String summary;
  final List<String> eventIds;

  /// User-chosen colour from [chapterColors], or null for none.
  final int? color;

  /// The [ChapterGroup] this chapter belongs to, if any.
  final String? groupId;

  /// True once the user has edited the title or summary; an AI rebuild then
  /// keeps their wording.
  final bool edited;

  const TimelineChapter({
    this.id = '',
    required this.title,
    required this.summary,
    required this.eventIds,
    this.color,
    this.groupId,
    this.edited = false,
  });

  TimelineChapter copyWith({
    String? id,
    String? title,
    String? summary,
    List<String>? eventIds,
    int? color,
    bool clearColor = false,
    String? groupId,
    bool clearGroup = false,
    bool? edited,
  }) => TimelineChapter(
    id: id ?? this.id,
    title: title ?? this.title,
    summary: summary ?? this.summary,
    eventIds: eventIds ?? this.eventIds,
    color: clearColor ? null : (color ?? this.color),
    groupId: clearGroup ? null : (groupId ?? this.groupId),
    edited: edited ?? this.edited,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'summary': summary,
    'event_ids': eventIds,
    'color': color,
    'group_id': groupId,
    'edited': edited,
  };

  factory TimelineChapter.fromJson(Map<String, dynamic> j) => TimelineChapter(
    id: (j['id'] as String?) ?? '',
    title: (j['title'] as String?) ?? '',
    summary: (j['summary'] as String?) ?? '',
    eventIds: ((j['event_ids'] as List?) ?? const []).cast<String>(),
    color: j['color'] as int?,
    groupId: j['group_id'] as String?,
    edited: (j['edited'] as bool?) ?? false,
  );
}

class EventLink {
  final String fromEventId;
  final String toEventId;
  final String relation;

  /// Added by the user; survives AI rebuilds.
  final bool manual;

  const EventLink({
    required this.fromEventId,
    required this.toEventId,
    required this.relation,
    this.manual = false,
  });

  Map<String, dynamic> toJson() => {
    'from': fromEventId,
    'to': toEventId,
    'relation': relation,
    'manual': manual,
  };

  factory EventLink.fromJson(Map<String, dynamic> j) => EventLink(
    fromEventId: j['from'] as String,
    toEventId: j['to'] as String,
    relation: (j['relation'] as String?) ?? '',
    manual: (j['manual'] as bool?) ?? false,
  );
}

class StoryTheme {
  final String name;
  final String description;
  final List<String> eventIds;

  /// Added or edited by the user; survives AI rebuilds.
  final bool manual;

  const StoryTheme({
    required this.name,
    required this.description,
    required this.eventIds,
    this.manual = false,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'event_ids': eventIds,
    'manual': manual,
  };

  factory StoryTheme.fromJson(Map<String, dynamic> j) => StoryTheme(
    name: (j['name'] as String?) ?? '',
    description: (j['description'] as String?) ?? '',
    eventIds: ((j['event_ids'] as List?) ?? const []).cast<String>(),
    manual: (j['manual'] as bool?) ?? false,
  );
}

/// The organised timeline: chapters, groups, links and themes. Built by the
/// AI and freely editable by the user.
class GraphSnapshot {
  final String id;
  final DateTime createdAt;

  /// Described events and photos when the AI last built this; the next
  /// automatic build happens once enough new photos are described.
  final int eventCount;
  final int photoCount;
  final String model;
  final String overview;
  final bool overviewEdited;
  final List<TimelineChapter> chapters;
  final List<EventLink> links;
  final List<StoryTheme> themes;
  final List<ChapterGroup> groups;

  const GraphSnapshot({
    required this.id,
    required this.createdAt,
    required this.eventCount,
    this.photoCount = 0,
    required this.model,
    required this.overview,
    this.overviewEdited = false,
    required this.chapters,
    required this.links,
    required this.themes,
    this.groups = const [],
  });

  /// An empty timeline for organising entirely by hand.
  factory GraphSnapshot.empty(String id) => GraphSnapshot(
    id: id,
    createdAt: DateTime.now(),
    eventCount: 0,
    model: '',
    overview: '',
    chapters: const [],
    links: const [],
    themes: const [],
  );

  GraphSnapshot copyWith({
    String? id,
    DateTime? createdAt,
    int? eventCount,
    int? photoCount,
    String? model,
    String? overview,
    bool? overviewEdited,
    List<TimelineChapter>? chapters,
    List<EventLink>? links,
    List<StoryTheme>? themes,
    List<ChapterGroup>? groups,
  }) => GraphSnapshot(
    id: id ?? this.id,
    createdAt: createdAt ?? this.createdAt,
    eventCount: eventCount ?? this.eventCount,
    photoCount: photoCount ?? this.photoCount,
    model: model ?? this.model,
    overview: overview ?? this.overview,
    overviewEdited: overviewEdited ?? this.overviewEdited,
    chapters: chapters ?? this.chapters,
    links: links ?? this.links,
    themes: themes ?? this.themes,
    groups: groups ?? this.groups,
  );

  TimelineChapter? chapterOf(String eventId) {
    for (final c in chapters) {
      if (c.eventIds.contains(eventId)) return c;
    }
    return null;
  }

  /// Repairs anything that could break the app: references to events that
  /// no longer exist, unknown groups or colours, blank names, duplicate or
  /// self links, and missing or duplicate chapter ids. Always safe to call.
  GraphSnapshot sanitized(Set<String> validEventIds) {
    final groupIds = <String>{};
    final cleanGroups = <ChapterGroup>[];
    for (var i = 0; i < groups.length; i++) {
      final g = groups[i];
      var id = g.id.isEmpty ? 'g$i' : g.id;
      while (groupIds.contains(id)) {
        id = '$id-$i';
      }
      groupIds.add(id);
      cleanGroups.add(
        ChapterGroup(
          id: id,
          name: g.name.trim().isEmpty ? untitledGroupName : g.name.trim(),
        ),
      );
    }

    List<String> events(List<String> ids) => [
      for (final id in ids.toSet())
        if (validEventIds.contains(id)) id,
    ];

    final chapterIds = <String>{};
    final cleanChapters = <TimelineChapter>[];
    for (var i = 0; i < chapters.length; i++) {
      final c = chapters[i];
      var id = c.id.isEmpty ? 'c$i' : c.id;
      while (chapterIds.contains(id)) {
        id = '$id-$i';
      }
      chapterIds.add(id);
      cleanChapters.add(
        TimelineChapter(
          id: id,
          title: c.title.trim().isEmpty ? 'Untitled chapter' : c.title.trim(),
          summary: c.summary.trim(),
          eventIds: events(c.eventIds),
          color: chapterColors.contains(c.color) ? c.color : null,
          groupId: groupIds.contains(c.groupId) ? c.groupId : null,
          edited: c.edited,
        ),
      );
    }

    final seenLinks = <String>{};
    final cleanLinks = <EventLink>[];
    for (final l in links) {
      final key = '${l.fromEventId}>${l.toEventId}';
      if (l.fromEventId == l.toEventId ||
          !validEventIds.contains(l.fromEventId) ||
          !validEventIds.contains(l.toEventId) ||
          !seenLinks.add(key)) {
        continue;
      }
      cleanLinks.add(
        EventLink(
          fromEventId: l.fromEventId,
          toEventId: l.toEventId,
          relation: l.relation.trim().isEmpty ? 'related' : l.relation.trim(),
          manual: l.manual,
        ),
      );
    }

    final seenThemes = <String>{};
    final cleanThemes = <StoryTheme>[];
    for (final t in themes) {
      final name = t.name.trim().isEmpty ? 'Untitled theme' : t.name.trim();
      if (!seenThemes.add(name.toLowerCase())) continue;
      cleanThemes.add(
        StoryTheme(
          name: name,
          description: t.description.trim(),
          eventIds: events(t.eventIds),
          manual: t.manual,
        ),
      );
    }

    return copyWith(
      overview: overview.trim(),
      groups: cleanGroups,
      chapters: cleanChapters,
      links: cleanLinks,
      themes: cleanThemes,
    );
  }

  /// Combines a fresh AI build with the user's edits to [previous]:
  /// groups, chapter colours, group membership, edited chapter wording, an
  /// edited overview, and the user's own links and themes are all kept.
  /// A fresh chapter inherits from the previous chapter it overlaps most.
  static GraphSnapshot mergeRebuild(
    GraphSnapshot? previous,
    GraphSnapshot fresh,
  ) {
    if (previous == null) return fresh;
    final used = <String>{};
    final chapters = <TimelineChapter>[];
    for (final c in fresh.chapters) {
      TimelineChapter? best;
      var bestScore = 0.0;
      final a = c.eventIds.toSet();
      for (final old in previous.chapters) {
        if (used.contains(old.id)) continue;
        final b = old.eventIds.toSet();
        final union = a.union(b).length;
        final score = union == 0 ? 0.0 : a.intersection(b).length / union;
        if (score > bestScore) {
          bestScore = score;
          best = old;
        }
      }
      if (best != null && bestScore >= 0.5) {
        used.add(best.id);
        chapters.add(
          c.copyWith(
            id: best.id,
            color: best.color,
            groupId: best.groupId,
            title: best.edited ? best.title : null,
            summary: best.edited ? best.summary : null,
            edited: best.edited,
          ),
        );
      } else {
        chapters.add(c);
      }
    }

    final links = [...fresh.links, ...previous.links.where((l) => l.manual)];
    final manualThemes = previous.themes.where((t) => t.manual).toList();
    final manualNames = manualThemes.map((t) => t.name.toLowerCase()).toSet();
    final themes = [
      ...fresh.themes.where((t) => !manualNames.contains(t.name.toLowerCase())),
      ...manualThemes,
    ];

    return fresh.copyWith(
      overview: previous.overviewEdited ? previous.overview : fresh.overview,
      overviewEdited: previous.overviewEdited,
      chapters: chapters,
      links: links,
      themes: themes,
      groups: previous.groups,
    );
  }

  Map<String, Object?> toRow() => {
    'id': id,
    'created_at': createdAt.millisecondsSinceEpoch,
    'event_count': eventCount,
    'model': model,
    'data': jsonEncode({
      'photo_count': photoCount,
      'overview': overview,
      'overview_edited': overviewEdited,
      'chapters': chapters.map((c) => c.toJson()).toList(),
      'links': links.map((l) => l.toJson()).toList(),
      'themes': themes.map((t) => t.toJson()).toList(),
      'groups': groups.map((g) => g.toJson()).toList(),
    }),
  };

  factory GraphSnapshot.fromRow(Map<String, Object?> row) {
    final data = jsonDecode(row['data'] as String) as Map<String, dynamic>;
    List<Map<String, dynamic>> list(String key) =>
        ((data[key] as List?) ?? const []).cast<Map<String, dynamic>>();
    final chapters = list('chapters').map(TimelineChapter.fromJson).toList();
    return GraphSnapshot(
      id: row['id'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      eventCount: row['event_count'] as int,
      photoCount: (data['photo_count'] as int?) ?? 0,
      model: (row['model'] as String?) ?? '',
      overview: (data['overview'] as String?) ?? '',
      overviewEdited: (data['overview_edited'] as bool?) ?? false,
      chapters: [
        // Snapshots from before chapters had ids get stable ones.
        for (var i = 0; i < chapters.length; i++)
          chapters[i].id.isEmpty
              ? chapters[i].copyWith(id: 'c$i')
              : chapters[i],
      ],
      links: list('links').map(EventLink.fromJson).toList(),
      themes: list('themes').map(StoryTheme.fromJson).toList(),
      groups: list('groups').map(ChapterGroup.fromJson).toList(),
    );
  }
}

class GraphNode {
  final String id;
  final String label;
  final NodeKind kind;
  final Provenance provenance;

  /// Set for event nodes, so the UI can open the event.
  final String? eventId;

  /// Event time, used to lay events out left-to-right like a timeline.
  final DateTime? time;
  final String detail;

  /// Ring colour the user chose for this event's chapter, if any.
  final int? ringColor;

  const GraphNode({
    required this.id,
    required this.label,
    required this.kind,
    required this.provenance,
    this.eventId,
    this.time,
    this.detail = '',
    this.ringColor,
  });
}

class GraphEdge {
  final String from;
  final String to;
  final EdgeKind kind;
  final String label;

  const GraphEdge(this.from, this.to, this.kind, [this.label = '']);
}

class GraphData {
  final List<GraphNode> nodes;
  final List<GraphEdge> edges;

  const GraphData(this.nodes, this.edges);

  GraphNode? node(String id) {
    for (final n in nodes) {
      if (n.id == id) return n;
    }
    return null;
  }
}

String _key(String s) => s.toLowerCase().trim();

/// Assembles the knowledge graph from what the user and the AI have recorded.
///
/// Events, people, places and tags come from each event; links, themes come
/// from the AI's [snapshot] (if any); memories come from long-term memory.
/// Each node is marked with who supplied it, and events carry the colour of
/// their chapter when the user has picked one.
GraphData buildGraph({
  required List<LifeEvent> events,
  required List<MemoryItem> memories,
  GraphSnapshot? snapshot,
}) {
  final described = events.where((e) => e.hasAccount).toList()
    ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
  final nodes = <String, GraphNode>{};
  final edges = <GraphEdge>[];

  final userText = [
    for (final e in described) e.notes,
    for (final e in described) e.title,
    for (final e in described) e.location,
    for (final m in memories.where((m) => m.source == 'user')) m.content,
  ].join('\n').toLowerCase();

  // A label is human-supplied when the user wrote it somewhere themselves.
  Provenance labelSource(String label) =>
      userText.contains(_key(label)) ? Provenance.human : Provenance.ai;

  void addLabel(LifeEvent e, String label, NodeKind kind) {
    final id = '${kind.name}:${_key(label)}';
    nodes.putIfAbsent(
      id,
      () => GraphNode(
        id: id,
        label: label,
        kind: kind,
        provenance: labelSource(label),
      ),
    );
    edges.add(GraphEdge('event:${e.id}', id, EdgeKind.mention));
  }

  for (final e in described) {
    nodes['event:${e.id}'] = GraphNode(
      id: 'event:${e.id}',
      label: e.title.isEmpty ? 'Untitled' : e.title,
      kind: NodeKind.event,
      // Photos and notes from the user, the account from the AI.
      provenance: Provenance.both,
      eventId: e.id,
      time: e.occurredAt,
      detail: e.summary,
      ringColor: snapshot?.chapterOf(e.id)?.color,
    );
    for (final p in e.people) {
      addLabel(e, p, NodeKind.person);
    }
    for (final p in e.places) {
      addLabel(e, p, NodeKind.place);
    }
    for (final t in e.tags) {
      addLabel(e, t, NodeKind.tag);
    }
  }

  for (var i = 1; i < described.length; i++) {
    edges.add(
      GraphEdge(
        'event:${described[i - 1].id}',
        'event:${described[i].id}',
        EdgeKind.chronology,
      ),
    );
  }

  for (final m in memories) {
    final id = 'memory:${m.id}';
    nodes[id] = GraphNode(
      id: id,
      label: m.content.length > 40
          ? '${m.content.substring(0, 40)}…'
          : m.content,
      kind: NodeKind.memory,
      provenance: m.source == 'ai' ? Provenance.ai : Provenance.human,
      detail: m.content,
    );
    if (m.eventId != null && nodes.containsKey('event:${m.eventId}')) {
      edges.add(GraphEdge(id, 'event:${m.eventId}', EdgeKind.learnedFrom));
    }
    // Tie memories to the people/places they talk about.
    final text = m.content.toLowerCase();
    for (final n in nodes.values.toList()) {
      if ((n.kind == NodeKind.person || n.kind == NodeKind.place) &&
          n.label.length > 2 &&
          text.contains(_key(n.label))) {
        edges.add(GraphEdge(id, n.id, EdgeKind.mention));
      }
    }
  }

  if (snapshot != null) {
    for (final link in snapshot.links) {
      final a = 'event:${link.fromEventId}', b = 'event:${link.toEventId}';
      if (nodes.containsKey(a) && nodes.containsKey(b) && a != b) {
        edges.add(GraphEdge(a, b, EdgeKind.aiLink, link.relation));
      }
    }
    for (final theme in snapshot.themes) {
      final id = 'theme:${_key(theme.name)}';
      nodes[id] = GraphNode(
        id: id,
        label: theme.name,
        kind: NodeKind.theme,
        provenance: Provenance.ai,
        detail: theme.description,
      );
      for (final eventId in theme.eventIds) {
        if (nodes.containsKey('event:$eventId')) {
          edges.add(GraphEdge(id, 'event:$eventId', EdgeKind.theme));
        }
      }
    }
  }

  return GraphData(nodes.values.toList(), edges);
}
