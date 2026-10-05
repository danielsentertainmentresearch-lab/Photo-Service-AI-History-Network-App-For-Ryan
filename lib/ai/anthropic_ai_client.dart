import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'ai_client.dart';

export 'ai_client.dart';

/// Minimal Claude Messages API client over raw HTTP (there is no official
/// Anthropic SDK for Dart).
class AnthropicAIClient implements AIClient {
  static final Uri messagesUri =
      Uri.parse('https://api.anthropic.com/v1/messages');
  static const String apiVersion = '2023-06-01';

  /// Lets the API re-run a declined request on the model Anthropic recommends
  /// for that refusal category, so a false positive doesn't fail the event.
  static const String fallbackBeta = 'server-side-fallback-2026-07-01';

  final http.Client _http;
  final String apiKey;
  final int maxRetries;
  final Duration timeout;

  AnthropicAIClient({
    required this.apiKey,
    http.Client? httpClient,
    this.maxRetries = 2,
    this.timeout = const Duration(minutes: 10),
  }) : _http = httpClient ?? http.Client();

  @override
  Future<Map<String, dynamic>> createMessage(Map<String, dynamic> body,
      {List<String> betas = const []}) async {
    final headers = {
      'x-api-key': apiKey,
      'anthropic-version': apiVersion,
      'content-type': 'application/json',
      if (betas.isNotEmpty) 'anthropic-beta': betas.join(','),
    };
    final encoded = jsonEncode(body);

    for (var attempt = 0;; attempt++) {
      try {
        final response = await _http
            .post(messagesUri, headers: headers, body: encoded)
            .timeout(timeout);
        if (response.statusCode == 200) {
          return jsonDecode(utf8.decode(response.bodyBytes))
              as Map<String, dynamic>;
        }
        final error = _errorFrom(response);
        if (!error.retryable || attempt >= maxRetries) throw error;
        await Future.delayed(_retryDelay(response, attempt));
      } on SocketException {
        if (attempt >= maxRetries) {
          throw const AIException(
              'No internet connection. Check your network and try again.',
              retryable: true);
        }
        await Future.delayed(_backoff(attempt));
      } on TimeoutException {
        throw const AIException(
            'The request took too long. Try again, or use fewer photos.',
            retryable: true);
      }
    }
  }

  @override
  void close() => _http.close();

  static Duration _backoff(int attempt) =>
      Duration(milliseconds: 1000 * (1 << attempt));

  static Duration _retryDelay(http.Response response, int attempt) {
    final retryAfter = int.tryParse(response.headers['retry-after'] ?? '');
    if (retryAfter != null && retryAfter <= 60) {
      return Duration(seconds: retryAfter);
    }
    return _backoff(attempt);
  }

  static AIException _errorFrom(http.Response response) {
    final status = response.statusCode;
    String? apiMessage;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      apiMessage = (decoded['error'] as Map?)?['message'] as String?;
    } catch (_) {
      // Non-JSON error body (e.g. from a proxy); fall back to the status.
    }
    final detail = apiMessage == null ? '' : ' ($apiMessage)';
    return switch (status) {
      401 => AIException(
          'Your Anthropic API key was rejected. Check it in Settings.',
          statusCode: status),
      403 => AIException(
          'This API key is not allowed to use the selected model$detail.',
          statusCode: status),
      400 || 404 || 413 =>
        AIException('The request was rejected$detail.',
            statusCode: status),
      429 => AIException(
          'Rate limited by Anthropic. Wait a minute and retry.',
          statusCode: status,
          retryable: true),
      _ when status >= 500 => AIException(
          'Anthropic is temporarily unavailable ($status). Try again soon.',
          statusCode: status,
          retryable: true),
      _ => AIException('Unexpected API error $status$detail.',
          statusCode: status),
    };
  }
}
