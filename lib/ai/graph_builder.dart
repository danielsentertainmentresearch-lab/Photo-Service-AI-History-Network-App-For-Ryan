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
      model: (response['model'] as String?) ?? '',
      overview: (data['overview'] as String? ?? '').trim(),
      chapters: [
        for (final c in list('chapters'))
          TimelineChapter(
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
    );
  }
}
