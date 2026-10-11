import 'dart:convert';

import 'memory_item.dart';

/// The app's own memory (docs/MEMORY_ARCHITECTURE.md, approved 11 Oct 2026).
///
/// Memory is the AI's: people never add, edit or delete points. They can fix
/// a name's spelling (which reaches every version) and erase everything at
/// once. Nothing else ever changes a stored row: a revision, an archiving or
/// a retirement writes a new version that links back to the one before.

/// A point the AI uses.
const pointActive = 'active';

/// A point kept for history; only the dream pass may revive it.
const pointArchived = 'archived';

/// A point the AI no longer holds true.
const pointRetired = 'retired';

const pointStatuses = [pointActive, pointArchived, pointRetired];

const polarities = ['negative', 'mixed', 'neutral', 'positive'];
const intensities = ['low', 'medium', 'high'];

/// Sentiment source for points moved in from the old memories table, until
/// a dream pass revises them.
const migratedSentiment = 'migrated';

/// Sentiment source for points saved before any dream pass has read them
/// (answers to the AI's questions).
const pendingSentiment = 'pending';

/// How an event or a person felt: a data point, never tone (rule 5).
class Sentiment {
  final String polarity;
  final String intensity;

  /// Where the reading came from: a dream pass, or [migratedSentiment].
  final String source;

  const Sentiment({
    required this.polarity,
    required this.intensity,
    required this.source,
  });

  /// Unknown values fall back to the calmest reading instead of failing.
  factory Sentiment.parse(String? polarity, String? intensity, String source) =>
      Sentiment(
        polarity: polarities.contains(polarity) ? polarity! : 'neutral',
        intensity: intensities.contains(intensity) ? intensity! : 'low',
        source: source,
      );

  /// "pos:med", the compact form used in prompts.
  String get compact =>
      '${const {'negative': 'neg', 'mixed': 'mix', 'neutral': 'neut', 'positive': 'pos'}[polarity]}:'
      '${const {'low': 'low', 'medium': 'med', 'high': 'high'}[intensity]}';

  @override
  bool operator ==(Object other) =>
      other is Sentiment &&
      other.polarity == polarity &&
      other.intensity == intensity &&
      other.source == source;

  @override
  int get hashCode => Object.hash(polarity, intensity, source);
}

/// One version of one learned point. All versions of a point share
/// [pointId]; [parentId] links each version to the row before it.
class LearnedPoint {
  /// This row (this version).
  final String id;

  /// The point across all its versions; what prompts and the dream pass use.
  final String pointId;
  final int version;
  final String? parentId;

  final String kind;
  final String content;
  final Sentiment sentiment;

  /// `ai`, `user` or `answer` (the person's answer to the AI's question).
  final String source;

  /// The events this point was learned from: cited by the AI, checked by the
  /// app.
  final List<String> eventIds;
  final String status;

  /// Why this version exists ("revised: ...", "archived: ..."); empty for a
  /// first version.
  final String reason;
  final DateTime createdAt;

  const LearnedPoint({
    required this.id,
    required this.pointId,
    required this.version,
    required this.kind,
    required this.content,
    required this.sentiment,
    required this.source,
    required this.eventIds,
    required this.status,
    required this.createdAt,
    this.parentId,
    this.reason = '',
  });

  bool get isActive => status == pointActive;

  /// The view the rest of the app reads (prompts, the learning page, the
  /// timeline graph and the export).
  MemoryItem toMemoryItem() => MemoryItem(
    id: pointId,
    kind: kind,
    content: content,
    source: source,
    eventId: eventIds.isEmpty ? null : eventIds.first,
    createdAt: createdAt,
  );

  factory LearnedPoint.fromRow(Map<String, Object?> row) => LearnedPoint(
    id: row['id'] as String,
    pointId: row['point_id'] as String,
    version: row['version'] as int,
    parentId: row['parent_id'] as String?,
    kind: row['kind'] as String,
    content: row['content'] as String,
    sentiment: Sentiment.parse(
      row['polarity'] as String?,
      row['intensity'] as String?,
      row['sentiment_source'] as String,
    ),
    source: row['source'] as String,
    eventIds: [
      for (final id in jsonDecode(row['event_ids'] as String) as List)
        id as String,
    ],
    status: row['status'] as String,
    reason: row['reason'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
  );

  Map<String, Object?> toRow() => {
    'id': id,
    'point_id': pointId,
    'version': version,
    'parent_id': parentId,
    'kind': kind,
    'content': content,
    'polarity': sentiment.polarity,
    'intensity': sentiment.intensity,
    'sentiment_source': sentiment.source,
    'source': source,
    'event_ids': jsonEncode(eventIds),
    'status': status,
    'reason': reason,
    'created_at': createdAt.millisecondsSinceEpoch,
  };
}

/// One version of the dream state: the foundation statements and themes the
/// dream pass holds about the person's story.
class DreamState {
  final String id;
  final int version;
  final String? parentId;
  final List<String> foundationStatements;
  final List<String> themes;
  final List<String> eventIds;
  final DateTime createdAt;

  const DreamState({
    required this.id,
    required this.version,
    required this.foundationStatements,
    required this.themes,
    required this.eventIds,
    required this.createdAt,
    this.parentId,
  });

  static List<String> _list(Object? json) => [
    for (final s in jsonDecode(json as String) as List) s as String,
  ];

  factory DreamState.fromRow(Map<String, Object?> row) => DreamState(
    id: row['id'] as String,
    version: row['version'] as int,
    parentId: row['parent_id'] as String?,
    foundationStatements: _list(row['foundation_statements']),
    themes: _list(row['themes']),
    eventIds: _list(row['event_ids']),
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
  );

  Map<String, Object?> toRow() => {
    'id': id,
    'version': version,
    'parent_id': parentId,
    'foundation_statements': jsonEncode(foundationStatements),
    'themes': jsonEncode(themes),
    'event_ids': jsonEncode(eventIds),
    'created_at': createdAt.millisecondsSinceEpoch,
  };
}
