import 'dart:convert';
import 'dart:typed_data';

import 'package:intl/intl.dart';

import '../models/event.dart';
import '../models/memory_item.dart';
import 'anthropic_ai_client.dart';

/// Models offered in Settings. Both accept adaptive thinking, effort,
/// structured outputs and server-side fallbacks.
const supportedModels = {
  'claude-opus-5-5': 'Claude Opus 5.5 (most detailed)',
  'claude-sonnet-5-5': 'Claude Sonnet 5.5 (faster, cheaper)',
};
const defaultModel = 'claude-opus-5-5';

const supportedEfforts = ['low', 'medium', 'high', 'xhigh'];
const defaultEffort = 'high';

/// What the AI produced for one event.
class EventAccount {
  final String title;
  final String summary;
  final String description;
  final List<String> people;
  final List<String> places;
  final List<String> tags;
  final List<MemorySuggestion> memorySuggestions;
  final String model;

  const EventAccount({
    required this.title,
    required this.summary,
    required this.description,
    required this.people,
    required this.places,
    required this.tags,
    required this.memorySuggestions,
    required this.model,
  });
}

/// Builds the request that turns photos + working memory + long-term memory
/// into a detailed account of an event, and parses the result.
class EventDescriber {
  final AIClient client;
  final String model;
  final String effort;

  /// How many recent events are summarised into the context.
  static const int recentEventLimit = 15;

  EventDescriber({
    required this.client,
    this.model = defaultModel,
    this.effort = defaultEffort,
  });

  static const String instructions = '''
You are the user's personal chronicler. The user records events from their life by taking photos and jotting down quick notes at the time. Your job is to write the factual record of each event on their behalf: an extremely detailed, objective account of what can be confirmed, so that years from now they know exactly what happened.

How to write the account:
- Write in the first person, as the user ("I", "we"), in a plain, precise and objective voice.
- This is the factual half of the event. The person keeps their own account of how it felt and what it meant, separately and in their own words, so do not describe their feelings, mood or what the event meant to them, and do not interpret their experience.
- Be exhaustive about what the photos show: setting, light, weather, time-of-day cues, colours, objects, food, clothing, text on signs, expressions, body language, and the order in which things seem to have happened across the photos.
- Weave in the user's notes (their working memory at the time). They are the most reliable source for who was there and what happened.
- Use the long-term memory and earlier events for continuity: name people and places only when the notes or memory make the match clear, and point out how this event connects to earlier ones (recurring people, places, ongoing situations, firsts and anniversaries).
- Never identify a person from their face or appearance alone. If someone is not named in the notes or memory, describe them neutrally (for example "a friend in a red jacket").
- Keep to what the photos, the notes, the date, the place and memory confirm. Mark anything that is only likely with words like "probably", and never invent facts the user did not give and the photos do not show.
- The description should be several rich paragraphs in plain text. Do not use markdown headings, bullet points or bold.

Also return:
- title: a short, specific title (under 60 characters).
- summary: two or three sentences, used later as context for future events.
- people, places, tags: short labels for search.
- memory_suggestions: new durable facts worth remembering for future events (who someone is, a place's significance, an ongoing situation, a preference). Only include facts stated or strongly supported by the notes and not already in long-term memory. Return an empty list if there is nothing new.
''';

  static const Map<String, dynamic> outputSchema = {
    'type': 'object',
    'properties': {
      'title': {'type': 'string'},
      'summary': {'type': 'string'},
      'description': {'type': 'string'},
      'people': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'places': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'tags': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'memory_suggestions': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'kind': {'type': 'string', 'enum': memoryKinds},
            'content': {'type': 'string'},
          },
          'required': ['kind', 'content'],
          'additionalProperties': false,
        },
      },
    },
    'required': [
      'title',
      'summary',
      'description',
      'people',
      'places',
      'tags',
      'memory_suggestions',
    ],
    'additionalProperties': false,
  };

  /// Long-term memory rendered as a stable block. It sits in the system
  /// prompt behind a cache breakpoint because it changes rarely.
  static String memoryBlock(List<MemoryItem> memories) {
    if (memories.isEmpty) {
      return 'Long-term memory: (empty — the user has not saved anything yet)';
    }
    final buffer = StringBuffer('Long-term memory about the user:\n');
    for (final kind in memoryKinds) {
      final items = memories.where((m) => m.kind == kind).toList();
      if (items.isEmpty) continue;
      buffer.writeln('${memoryKindLabel(kind)}:');
      for (final item in items) {
        buffer.writeln('- ${item.content}');
      }
    }
    return buffer.toString().trimRight();
  }

  static String _date(DateTime d) =>
      DateFormat("EEEE d MMMM yyyy, HH:mm").format(d);

  /// The per-event text: working memory plus earlier events for continuity.
  static String eventContext(LifeEvent event, List<LifeEvent> history) {
    final buffer = StringBuffer();
    final earlier =
        history.where((e) => e.id != event.id && e.summary.isNotEmpty).toList()
          ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    final recent = earlier.take(recentEventLimit).toList().reversed;
    if (recent.isNotEmpty) {
      buffer.writeln('<earlier_events>');
      for (final e in recent) {
        buffer.writeln('- ${_date(e.occurredAt)} — ${e.title}: ${e.summary}');
      }
      buffer.writeln('</earlier_events>\n');
    }

    buffer.writeln('<this_event>');
    buffer.writeln('When: ${_date(event.occurredAt)}');
    if (event.location.trim().isNotEmpty) {
      buffer.writeln('Where: ${event.location.trim()}');
    }
    if (event.title.trim().isNotEmpty) {
      buffer.writeln("User's working title: ${event.title.trim()}");
    }
    buffer.writeln('Photos attached: ${event.images.length}');
    buffer.writeln("User's notes at the time (working memory):");
    buffer.writeln(
      event.notes.trim().isEmpty
          ? '(none — rely on the photos and memory)'
          : event.notes.trim(),
    );
    buffer.writeln('</this_event>\n');
    buffer.write('Write the account of this event.');
    return buffer.toString();
  }

  Map<String, dynamic> buildRequest({
    required LifeEvent event,
    required List<Uint8List> jpegs,
    required List<MemoryItem> memories,
    required List<LifeEvent> history,
  }) {
    final content = <Map<String, dynamic>>[];
    for (var i = 0; i < jpegs.length; i++) {
      content.add({'type': 'text', 'text': 'Photo ${i + 1}:'});
      content.add({
        'type': 'image',
        'source': {
          'type': 'base64',
          'media_type': 'image/jpeg',
          'data': base64Encode(jpegs[i]),
        },
      });
    }
    content.add({'type': 'text', 'text': eventContext(event, history)});

    return {
      'model': model,
      'max_tokens': 32000,
      'thinking': {'type': 'adaptive'},
      'output_config': {
        'effort': effort,
        'format': {'type': 'json_schema', 'schema': outputSchema},
      },
      'fallbacks': 'default',
      'system': [
        {'type': 'text', 'text': instructions},
        {
          'type': 'text',
          'text': memoryBlock(memories),
          'cache_control': {'type': 'ephemeral'},
        },
      ],
      'messages': [
        {'role': 'user', 'content': content},
      ],
    };
  }

  /// Turns an API response into an [EventAccount], or throws a user-facing
  /// [AIException] explaining why there is no account.
  static EventAccount parseResponse(Map<String, dynamic> response) {
    final data = parseStructured(response);
    List<String> strings(String key) => ((data[key] as List?) ?? const [])
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return EventAccount(
      title: (data['title'] as String? ?? '').trim(),
      summary: (data['summary'] as String? ?? '').trim(),
      description: (data['description'] as String? ?? '').trim(),
      people: strings('people'),
      places: strings('places'),
      tags: strings('tags'),
      memorySuggestions: ((data['memory_suggestions'] as List?) ?? const [])
          .map((e) => MemorySuggestion.fromJson(e as Map<String, dynamic>))
          .where((s) => s.content.trim().isNotEmpty)
          .toList(),
      model: (response['model'] as String?) ?? '',
    );
  }

  Future<EventAccount> describe({
    required LifeEvent event,
    required List<Uint8List> jpegs,
    required List<MemoryItem> memories,
    required List<LifeEvent> history,
  }) async {
    final response = await client.createMessage(
      buildRequest(
        event: event,
        jpegs: jpegs,
        memories: memories,
        history: history,
      ),
      betas: const [AnthropicAIClient.fallbackBeta],
    );
    return parseResponse(response);
  }
}

/// Checks the stop reason and decodes the JSON text of a structured-output
/// response, throwing a user-facing [AIException] on any problem.
Map<String, dynamic> parseStructured(Map<String, dynamic> response) {
  final stopReason = response['stop_reason'] as String?;
  if (stopReason == 'refusal') {
    throw const AIException(
      'The AI declined this request. Try editing the notes or removing a '
      'photo, then retry.',
    );
  }
  if (stopReason == 'max_tokens') {
    throw const AIException(
      'The AI response was cut off. Try fewer photos or a lower effort '
      'level in Settings.',
    );
  }
  final blocks = (response['content'] as List).cast<Map<String, dynamic>>();
  final text = blocks
      .where((b) => b['type'] == 'text')
      .map((b) => b['text'] as String)
      .join();
  if (text.trim().isEmpty) {
    throw const AIException('The AI returned an empty response.');
  }
  try {
    return jsonDecode(text) as Map<String, dynamic>;
  } on FormatException {
    throw const AIException(
      'The AI response could not be read. Please retry.',
    );
  }
}
