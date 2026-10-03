import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../models/event.dart';
import '../models/memory_graph.dart';
import '../models/memory_item.dart';
import 'anthropic_client.dart';
import 'event_describer.dart';

/// Asks the AI to organise every described event into a timeline: chapters,
/// links between events, and recurring themes. Runs text-only (no photos),
/// using the accounts and notes already recorded.
class GraphBuilder {
  final AnthropicClient client;
  final String model;
  final String effort;

  /// Most recent events sent; older ones are summarised by earlier chapters.
  static const int maxEvents = 200;

  GraphBuilder({
    required this.client,
    this.model = defaultModel,
    this.effort = defaultEffort,
  });

  static const String instructions = '''
You organise a person's life journal into a connected timeline, like the graph view of a personal knowledge base. You receive every event they have recorded: the date, the user's own notes, and the AI-written summary, people, places and tags. You also receive their long-term memories.

Produce:
- overview: one paragraph on the arc of this whole period of their life.
- chapters: consecutive stretches of time that belong together (a trip, a season, a project, a hard week). Every event belongs to exactly one chapter, in date order. Give each a short title and a two-to-three sentence summary.
- links: meaningful connections between two events beyond simply being next in time: the same people or place returning, a cause and its consequence, a promise and its follow-up, a first and a repeat, an anniversary. Give each a short relation phrase such as "same lake, one year later". Only link events when the connection is real and supported by the data.
- themes: recurring threads across events (a relationship, a hobby, a place, a goal), each with a one-sentence description and the events that belong to it.

Refer to events only by their reference codes (E1, E2, ...). Treat the user's notes as the most reliable source and never invent facts.
''';

  static const Map<String, dynamic> outputSchema = {
    'type': 'object',
    'properties': {
      'overview': {'type': 'string'},
      'chapters': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'title': {'type': 'string'},
            'summary': {'type': 'string'},
            'event_refs': {
              'type': 'array',
              'items': {'type': 'string'},
            },
          },
          'required': ['title', 'summary', 'event_refs'],
          'additionalProperties': false,
        },
      },
      'links': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'from': {'type': 'string'},
            'to': {'type': 'string'},
            'relation': {'type': 'string'},
          },
          'required': ['from', 'to', 'relation'],
          'additionalProperties': false,
        },
      },
      'themes': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'name': {'type': 'string'},
            'description': {'type': 'string'},
            'event_refs': {
              'type': 'array',
              'items': {'type': 'string'},
            },
          },
          'required': ['name', 'description', 'event_refs'],
          'additionalProperties': false,
        },
      },
    },
    'required': ['overview', 'chapters', 'links', 'themes'],
    'additionalProperties': false,
  };

  /// Described events in date order, capped at [maxEvents] most recent.
  static List<LifeEvent> eligible(List<LifeEvent> events) {
    final described = events.where((e) => e.hasAccount).toList()
      ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    return described.length <= maxEvents
        ? described
        : described.sublist(described.length - maxEvents);
  }

  static String journalText(
    List<LifeEvent> ordered,
    List<MemoryItem> memories,
  ) {
    final date = DateFormat('EEE d MMM yyyy, HH:mm');
    final buffer = StringBuffer(EventDescriber.memoryBlock(memories))
      ..writeln('\n\n<events>');
    for (var i = 0; i < ordered.length; i++) {
      final e = ordered[i];
      buffer.writeln('E${i + 1} | ${date.format(e.occurredAt)} | ${e.title}');
      if (e.location.isNotEmpty) buffer.writeln('  Where: ${e.location}');
      if (e.notes.isNotEmpty) buffer.writeln('  User notes: ${e.notes}');
      buffer.writeln('  Summary: ${e.summary}');
      if (e.people.isNotEmpty) {
        buffer.writeln('  People: ${e.people.join(', ')}');
      }
      if (e.places.isNotEmpty) {
        buffer.writeln('  Places: ${e.places.join(', ')}');
      }
      if (e.tags.isNotEmpty) buffer.writeln('  Tags: ${e.tags.join(', ')}');
    }
    buffer
      ..writeln('</events>')
      ..write('Organise these events into the connected timeline.');
    return buffer.toString();
  }

  Map<String, dynamic> buildRequest(
    List<LifeEvent> ordered,
    List<MemoryItem> memories,
  ) => {
    'model': model,
    'max_tokens': 32000,
    'thinking': {'type': 'adaptive'},
    'output_config': {
      'effort': effort,
      'format': {'type': 'json_schema', 'schema': outputSchema},
    },
    'fallbacks': 'default',
    'system': instructions,
    'messages': [
      {'role': 'user', 'content': journalText(ordered, memories)},
    ],
  };

  /// Maps the AI's E-codes back to event ids, dropping unknown codes.
  static GraphSnapshot parse(
    Map<String, dynamic> response,
    List<LifeEvent> ordered, {
    required int describedCount,
    int photoCount = 0,
  }) {
    final data = parseStructured(response);
    String? idFor(Object? ref) {
      final match = RegExp(r'^E(\d+)$').firstMatch('$ref'.trim());
      final index = match == null ? -1 : int.parse(match.group(1)!) - 1;
      return index >= 0 && index < ordered.length ? ordered[index].id : null;
    }

    List<String> ids(Object? refs) => ((refs as List?) ?? const [])
        .map(idFor)
        .whereType<String>()
        .toSet()
        .toList();
    List<Map<String, dynamic>> list(String key) =>
        ((data[key] as List?) ?? const []).cast<Map<String, dynamic>>();

    return GraphSnapshot(
      id: const Uuid().v4(),
      createdAt: DateTime.now(),
      eventCount: describedCount,
      photoCount: photoCount,
      model: (response['model'] as String?) ?? '',
      overview: (data['overview'] as String? ?? '').trim(),
      chapters: [
        for (final c in list('chapters'))
          TimelineChapter(
            id: const Uuid().v4(),
            title: (c['title'] as String? ?? '').trim(),
            summary: (c['summary'] as String? ?? '').trim(),
            eventIds: ids(c['event_refs']),
          ),
      ].where((c) => c.eventIds.isNotEmpty).toList(),
      links: [
        for (final l in list('links'))
          if (idFor(l['from']) != null &&
              idFor(l['to']) != null &&
              idFor(l['from']) != idFor(l['to']))
            EventLink(
              fromEventId: idFor(l['from'])!,
              toEventId: idFor(l['to'])!,
              relation: (l['relation'] as String? ?? '').trim(),
            ),
      ],
      themes: [
        for (final t in list('themes'))
          StoryTheme(
            name: (t['name'] as String? ?? '').trim(),
            description: (t['description'] as String? ?? '').trim(),
            eventIds: ids(t['event_refs']),
          ),
      ].where((t) => t.name.isNotEmpty && t.eventIds.isNotEmpty).toList(),
    );
  }

  // ---- Building on an existing graph ------------------------------------

  static const String updateInstructions = """
You maintain a person's life journal as a connected timeline, like the graph view of a personal knowledge base. The timeline already exists: chapters (C1, C2, ...), themes, and the events already placed (E1, E2, ...). New events have just been recorded (N1, N2, ...).

Build on what exists; never rewrite it. Earlier chapters, themes and connections stay exactly as they are. For the new events:
- placements: put every new event into the existing chapter it belongs to, or into a new chapter when it clearly starts a new stretch of life (a trip, a season, a project). New events that belong together go into the same new chapter (use the same new_chapter_title). Give a new chapter a short title and a two-to-three sentence summary; leave both empty when using an existing chapter.
- links: meaningful connections from a new event to another event (new or earlier): the same people or place returning, a cause and its consequence, a promise and its follow-up, a first and a repeat, an anniversary. Short relation phrase. Only real, supported connections.
- themes: recurring threads the new events belong to. Reuse an existing theme's exact name to add events to it, or create a new theme with a one-sentence description.
- overview: the existing overview, extended so it also reflects the new events. Keep what it already says.

Refer to events and chapters only by their codes. Treat the user's notes as the most reliable source and never invent facts.
""";

  static const Map<String, dynamic> updateSchema = {
    'type': 'object',
    'properties': {
      'overview': {'type': 'string'},
      'placements': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'event': {'type': 'string'},
            'chapter': {
              'type': 'string',
              'description': 'An existing chapter code, or NEW',
            },
            'new_chapter_title': {'type': 'string'},
            'new_chapter_summary': {'type': 'string'},
          },
          'required': [
            'event',
            'chapter',
            'new_chapter_title',
            'new_chapter_summary',
          ],
          'additionalProperties': false,
        },
      },
      'links': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'from': {'type': 'string'},
            'to': {'type': 'string'},
            'relation': {'type': 'string'},
          },
          'required': ['from', 'to', 'relation'],
          'additionalProperties': false,
        },
      },
      'themes': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'name': {'type': 'string'},
            'description': {'type': 'string'},
            'event_refs': {
              'type': 'array',
              'items': {'type': 'string'},
            },
          },
          'required': ['name', 'description', 'event_refs'],
          'additionalProperties': false,
        },
      },
    },
    'required': ['overview', 'placements', 'links', 'themes'],
    'additionalProperties': false,
  };

  /// Described events the AI hasn't placed in a chapter yet, oldest first.
  static List<LifeEvent> pending(List<LifeEvent> events, GraphSnapshot graph) {
    final placed = {for (final c in graph.chapters) ...c.eventIds};
    return events.where((e) => e.hasAccount && !placed.contains(e.id)).toList()
      ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
  }

  /// Already-placed events in date order, capped at [maxEvents].
  static List<LifeEvent> placed(List<LifeEvent> events, GraphSnapshot graph) {
    final ids = {for (final c in graph.chapters) ...c.eventIds};
    final list = events.where((e) => ids.contains(e.id)).toList()
      ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    return list.length <= maxEvents
        ? list
        : list.sublist(list.length - maxEvents);
  }

  static String updateText(
    GraphSnapshot graph,
    List<LifeEvent> existing,
    List<LifeEvent> fresh,
    List<MemoryItem> memories,
  ) {
    final date = DateFormat('EEE d MMM yyyy, HH:mm');
    final eRef = {
      for (var i = 0; i < existing.length; i++) existing[i].id: 'E${i + 1}',
    };
    final buffer = StringBuffer(EventDescriber.memoryBlock(memories))
      ..writeln('\n\n<overview>\n${graph.overview}\n</overview>')
      ..writeln('\n<chapters>');
    for (var i = 0; i < graph.chapters.length; i++) {
      final c = graph.chapters[i];
      final refs = c.eventIds.map((id) => eRef[id]).whereType<String>();
      buffer.writeln(
        'C${i + 1} | ${c.title} | ${c.summary} | events: ${refs.join(', ')}',
      );
    }
    buffer.writeln('</chapters>\n\n<themes>');
    for (final t in graph.themes) {
      final refs = t.eventIds.map((id) => eRef[id]).whereType<String>();
      buffer.writeln(
        '${t.name} | ${t.description} | events: ${refs.join(', ')}',
      );
    }
    buffer.writeln('</themes>\n\n<earlier_events>');
    for (var i = 0; i < existing.length; i++) {
      final e = existing[i];
      buffer.writeln(
        'E${i + 1} | ${date.format(e.occurredAt)} | ${e.title} | ${e.summary}',
      );
    }
    buffer.writeln('</earlier_events>\n\n<new_events>');
    for (var i = 0; i < fresh.length; i++) {
      final e = fresh[i];
      buffer.writeln('N${i + 1} | ${date.format(e.occurredAt)} | ${e.title}');
      if (e.location.isNotEmpty) buffer.writeln('  Where: ${e.location}');
      if (e.notes.isNotEmpty) buffer.writeln('  User notes: ${e.notes}');
      buffer.writeln('  Summary: ${e.summary}');
      if (e.people.isNotEmpty) {
        buffer.writeln('  People: ${e.people.join(', ')}');
      }
      if (e.places.isNotEmpty) {
        buffer.writeln('  Places: ${e.places.join(', ')}');
      }
      if (e.tags.isNotEmpty) buffer.writeln('  Tags: ${e.tags.join(', ')}');
    }
    buffer
      ..writeln('</new_events>')
      ..write('Add the new events to the timeline.');
    return buffer.toString();
  }

  Map<String, dynamic> buildUpdateRequest(
    GraphSnapshot graph,
    List<LifeEvent> existing,
    List<LifeEvent> fresh,
    List<MemoryItem> memories,
  ) => {
    'model': model,
    'max_tokens': 32000,
    'thinking': {'type': 'adaptive'},
    'output_config': {
      'effort': effort,
      'format': {'type': 'json_schema', 'schema': updateSchema},
    },
    'fallbacks': 'default',
    'system': updateInstructions,
    'messages': [
      {'role': 'user', 'content': updateText(graph, existing, fresh, memories)},
    ],
  };

  /// Adds the AI's placements, links and themes for [fresh] events to
  /// [graph] without changing anything already there (apart from extending
  /// the overview and adding events to existing themes). New events the AI
  /// forgot to place go into the latest chapter, so nothing is left behind.
  static GraphSnapshot applyUpdate(
    Map<String, dynamic> response,
    GraphSnapshot graph,
    List<LifeEvent> existing,
    List<LifeEvent> fresh, {
    required int describedCount,
    required int photoCount,
  }) {
    final data = parseStructured(response);
    String? idFor(Object? ref) {
      final match = RegExp(r'^([EN])(\d+)$').firstMatch('$ref'.trim());
      if (match == null) return null;
      final list = match.group(1) == 'E' ? existing : fresh;
      final index = int.parse(match.group(2)!) - 1;
      return index >= 0 && index < list.length ? list[index].id : null;
    }

    List<Map<String, dynamic>> list(String key) =>
        ((data[key] as List?) ?? const []).cast<Map<String, dynamic>>();
    final freshIds = fresh.map((e) => e.id).toSet();

    final chapters = [
      for (final c in graph.chapters) c.copyWith(eventIds: [...c.eventIds]),
    ];
    final newByTitle = <String, int>{};
    final placedNow = <String>{};
    for (final p in list('placements')) {
      final eventId = idFor(p['event']);
      if (eventId == null || !freshIds.contains(eventId)) continue;
      if (!placedNow.add(eventId)) continue;
      final match = RegExp(r'^C(\d+)$').firstMatch('${p['chapter']}'.trim());
      final index = match == null ? -1 : int.parse(match.group(1)!) - 1;
      if (index >= 0 && index < graph.chapters.length) {
        chapters[index] = chapters[index].copyWith(
          eventIds: [...chapters[index].eventIds, eventId],
        );
        continue;
      }
      final title = (p['new_chapter_title'] as String? ?? '').trim();
      final key = title.isEmpty ? 'New chapter' : title;
      final existingIndex = newByTitle[key.toLowerCase()];
      if (existingIndex != null) {
        chapters[existingIndex] = chapters[existingIndex].copyWith(
          eventIds: [...chapters[existingIndex].eventIds, eventId],
        );
      } else {
        newByTitle[key.toLowerCase()] = chapters.length;
        chapters.add(
          TimelineChapter(
            id: const Uuid().v4(),
            title: key,
            summary: (p['new_chapter_summary'] as String? ?? '').trim(),
            eventIds: [eventId],
          ),
        );
      }
    }
    final forgotten = fresh.where((e) => !placedNow.contains(e.id)).toList();
    if (forgotten.isNotEmpty) {
      if (chapters.isEmpty) {
        chapters.add(
          TimelineChapter(
            id: const Uuid().v4(),
            title: 'Recent events',
            summary: '',
            eventIds: forgotten.map((e) => e.id).toList(),
          ),
        );
      } else {
        chapters[chapters.length - 1] = chapters.last.copyWith(
          eventIds: [...chapters.last.eventIds, ...forgotten.map((e) => e.id)],
        );
      }
    }

    final links = [
      ...graph.links,
      for (final l in list('links'))
        if (idFor(l['from']) != null &&
            idFor(l['to']) != null &&
            (freshIds.contains(idFor(l['from'])) ||
                freshIds.contains(idFor(l['to']))))
          EventLink(
            fromEventId: idFor(l['from'])!,
            toEventId: idFor(l['to'])!,
            relation: (l['relation'] as String? ?? '').trim(),
          ),
    ];

    final themes = [...graph.themes];
    for (final t in list('themes')) {
      final name = (t['name'] as String? ?? '').trim();
      if (name.isEmpty) continue;
      final ids = ((t['event_refs'] as List?) ?? const [])
          .map(idFor)
          .whereType<String>()
          .toList();
      final i = themes.indexWhere(
        (x) => x.name.toLowerCase() == name.toLowerCase(),
      );
      if (i >= 0) {
        themes[i] = themes[i].copyWith(
          eventIds: {...themes[i].eventIds, ...ids}.toList(),
        );
      } else if (ids.isNotEmpty) {
        themes.add(
          StoryTheme(
            name: name,
            description: (t['description'] as String? ?? '').trim(),
            eventIds: ids,
          ),
        );
      }
    }

    final overview = (data['overview'] as String? ?? '').trim();
    return graph.copyWith(
      updatedAt: DateTime.now(),
      eventCount: describedCount,
      photoCount: photoCount,
      model: (response['model'] as String?) ?? graph.model,
      overview: overview.isEmpty ? graph.overview : overview,
      chapters: chapters,
      links: links,
      themes: themes,
    );
  }

  /// Builds on [graph] with any described events not yet placed. Returns
  /// [graph] unchanged when there is nothing new.
  Future<GraphSnapshot> update(
    GraphSnapshot graph,
    List<LifeEvent> events,
    List<MemoryItem> memories,
  ) async {
    final fresh = pending(events, graph);
    if (fresh.isEmpty) return graph;
    final existing = placed(events, graph);
    final response = await client.createMessage(
      buildUpdateRequest(graph, existing, fresh, memories),
      betas: const [AnthropicClient.fallbackBeta],
    );
    return applyUpdate(
      response,
      graph,
      existing,
      fresh,
      describedCount: events.where((e) => e.hasAccount).length,
      photoCount: describedPhotoCount(events),
    );
  }

  Future<GraphSnapshot> build(
    List<LifeEvent> events,
    List<MemoryItem> memories,
  ) async {
    final ordered = eligible(events);
    final response = await client.createMessage(
      buildRequest(ordered, memories),
      betas: const [AnthropicClient.fallbackBeta],
    );
    return parse(
      response,
      ordered,
      describedCount: events.where((e) => e.hasAccount).length,
      photoCount: describedPhotoCount(events),
    );
  }
}

/// Photos across all described events; the graph unlocks at
/// [graphUnlockPhotos].
int describedPhotoCount(List<LifeEvent> events) => events
    .where((e) => e.hasAccount)
    .fold(0, (sum, e) => sum + e.images.length);

/// Described photos needed before the AI first turns the timeline into a
/// graph. This happens once; after that the AI builds on the graph as new
/// events are described.
const graphUnlockPhotos = 10;
