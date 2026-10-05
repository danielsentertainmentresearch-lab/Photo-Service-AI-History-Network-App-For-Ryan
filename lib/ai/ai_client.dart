/// Error from an AI backend, with a message suitable for showing the user.
class AIException implements Exception {
  final int? statusCode;
  final String message;
  final bool retryable;

  const AIException(this.message, {this.statusCode, this.retryable = false});

  @override
  String toString() => message;
}

/// The contract every AI backend implements, so the describer, graph
/// builder, labeler and advisor don't depend on one provider.
///
/// Requests and responses use the Claude Messages API shape: [body] is a
/// Messages request and the result is a Messages response. A backend that
/// speaks another format translates both ways. Throws [AIException] with a
/// user-facing message on failure.
abstract interface class AIClient {
  Future<Map<String, dynamic>> createMessage(
    Map<String, dynamic> body, {
    List<String> betas,
  });

  void close();
}
