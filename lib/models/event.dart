import 'dart:convert';

/// Lifecycle of an event's AI account.
enum EventStatus { draft, describing, described, failed }

/// A memory the AI proposed while describing an event. The user decides
/// whether it is promoted into long-term memory.
class MemorySuggestion {
  final String kind;
  final String content;

  const MemorySuggestion({required this.kind, required this.content});

  factory MemorySuggestion.fromJson(Map<String, dynamic> json) =>
      MemorySuggestion(
        kind: (json['kind'] as String?) ?? 'fact',
        content: (json['content'] as String?) ?? '',
      );

  Map<String, dynamic> toJson() => {'kind': kind, 'content': content};
}

/// One photo stored in the on-device vault.
class EventImage {
  final String id;
  final String eventId;

  /// File name relative to the vault directory (never an absolute path, so the
  /// database survives the app's data directory moving).
  final String fileName;
  final int position;

  const EventImage({
    required this.id,
    required this.eventId,
    required this.fileName,
    required this.position,
  });

  factory EventImage.fromRow(Map<String, Object?> row) => EventImage(
        id: row['id'] as String,
        eventId: row['event_id'] as String,
        fileName: row['file_name'] as String,
        position: row['position'] as int,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'event_id': eventId,
        'file_name': fileName,
        'position': position,
      };
}

/// A recorded event: the user's photos and in-the-moment notes (working
/// memory), plus the AI's detailed account of it.
class LifeEvent {
  final String id;
  final String title;

  /// What the user knew at capture time: who was there, mood, what was going
  /// on. This is the "working memory" handed to the AI.
  final String notes;
  final String location;
  final DateTime occurredAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  final String summary;
  final String description;
  final List<String> people;
  final List<String> places;
  final List<String> tags;
  final List<MemorySuggestion> suggestions;

  final EventStatus status;
  final String? error;
  final String? model;

  final List<EventImage> images;

  const LifeEvent({
    required this.id,
    required this.title,
    required this.notes,
    required this.location,
    required this.occurredAt,
    required this.createdAt,
    required this.updatedAt,
    this.summary = '',
    this.description = '',
    this.people = const [],
    this.places = const [],
    this.tags = const [],
    this.suggestions = const [],
    this.status = EventStatus.draft,
    this.error,
    this.model,
    this.images = const [],
  });

  bool get hasAccount => description.trim().isNotEmpty;

  LifeEvent copyWith({
    String? title,
    String? notes,
    String? location,
    DateTime? occurredAt,
    DateTime? updatedAt,
    String? summary,
    String? description,
    List<String>? people,
    List<String>? places,
    List<String>? tags,
    List<MemorySuggestion>? suggestions,
    EventStatus? status,
    String? error,
    bool clearError = false,
    String? model,
    List<EventImage>? images,
  }) {
    return LifeEvent(
      id: id,
      title: title ?? this.title,
      notes: notes ?? this.notes,
      location: location ?? this.location,
      occurredAt: occurredAt ?? this.occurredAt,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      summary: summary ?? this.summary,
      description: description ?? this.description,
      people: people ?? this.people,
      places: places ?? this.places,
      tags: tags ?? this.tags,
      suggestions: suggestions ?? this.suggestions,
      status: status ?? this.status,
      error: clearError ? null : (error ?? this.error),
      model: model ?? this.model,
      images: images ?? this.images,
    );
  }

  factory LifeEvent.fromRow(Map<String, Object?> row,
      {List<EventImage> images = const []}) {
    List<String> strings(Object? raw) => raw == null || raw == ''
        ? const []
        : (jsonDecode(raw as String) as List).cast<String>();
    final rawSuggestions = row['suggestions'] as String?;
    return LifeEvent(
      id: row['id'] as String,
      title: (row['title'] as String?) ?? '',
      notes: (row['notes'] as String?) ?? '',
      location: (row['location'] as String?) ?? '',
      occurredAt: DateTime.fromMillisecondsSinceEpoch(row['occurred_at'] as int),
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
      summary: (row['summary'] as String?) ?? '',
      description: (row['description'] as String?) ?? '',
      people: strings(row['people']),
      places: strings(row['places']),
      tags: strings(row['tags']),
      suggestions: rawSuggestions == null || rawSuggestions.isEmpty
          ? const []
          : (jsonDecode(rawSuggestions) as List)
              .map((e) => MemorySuggestion.fromJson(e as Map<String, dynamic>))
              .toList(),
      status: EventStatus.values.byName((row['status'] as String?) ?? 'draft'),
      error: row['error'] as String?,
      model: row['model'] as String?,
      images: images,
    );
  }

  Map<String, Object?> toRow() => {
        'id': id,
        'title': title,
        'notes': notes,
        'location': location,
        'occurred_at': occurredAt.millisecondsSinceEpoch,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
        'summary': summary,
        'description': description,
        'people': jsonEncode(people),
        'places': jsonEncode(places),
        'tags': jsonEncode(tags),
        'suggestions': jsonEncode(suggestions.map((s) => s.toJson()).toList()),
        'status': status.name,
        'error': error,
        'model': model,
      };
}
