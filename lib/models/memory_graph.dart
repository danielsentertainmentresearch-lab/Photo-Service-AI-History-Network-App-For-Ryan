import 'dart:convert';

import 'event.dart';
import 'memory_item.dart';
import 'ring_palette.dart';

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

/// User-made collection of chapters, titled by the user.
const bookLabel = 'Book';
const untitledBookTitle = 'Untitled book';

class Book {
  final String id;
  final String title;

  const Book({required this.id, required this.title});

  Book copyWith({String? title}) => Book(id: id, title: title ?? this.title);

  Map<String, dynamic> toJson() => {'id': id, 'title': title};

  factory Book.fromJson(Map<String, dynamic> j) => Book(
    id: j['id'] as String,
    // 'name' is how the earlier "group" builds stored it.
    title:
        (j['title'] as String?) ?? (j['name'] as String?) ?? untitledBookTitle,
  );
}

/// A stretch of the timeline the AI grouped together. Its wording and
/// events belong to the AI; the user only chooses which [Book] it sits in.
class TimelineChapter {
  final String id;
  final String title;
  final String summary;
  final List<String> eventIds;
  final String? bookId;

  const TimelineChapter({
    this.id = '',
    required this.title,
    required this.summary,
    required this.eventIds,
    this.bookId,
  });

  TimelineChapter copyWith({
    String? id,
    List<String>? eventIds,
    String? bookId,
    bool clearBook = false,
  }) => TimelineChapter(
    id: id ?? this.id,
    title: title,
    summary: summary,
    eventIds: eventIds ?? this.eventIds,
    bookId: clearBook ? null : (bookId ?? this.bookId),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'summary': summary,
    'event_ids': eventIds,
    'book_id': bookId,
  };

  factory TimelineChapter.fromJson(Map<String, dynamic> j) => TimelineChapter(
    id: (j['id'] as String?) ?? '',
    title: (j['title'] as String?) ?? '',
    summary: (j['summary'] as String?) ?? '',
    eventIds: ((j['event_ids'] as List?) ?? const []).cast<String>(),
    bookId: (j['book_id'] as String?) ?? (j['group_id'] as String?),
  );
}

/// A connection between two events, made by the AI.
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
    relation: (j['relation'] as String?) ?? '',
  );
}

/// A recurring thread across events, found by the AI.
class StoryTheme {
  final String name;
  final String description;
  final List<String> eventIds;

  const StoryTheme({
    required this.name,
    required this.description,
    required this.eventIds,
  });

  StoryTheme copyWith({List<String>? eventIds}) => StoryTheme(
    name: name,
    description: description,
    eventIds: eventIds ?? this.eventIds,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'event_ids': eventIds,
  };

  factory StoryTheme.fromJson(Map<String, dynamic> j) => StoryTheme(
    name: (j['name'] as String?) ?? '',
    description: (j['description'] as String?) ?? '',
    eventIds: ((j['event_ids'] as List?) ?? const []).cast<String>(),
  );
}

/// The organised timeline.
///
/// Two layers live here. The AI layer (overview, chapters' wording and
/// events, links, themes) is written only by the AI, which builds on it as
/// new events are described. The user layer (books, which book each chapter
/// is in, and rings on events) is the only part the user can change; see
/// [withUserLayer].
class GraphSnapshot {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Described events and photos the AI had seen at its last update.
  final int eventCount;
  final int photoCount;
  final String model;
  final String overview;
  final List<TimelineChapter> chapters;
  final List<EventLink> links;
  final List<StoryTheme> themes;

  // ---- User layer ----
  final List<Book> books;

  /// Event id → index into [ringPalette].
  final Map<String, int> rings;

  GraphSnapshot({
    required this.id,
    required this.createdAt,
    DateTime? updatedAt,
    required this.eventCount,
    this.photoCount = 0,
    required this.model,
    required this.overview,
    required this.chapters,
    required this.links,
    required this.themes,
    this.books = const [],
    this.rings = const {},
  }) : updatedAt = updatedAt ?? createdAt;

  GraphSnapshot copyWith({
    DateTime? updatedAt,
    int? eventCount,
    int? photoCount,
    String? model,
    String? overview,
    List<TimelineChapter>? chapters,
    List<EventLink>? links,
    List<StoryTheme>? themes,
    List<Book>? books,
    Map<String, int>? rings,
  }) => GraphSnapshot(
    id: id,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    eventCount: eventCount ?? this.eventCount,
    photoCount: photoCount ?? this.photoCount,
    model: model ?? this.model,
    overview: overview ?? this.overview,
    chapters: chapters ?? this.chapters,
    links: links ?? this.links,
    themes: themes ?? this.themes,
    books: books ?? this.books,
    rings: rings ?? this.rings,
  );

  TimelineChapter? chapterOf(String eventId) {
    for (final c in chapters) {
      if (c.eventIds.contains(eventId)) return c;
    }
    return null;
  }

  /// Applies the user's choices without touching anything the AI owns:
  /// only books, chapter → book placement and rings are taken from the
  /// arguments. Unknown chapters in [chapterBooks] are ignored.
  GraphSnapshot withUserLayer({
    required List<Book> books,
    required Map<String, String?> chapterBooks,
    required Map<String, int> rings,
  }) => copyWith(
    books: books,
    rings: rings,
    chapters: [
      for (final c in chapters)
        chapterBooks.containsKey(c.id)
            ? c.copyWith(
                bookId: chapterBooks[c.id],
                clearBook: chapterBooks[c.id] == null,
              )
            : c,
    ],
  );

  /// Repairs anything that could break the app: references to events that
  /// no longer exist, unknown books, out-of-range rings, blank titles,
  /// duplicate or self links, duplicate themes, and missing or duplicate
  /// ids. Always safe to call, and stable when called again.
  GraphSnapshot sanitized(Set<String> validEventIds) {
    final bookIds = <String>{};
    final cleanBooks = <Book>[];
    for (var i = 0; i < books.length; i++) {
      final b = books[i];
      var id = b.id.isEmpty ? 'b$i' : b.id;
      while (bookIds.contains(id)) {
        id = '$id-$i';
      }
      bookIds.add(id);
      cleanBooks.add(
        Book(
          id: id,
          title: b.title.trim().isEmpty ? untitledBookTitle : b.title.trim(),
        ),
      );
    }

    List<String> events(List<String> ids) => [
      for (final id in ids.toSet())
        if (validEventIds.contains(id)) id,
    ];

    final chapterIds = <String>{};
    final placed = <String>{};
    final cleanChapters = <TimelineChapter>[];
    for (var i = 0; i < chapters.length; i++) {
      final c = chapters[i];
      var id = c.id.isEmpty ? 'c$i' : c.id;
      while (chapterIds.contains(id)) {
        id = '$id-$i';
      }
      chapterIds.add(id);
      // An event sits in one chapter: the first one that claims it.
      final ids = [
        for (final e in events(c.eventIds))
          if (placed.add(e)) e,
      ];
      cleanChapters.add(
        TimelineChapter(
          id: id,
          title: c.title.trim().isEmpty ? 'Untitled chapter' : c.title.trim(),
          summary: c.summary.trim(),
          eventIds: ids,
          bookId: bookIds.contains(c.bookId) ? c.bookId : null,
        ),
      );
    }

    final seenLinks = <String>{};
    final cleanLinks = <EventLink>[];
    for (final l in links) {
      if (l.fromEventId == l.toEventId ||
          !validEventIds.contains(l.fromEventId) ||
          !validEventIds.contains(l.toEventId) ||
          !seenLinks.add('${l.fromEventId}>${l.toEventId}')) {
        continue;
      }
      cleanLinks.add(
        EventLink(
          fromEventId: l.fromEventId,
          toEventId: l.toEventId,
          relation: l.relation.trim().isEmpty ? 'related' : l.relation.trim(),
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
        ),
      );
    }

    return copyWith(
      overview: overview.trim(),
      books: cleanBooks,
      chapters: cleanChapters,
      links: cleanLinks,
      themes: cleanThemes,
      rings: {
        for (final entry in rings.entries)
          if (validEventIds.contains(entry.key) &&
              entry.value >= 0 &&
              entry.value < ringPalette.length)
            entry.key: entry.value,
      },
    );
  }

  Map<String, Object?> toRow() => {
    'id': id,
    'created_at': createdAt.millisecondsSinceEpoch,
    'event_count': eventCount,
    'model': model,
    'data': jsonEncode({
      'updated_at': updatedAt.millisecondsSinceEpoch,
      'photo_count': photoCount,
      'overview': overview,
      'chapters': chapters.map((c) => c.toJson()).toList(),
      'links': links.map((l) => l.toJson()).toList(),
      'themes': themes.map((t) => t.toJson()).toList(),
      'books': books.map((b) => b.toJson()).toList(),
      'rings': rings,
    }),
  };

  factory GraphSnapshot.fromRow(Map<String, Object?> row) {
    final data = jsonDecode(row['data'] as String) as Map<String, dynamic>;
    List<Map<String, dynamic>> list(String key) =>
        ((data[key] as List?) ?? const []).cast<Map<String, dynamic>>();
    final chapters = list('chapters').map(TimelineChapter.fromJson).toList();
    final createdAt = DateTime.fromMillisecondsSinceEpoch(
      row['created_at'] as int,
    );
    final updated = data['updated_at'] as int?;
    return GraphSnapshot(
      id: row['id'] as String,
      createdAt: createdAt,
      updatedAt: updated == null
          ? createdAt
          : DateTime.fromMillisecondsSinceEpoch(updated),
      eventCount: row['event_count'] as int,
      photoCount: (data['photo_count'] as int?) ?? 0,
      model: (row['model'] as String?) ?? '',
      overview: (data['overview'] as String?) ?? '',
      chapters: [
        // Snapshots from before chapters had ids get stable ones.
        for (var i = 0; i < chapters.length; i++)
          chapters[i].id.isEmpty
              ? chapters[i].copyWith(id: 'c$i')
              : chapters[i],
      ],
      links: list('links').map(EventLink.fromJson).toList(),
      themes: list('themes').map(StoryTheme.fromJson).toList(),
      // Earlier builds called books "groups".
      books: (data['books'] != null ? list('books') : list('groups'))
          .map(Book.fromJson)
          .toList(),
      rings: {
        for (final e in ((data['rings'] as Map?) ?? const {}).entries)
          if (e.value is int) e.key as String: e.value as int,
      },
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

  /// Ring colour the user put on this event, if any.
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
/// Each node is marked with who supplied it, and events carry the ring
/// colour the user gave them, if any.
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
      ringColor: ringColorFor(snapshot?.rings[e.id]),
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
