import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'ai_client.dart';

/// The owner's AI server (see `docs/AI_SERVER.md`), passed at build time:
/// `--dart-define=AI_SERVER_URL=https://<project>.supabase.co/functions/v1/ai`.
/// When it is set, the app uses the server and nobody needs their own
/// Anthropic API key; when it is empty, the app falls back to the key in
/// Settings.
const aiServerUrl = String.fromEnvironment('AI_SERVER_URL');

/// Stands in for an API key when the AI runs through the owner's server.
const aiServerCredential = 'ai-server';

/// What each kind of request is, so the server can choose the model and
/// charge the allowance by cost.
abstract final class AiTask {
  static const describe = 'describe';
  static const graph = 'graph';
  static const label = 'label';
  static const advise = 'advise';
}

/// Today's AI allowance for the signed-in account, as the server reports it.
@immutable
class AiAllowance {
  /// Credits left today, including ad top-ups.
  final int remaining;

  /// The free daily amount, before top-ups.
  final int daily;

  const AiAllowance({required this.remaining, required this.daily});

  static AiAllowance? fromHeaders(Map<String, String> headers) {
    final remaining = int.tryParse(headers['x-ai-remaining'] ?? '');
    final daily = int.tryParse(headers['x-ai-daily'] ?? '');
    if (remaining == null || daily == null) return null;
    return AiAllowance(remaining: remaining, daily: daily);
  }

  @override
  bool operator ==(Object other) =>
      other is AiAllowance &&
      other.remaining == remaining &&
      other.daily == daily;

  @override
  int get hashCode => Object.hash(remaining, daily);
}

/// The latest allowance any server reply reported (null until the first).
final ValueNotifier<AiAllowance?> aiAllowance = ValueNotifier(null);

/// The signed-in account's Firebase ID token, which the server checks.
Future<String?> firebaseIdToken() async {
  if (Firebase.apps.isEmpty) return null;
  return FirebaseAuth.instance.currentUser?.getIdToken();
}

/// Sends Claude Messages requests through the owner's AI server, which holds
/// the Anthropic key, checks the account and applies the daily allowance.
class ProxyAIClient implements AIClient {
  final Uri baseUri;
  final String task;
  final Future<String?> Function() idToken;
  final int maxRetries;
  final Duration timeout;
  final http.Client _http;

  ProxyAIClient({
    required this.baseUri,
    required this.task,
    this.idToken = firebaseIdToken,
    http.Client? httpClient,
    this.maxRetries = 2,
    this.timeout = const Duration(minutes: 10),
  }) : _http = httpClient ?? http.Client();

  /// A client for [task] on the server named by [aiServerUrl].
  factory ProxyAIClient.fromEnvironment(String task) =>
      ProxyAIClient(baseUri: Uri.parse(aiServerUrl), task: task);

  Uri _endpoint(String path) => baseUri.replace(
    path: '${baseUri.path.replaceAll(RegExp(r'/+$'), '')}/$path',
  );

  Future<Map<String, String>> _headers() async {
    final token = await idToken();
    if (token == null || token.isEmpty) {
      throw const AIException('Sign in to your account to use the AI.');
    }
    return {
      'authorization': 'Bearer $token',
      'content-type': 'application/json',
    };
  }

  @override
  Future<Map<String, dynamic>> createMessage(
    Map<String, dynamic> body, {
    List<String> betas = const [],
  }) async {
    final headers = await _headers();
    final encoded = jsonEncode({'task': task, 'betas': betas, 'body': body});

    for (var attempt = 0; ; attempt++) {
      try {
        final response = await _http
            .post(_endpoint('messages'), headers: headers, body: encoded)
            .timeout(timeout);
        _noteAllowance(response);
        if (response.statusCode == 200) {
          return jsonDecode(utf8.decode(response.bodyBytes))
              as Map<String, dynamic>;
        }
        final error = errorFrom(response);
        if (!error.retryable || attempt >= maxRetries) throw error;
        await Future.delayed(_backoff(attempt));
      } on SocketException {
        if (attempt >= maxRetries) {
          throw const AIException(
            'No internet connection. Check your network and try again.',
            retryable: true,
          );
        }
        await Future.delayed(_backoff(attempt));
      } on TimeoutException {
        throw const AIException(
          'The request took too long. Try again, or use fewer photos.',
          retryable: true,
        );
      }
    }
  }

  /// Asks the server for today's allowance without using any of it.
  Future<AiAllowance?> fetchAllowance() async {
    final response = await _http
        .get(_endpoint('allowance'), headers: await _headers())
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) throw errorFrom(response);
    return _noteAllowance(response);
  }

  AiAllowance? _noteAllowance(http.Response response) {
    final allowance = AiAllowance.fromHeaders(response.headers);
    if (allowance != null) aiAllowance.value = allowance;
    return allowance;
  }

  @override
  void close() => _http.close();

  static Duration _backoff(int attempt) =>
      Duration(milliseconds: 1000 * (1 << attempt));

  static AIException errorFrom(http.Response response) {
    final status = response.statusCode;
    String? serverMessage;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      serverMessage = (decoded['error'] as Map?)?['message'] as String?;
    } catch (_) {
      // Non-JSON error body; fall back to the status.
    }
    final detail = serverMessage == null ? '' : ' ($serverMessage)';
    return switch (status) {
      401 => AIException(
        'Your sign-in has expired. Sign out and back in, then retry.',
        statusCode: status,
      ),
      402 => AIException(
        'You\'ve used today\'s AI allowance. Nothing is lost: this waits '
        'and you can retry tomorrow, or after a reward video adds more.',
        statusCode: status,
      ),
      400 || 404 || 413 => AIException(
        'The request was rejected$detail.',
        statusCode: status,
      ),
      429 => AIException(
        'The AI is busy right now. Wait a minute and retry.',
        statusCode: status,
        retryable: true,
      ),
      _ when status >= 500 => AIException(
        'The AI service is temporarily unavailable ($status). Try again '
        'soon.',
        statusCode: status,
        retryable: true,
      ),
      _ => AIException(
        'Unexpected AI server error $status$detail.',
        statusCode: status,
      ),
    };
  }
}
