import 'dart:convert';

import 'package:eventlens/ai/ai_server.dart';
import 'package:eventlens/ai/anthropic_ai_client.dart';
import 'package:eventlens/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

ProxyAIClient _client(
  MockClientHandler handler, {
  String? token = 'id-token',
  String task = AiTask.describe,
}) => ProxyAIClient(
  baseUri: Uri.parse('https://example.supabase.co/functions/v1/ai/'),
  task: task,
  idToken: () async => token,
  httpClient: MockClient(handler),
);

void main() {
  setUp(() => aiAllowance.value = null);

  test('sends the task, betas and body with the sign-in token', () async {
    late http.Request seen;
    final client = _client((request) async {
      seen = request;
      return http.Response(
        jsonEncode({'stop_reason': 'end_turn', 'content': []}),
        200,
        headers: {'x-ai-remaining': '17', 'x-ai-daily': '20'},
      );
    });
    final result = await client.createMessage(
      {'model': 'claude-opus-5-5'},
      betas: const [AnthropicAIClient.fallbackBeta],
    );

    expect(result['stop_reason'], 'end_turn');
    expect(
      seen.url.toString(),
      'https://example.supabase.co/functions/v1/ai/messages',
    );
    expect(seen.headers['authorization'], 'Bearer id-token');
    expect(seen.headers.containsKey('x-api-key'), isFalse);
    final sent = jsonDecode(seen.body) as Map<String, dynamic>;
    expect(sent['task'], AiTask.describe);
    expect(sent['betas'], [AnthropicAIClient.fallbackBeta]);
    expect(sent['body'], {'model': 'claude-opus-5-5'});
    expect(aiAllowance.value, const AiAllowance(remaining: 17, daily: 20));
  });

  test('a used-up allowance is a clear, non-retried error', () async {
    var calls = 0;
    final client = _client((request) async {
      calls++;
      return http.Response(
        jsonEncode({
          'error': {'message': 'allowance used up'},
        }),
        402,
        headers: {'x-ai-remaining': '0', 'x-ai-daily': '20'},
      );
    });
    await expectLater(
      client.createMessage({}),
      throwsA(
        isA<AIException>()
            .having((e) => e.statusCode, 'status', 402)
            .having((e) => e.retryable, 'retryable', isFalse)
            .having((e) => e.message, 'message', contains('Nothing is lost')),
      ),
    );
    expect(calls, 1);
    expect(aiAllowance.value?.remaining, 0);
  });

  test('retries a busy server, then succeeds', () async {
    var calls = 0;
    final client = _client((request) async {
      calls++;
      return calls == 1
          ? http.Response('busy', 503)
          : http.Response(jsonEncode({'ok': true}), 200);
    });
    expect(await client.createMessage({}), {'ok': true});
    expect(calls, 2);
  });

  test('without a sign-in it asks the person to sign in', () async {
    final client = _client(
      (request) async => http.Response('{}', 200),
      token: null,
    );
    await expectLater(
      client.createMessage({}),
      throwsA(
        isA<AIException>().having(
          (e) => e.message,
          'message',
          contains('Sign in'),
        ),
      ),
    );
  });

  test('reads the allowance without using it', () async {
    late http.Request seen;
    final client = _client((request) async {
      seen = request;
      return http.Response(
        '{}',
        200,
        headers: {'x-ai-remaining': '20', 'x-ai-daily': '20'},
      );
    });
    final allowance = await client.fetchAllowance();
    expect(seen.method, 'GET');
    expect(seen.url.path, '/functions/v1/ai/allowance');
    expect(allowance, const AiAllowance(remaining: 20, daily: 20));
  });

  test(
    'the server credential picks the server client, a key picks Anthropic',
    () {
      expect(
        aiClientFor(aiServerCredential, AiTask.label),
        isA<ProxyAIClient>(),
      );
      expect(
        (aiClientFor(aiServerCredential, AiTask.label) as ProxyAIClient).task,
        AiTask.label,
      );
      expect(
        aiClientFor('sk-ant-test', AiTask.label),
        isA<AnthropicAIClient>(),
      );
    },
  );
}
