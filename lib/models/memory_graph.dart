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

/// A stretch of the timeline the AI grouped together.
class TimelineChapter {
  final String title;
  final String summary;
  final List<String> eventIds;

  const TimelineChapter({
    required this.title,
    required this.summary,
    required this.eventIds,
  });

  Map<String, dynamic> toJson() => {
    'title': title,
    'summary': summary,
    'event_ids': eventIds,
  };

  factory TimelineChapter.fromJson(Map<String, dynamic> j) => TimelineChapter(
    title: j['title'] as String,
    summary: j['summary'] as String,
    eventIds: (j['event_ids'] as List).cast<String>(),
  );
}

class EventLink {
  final String fromEventId;
  final String toEventId;
  final String relation;

  const EventLink({
    required this.fromEventId,
    required this.toEventId,
    required this.relation,
  });

  Map<String, dynamic> toJson() => {
    'from': fromEventId,
    'to': toEventId,
    'relation': relation,
  };

  factory EventLink.fromJson(Map<String, dynamic> j) => EventLink(
    fromEventId: j['from'] as String,
    toEventId: j['to'] as String,
    relation: j['relation'] as String,
  );
}

class StoryTheme {
  final String name;
  final String description;
  final List<String> eventIds;

  const StoryTheme({
    required this.name,
    required this.description,
    required this.eventIds,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'event_ids': eventIds,
  };

  factory StoryTheme.fromJson(Map<String, dynamic> j) => StoryTheme(
    name: j['name'] as String,
    description: j['description'] as String,
    eventIds: (j['event_ids'] as List).cast<String>(),
  );
}

/// What the AI produced the last time it organised the whole timeline.
class GraphSnapshot {
  final String id;
  final DateTime createdAt;

  /// Number of described events when this snapshot was built; the next
  /// automatic build happens once enough new events are described.
  final int eventCount;
  final String model;
  final String overview;
  final List<TimelineChapter> chapters;
  final List<EventLink> links;
  final List<StoryTheme> themes;

  const GraphSnapshot({
    required this.id,
    required this.createdAt,
    required this.eventCount,
    required this.model,
    required this.overview,
    required this.chapters,
    required this.links,
    required this.themes,
  });

  Map<String, Object?> toRow() => {
    'id': id,
    'created_at': createdAt.millisecondsSinceEpoch,
    'event_count': eventCount,
    'model': model,
    'data': jsonEncode({
      'overview': overview,
      'chapters': chapters.map((c) => c.toJson()).toList(),
      'links': links.map((l) => l.toJson()).toList(),
      'themes': themes.map((t) => t.toJson()).toList(),
    }),
  };

  factory GraphSnapshot.fromRow(Map<String, Object?> row) {
    final data = jsonDecode(row['data'] as String) as Map<String, dynamic>;
    List<Map<String, dynamic>> list(String key) =>
        ((data[key] as List?) ?? const []).cast<Map<String, dynamic>>();
    return GraphSnapshot(
      id: row['id'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      eventCount: row['event_count'] as int,
      model: (row['model'] as String?) ?? '',
      overview: (data['overview'] as String?) ?? '',
      chapters: list('chapters').map(TimelineChapter.fromJson).toList(),
      links: list('links').map(EventLink.fromJson).toList(),
      themes: list('themes').map(StoryTheme.fromJson).toList(),
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

  const GraphNode({
    required this.id,
    required this.label,
    required this.kind,
    required this.provenance,
    this.eventId,
    this.time,
    this.detail = '',
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
/// Each node is marked with who supplied it.
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
