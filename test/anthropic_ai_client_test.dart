import 'dart:convert';

import 'package:eventlens/ai/anthropic_ai_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('sends auth, version and beta headers', () async {
    late http.Request seen;
    final client = AnthropicAIClient(
      apiKey: 'sk-ant-test',
      httpClient: MockClient((request) async {
        seen = request;
        return http.Response(jsonEncode({'ok': true}), 200);
      }),
    );
    final result = await client.createMessage({'model': 'x'},
        betas: const [AnthropicAIClient.fallbackBeta]);

    expect(result, {'ok': true});
    expect(seen.url, AnthropicAIClient.messagesUri);
    expect(seen.headers['x-api-key'], 'sk-ant-test');
    expect(seen.headers['anthropic-version'], '2023-06-01');
    expect(seen.headers['anthropic-beta'], AnthropicAIClient.fallbackBeta);
  });

  test('retries overloaded responses, then succeeds', () async {
    var calls = 0;
    final client = AnthropicAIClient(
      apiKey: 'k',
      httpClient: MockClient((_) async {
        calls++;
        return calls == 1
            ? http.Response('{"error":{"message":"Overloaded"}}', 529,
                headers: {'retry-after': '0'})
            : http.Response('{"done":1}', 200);
      }),
    );
    expect(await client.createMessage(const {}), {'done': 1});
    expect(calls, 2);
  });

  test('does not retry a rejected key', () async {
    var calls = 0;
    final client = AnthropicAIClient(
      apiKey: 'bad',
      httpClient: MockClient((_) async {
        calls++;
        return http.Response('{"error":{"message":"invalid x-api-key"}}', 401);
      }),
    );
    await expectLater(
      client.createMessage(const {}),
      throwsA(isA<AIException>()
          .having((e) => e.statusCode, 'statusCode', 401)),
    );
    expect(calls, 1);
  });
}
