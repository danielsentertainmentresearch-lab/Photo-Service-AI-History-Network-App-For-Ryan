/// Kinds of long-term memory. Kept small so the AI can classify reliably.
const memoryKinds = ['person', 'place', 'fact', 'preference', 'ongoing'];

String memoryKindLabel(String kind) => switch (kind) {
  'person' => 'Person',
  'place' => 'Place',
  'preference' => 'Preference',
  'ongoing' => 'Ongoing situation',
  _ => 'Fact',
};

/// Marks memories that came from answering the AI's who/where questions.
/// Since database v8 they live in the app's own memory as learned points
/// with this source, their event as evidence (docs/MEMORY_ARCHITECTURE.md).
const answerSource = 'answer';

/// What the AI currently holds, as the rest of the app reads it: the latest
/// version of an active learned point (`lib/models/learned_point.dart`).
class MemoryItem {
  final String id;
  final String kind;
  final String content;

  /// 'user' when typed by the user, 'ai' when accepted from an AI suggestion,
  /// [answerSource] when it is the person's answer to an AI question.
  final String source;
  final String? eventId;
  final DateTime createdAt;

  const MemoryItem({
    required this.id,
    required this.kind,
    required this.content,
    required this.source,
    required this.createdAt,
    this.eventId,
  });

  MemoryItem copyWith({String? kind, String? content}) => MemoryItem(
    id: id,
    kind: kind ?? this.kind,
    content: content ?? this.content,
    source: source,
    eventId: eventId,
    createdAt: createdAt,
  );

  factory MemoryItem.fromRow(Map<String, Object?> row) => MemoryItem(
    id: row['id'] as String,
    kind: row['kind'] as String,
    content: row['content'] as String,
    source: row['source'] as String,
    eventId: row['event_id'] as String?,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
  );

  Map<String, Object?> toRow() => {
    'id': id,
    'kind': kind,
    'content': content,
    'source': source,
    'event_id': eventId,
    'created_at': createdAt.millisecondsSinceEpoch,
  };
}
