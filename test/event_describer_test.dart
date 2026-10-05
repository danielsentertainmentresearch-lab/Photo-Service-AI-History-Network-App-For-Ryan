import 'dart:convert';
import 'dart:typed_data';

import 'package:eventlens/ai/anthropic_ai_client.dart';
import 'package:eventlens/ai/event_describer.dart';
import 'package:eventlens/models/event.dart';
import 'package:eventlens/models/memory_item.dart';
import 'package:flutter_test/flutter_test.dart';

LifeEvent _event({String id = 'e1', String notes = 'Sam and I at the lake'}) {
  final at = DateTime(2026, 7, 4, 18, 30);
  return LifeEvent(
    id: id,
    title: '',
    notes: notes,
    location: 'Lake Tahoe',
    occurredAt: at,
    createdAt: at,
    updatedAt: at,
    images: const [
      EventImage(id: 'i1', eventId: 'e1', fileName: 'a.jpg', position: 0),
      EventImage(id: 'i2', eventId: 'e1', fileName: 'b.jpg', position: 1),
    ],
  );
}

Map<String, dynamic> _response(Map<String, dynamic> account,
        {String stopReason = 'end_turn'}) =>
    {
      'model': 'claude-opus-5-5',
      'stop_reason': stopReason,
      'content': [
        {'type': 'thinking', 'thinking': ''},
        {'type': 'text', 'text': jsonEncode(account)},
      ],
    };

/// Stands in for any non-Anthropic backend behind the [AIClient] interface.
class _FakeAIClient implements AIClient {
  final Map<String, dynamic> reply;
  Map<String, dynamic>? sent;
  List<String>? sentBetas;

  _FakeAIClient(this.reply);

  @override
  Future<Map<String, dynamic>> createMessage(Map<String, dynamic> body,
      {List<String> betas = const []}) async {
    sent = body;
    sentBetas = betas;
    return reply;
  }

  @override
  void close() {}
}

void main() {
  final describer =
      EventDescriber(client: AnthropicAIClient(apiKey: 'sk-ant-test'));
  final memories = [
    MemoryItem(
      id: 'm1',
      kind: 'person',
      content: 'Sam is my younger brother',
      source: 'user',
      createdAt: DateTime(2026),
    ),
  ];

  test('the free write never goes to the AI, and the account stays factual',
      () {
    const private = 'only mine to read';
    final body = describer.buildRequest(
      event: _event().copyWith(experience: private),
      jpegs: [Uint8List.fromList([1])],
      memories: memories,
      history: [_event(id: 'e0').copyWith(experience: private, summary: 's')],
    );
    expect(jsonEncode(body), isNot(contains(private)));
    expect(EventDescriber.instructions, contains('objective'));
    expect(EventDescriber.instructions, isNot(contains('warm')));
  });

  test('request carries photos, memory, fallbacks and structured output', () {
    final earlier = _event(id: 'e0').copyWith(
        title: 'First swim', summary: 'We swam at dawn.');
    final body = describer.buildRequest(
      event: _event(),
      jpegs: [Uint8List.fromList([1, 2]), Uint8List.fromList([3])],
      memories: memories,
      history: [earlier],
    );

    expect(body['model'], 'claude-opus-5-5');
    expect(body['fallbacks'], 'default');
    expect(body['thinking'], {'type': 'adaptive'});
    expect(body['output_config']['effort'], 'high');
    expect(body['output_config']['format']['type'], 'json_schema');

    final system = body['system'] as List;
    expect(system.last['text'], contains('Sam is my younger brother'));
    expect(system.last['cache_control'], {'type': 'ephemeral'});

    final content = body['messages'][0]['content'] as List;
    final images = content.where((b) => b['type'] == 'image').toList();
    expect(images, hasLength(2));
    expect(images.first['source']['data'], base64Encode([1, 2]));
    final text = content.last['text'] as String;
    expect(text, contains('Sam and I at the lake'));
    expect(text, contains('Lake Tahoe'));
    expect(text, contains('First swim: We swam at dawn.'));
  });

  test('empty memory is stated explicitly', () {
    expect(EventDescriber.memoryBlock(const []), contains('empty'));
  });

  test('parses a structured account', () {
    final account = EventDescriber.parseResponse(_response({
      'title': 'Sunset at the lake',
      'summary': 'Sam and I watched the sunset.',
      'description': 'The water was glass...',
      'people': ['Sam', ' '],
      'places': ['Lake Tahoe'],
      'tags': ['summer'],
      'memory_suggestions': [
        {'kind': 'place', 'content': 'Lake Tahoe is our summer spot'},
      ],
    }));
    expect(account.title, 'Sunset at the lake');
    expect(account.people, ['Sam']);
    expect(account.memorySuggestions.single.kind, 'place');
    expect(account.model, 'claude-opus-5-5');
    expect(account.questions, isEmpty);
  });

  test('parses up to three who/where questions', () {
    final account = EventDescriber.parseResponse(_response({
      'title': 't',
      'summary': 's',
      'description': 'd',
      'people': [],
      'places': [],
      'tags': [],
      'memory_suggestions': [],
      'questions': [
        for (var i = 0; i < 5; i++)
          {
            'kind': i.isEven ? 'person' : 'place',
            'about': 'thing $i',
            'question': 'Who or where is thing $i?',
          },
        {'kind': 'person', 'about': 'x', 'question': ' '},
      ],
    }));
    expect(account.questions, hasLength(EventDescriber.maxQuestions));
    expect(account.questions.first.kind, 'person');
    expect(account.questions[1].kind, 'place');
    expect(account.questions.first.about, 'thing 0');
  });

  test('the request asks for questions in the structured output', () {
    expect(
      (EventDescriber.outputSchema['required'] as List),
      contains('questions'),
    );
    expect(EventDescriber.instructions, contains('never about feelings'));
  });

  test('refusal and truncation become user-facing errors', () {
    expect(
      () => EventDescriber.parseResponse(
          _response(const {}, stopReason: 'refusal')),
      throwsA(isA<AIException>()
          .having((e) => e.message, 'message', contains('declined'))),
    );
    expect(
      () => EventDescriber.parseResponse(
          _response(const {}, stopReason: 'max_tokens')),
      throwsA(isA<AIException>()
          .having((e) => e.message, 'message', contains('cut off'))),
    );
  });

  test('invalid JSON becomes a user-facing error', () {
    expect(
      () => EventDescriber.parseResponse({
        'stop_reason': 'end_turn',
        'content': [
          {'type': 'text', 'text': 'not json'},
        ],
      }),
      throwsA(isA<AIException>()),
    );
  });

  test('describes through any AIClient backend, not only Anthropic', () async {
    final backend = _FakeAIClient(_response({
      'title': 'Sunset at the lake',
      'summary': 'Sam and I watched the sunset.',
      'description': 'The water was glass...',
      'people': ['Sam'],
      'places': ['Lake Tahoe'],
      'tags': ['summer'],
      'memory_suggestions': [],
    }));
    final account = await EventDescriber(client: backend).describe(
      event: _event(),
      jpegs: [Uint8List.fromList([1])],
      memories: memories,
      history: const [],
    );
    expect(account.title, 'Sunset at the lake');
    expect(backend.sent?['messages'], isNotEmpty);
    expect(backend.sentBetas, [AnthropicAIClient.fallbackBeta]);
  });
}
