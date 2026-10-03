/// Kinds of long-term memory. Kept small so the AI can classify reliably.
const memoryKinds = ['person', 'place', 'fact', 'preference', 'ongoing'];

String memoryKindLabel(String kind) => switch (kind) {
      'person' => 'Person',
      'place' => 'Place',
      'preference' => 'Preference',
      'ongoing' => 'Ongoing situation',
      _ => 'Fact',
    };

/// A durable piece of context ("contextual memory") the AI reads before
/// describing any event, e.g. "Sam is my younger brother; he plays drums".
class MemoryItem {
  final String id;
  final String kind;
  final String content;

  /// 'user' when typed by the user, 'ai' when accepted from an AI suggestion.
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
