import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../ai/dream_reply.dart';
import '../models/learned_point.dart';
import '../models/memory_item.dart';

/// The app's own memory: learned points and the dream state, each kept as
/// versions (docs/MEMORY_ARCHITECTURE.md). A stored row is never changed,
/// with one exception: a name spelling fix, which is the person's
/// correction of a name and reaches every version.
class MemoryRepository {
  final Database db;
  final Uuid _uuid = const Uuid();

  MemoryRepository(this.db);

  /// The latest version of every point, whatever its status.
  Future<List<LearnedPoint>> current() async {
    final rows = await db.rawQuery('''
      SELECT p.* FROM learned_points p
      WHERE p.version = (
        SELECT MAX(q.version) FROM learned_points q WHERE q.point_id = p.point_id
      )
      ORDER BY p.kind, p.created_at
    ''');
    return rows.map(LearnedPoint.fromRow).toList();
  }

  /// What the AI currently holds: the latest version of every active point,
  /// as the rest of the app reads it.
  Future<List<MemoryItem>> all() async => [
    for (final p in await current())
      if (p.isActive) p.toMemoryItem(),
  ];

  /// Every version of [pointId], oldest first.
  Future<List<LearnedPoint>> history(String pointId) async {
    final rows = await db.query(
      'learned_points',
      where: 'point_id = ?',
      whereArgs: [pointId],
      orderBy: 'version',
    );
    return rows.map(LearnedPoint.fromRow).toList();
  }

  /// Every stored version of every point (the export and the tests).
  Future<List<LearnedPoint>> allVersions() async {
    final rows = await db.query('learned_points', orderBy: 'point_id, version');
    return rows.map(LearnedPoint.fromRow).toList();
  }

  /// A new point, at version 1.
  Future<LearnedPoint> add({
    required String kind,
    required String content,
    required String source,
    required Sentiment sentiment,
    List<String> eventIds = const [],
    DateTime? now,
  }) async {
    final id = _uuid.v4();
    final point = LearnedPoint(
      id: id,
      pointId: id,
      version: 1,
      kind: kind,
      content: content,
      sentiment: sentiment,
      source: source,
      eventIds: eventIds,
      status: pointActive,
      createdAt: now ?? DateTime.now(),
    );
    await db.insert('learned_points', point.toRow());
    return point;
  }

  /// Writes the next version of [pointId], linked to the one before. Fields
  /// left null carry over. Returns null when there is no such point.
  Future<LearnedPoint?> revise(
    String pointId, {
    required String reason,
    String? content,
    Sentiment? sentiment,
    List<String>? eventIds,
    String? status,
    DateTime? now,
  }) => db.transaction((txn) async {
    final rows = await txn.query(
      'learned_points',
      where: 'point_id = ?',
      whereArgs: [pointId],
      orderBy: 'version DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final last = LearnedPoint.fromRow(rows.single);
    final next = LearnedPoint(
      id: _uuid.v4(),
      pointId: pointId,
      version: last.version + 1,
      parentId: last.id,
      kind: last.kind,
      content: content ?? last.content,
      sentiment: sentiment ?? last.sentiment,
      source: last.source,
      eventIds: eventIds ?? last.eventIds,
      status: status ?? last.status,
      reason: reason,
      createdAt: now ?? DateTime.now(),
    );
    await txn.insert('learned_points', next.toRow());
    return next;
  });

  /// Archives [pointId] as a new version; the point is kept for history.
  Future<LearnedPoint?> archive(String pointId, String reason) =>
      revise(pointId, reason: reason, status: pointArchived);

  /// The latest dream state, or null before the first dream pass.
  Future<DreamState?> dream() async {
    final rows = await db.query(
      'dream_states',
      orderBy: 'version DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : DreamState.fromRow(rows.single);
  }

  /// Every version of the dream state, oldest first.
  Future<List<DreamState>> dreamHistory() async {
    final rows = await db.query('dream_states', orderBy: 'version');
    return rows.map(DreamState.fromRow).toList();
  }

  /// Writes the next version of the dream state.
  Future<DreamState> saveDream({
    required List<String> foundationStatements,
    required List<String> themes,
    required List<String> eventIds,
    DateTime? now,
  }) => db.transaction((txn) async {
    final rows = await txn.query(
      'dream_states',
      orderBy: 'version DESC',
      limit: 1,
    );
    final last = rows.isEmpty ? null : DreamState.fromRow(rows.single);
    final next = DreamState(
      id: _uuid.v4(),
      version: (last?.version ?? 0) + 1,
      parentId: last?.id,
      foundationStatements: foundationStatements,
      themes: themes,
      eventIds: eventIds,
      createdAt: now ?? DateTime.now(),
    );
    await txn.insert('dream_states', next.toRow());
    return next;
  });

  /// Saves one checked dream pass in a single transaction, so a pass is
  /// stored whole or not at all. Every change is a new version; a revision
  /// keeps the point's earlier evidence and adds the new.
  Future<void> applyDream(DreamChanges changes, {DateTime? now}) =>
      db.transaction((txn) async {
        final at = now ?? DateTime.now();
        Future<LearnedPoint?> last(String pointId) async {
          final rows = await txn.query(
            'learned_points',
            where: 'point_id = ?',
            whereArgs: [pointId],
            orderBy: 'version DESC',
            limit: 1,
          );
          return rows.isEmpty ? null : LearnedPoint.fromRow(rows.single);
        }

        Future<void> next(
          LearnedPoint before, {
          required String reason,
          required List<String> eventIds,
          String? content,
          Sentiment? sentiment,
          String? status,
        }) => txn.insert(
          'learned_points',
          LearnedPoint(
            id: _uuid.v4(),
            pointId: before.pointId,
            version: before.version + 1,
            parentId: before.id,
            kind: before.kind,
            content: content ?? before.content,
            sentiment: sentiment ?? before.sentiment,
            source: before.source,
            eventIds: {...before.eventIds, ...eventIds}.toList(),
            status: status ?? before.status,
            reason: reason,
            createdAt: at,
          ).toRow(),
        );

        for (final a in changes.adds) {
          final id = _uuid.v4();
          await txn.insert(
            'learned_points',
            LearnedPoint(
              id: id,
              pointId: id,
              version: 1,
              kind: a.kind,
              content: a.content,
              sentiment: a.sentiment,
              source: 'ai',
              eventIds: a.eventIds,
              status: pointActive,
              reason: a.reason,
              createdAt: at,
            ).toRow(),
          );
        }
        for (final r in changes.revisions) {
          final before = await last(r.pointId);
          // Retired points never come back.
          if (before == null || before.status == pointRetired) continue;
          await next(
            before,
            reason: '${r.revives ? 'revived' : 'revised'}: ${r.reason}',
            eventIds: r.eventIds,
            content: r.content,
            sentiment: r.sentiment,
            status: pointActive,
          );
        }
        for (final s in changes.statusChanges) {
          final before = await last(s.pointId);
          if (before == null || !before.isActive) continue;
          await next(
            before,
            reason: '${s.status}: ${s.reason}',
            eventIds: s.eventIds,
            status: s.status,
          );
        }
        final dream = changes.dream;
        if (dream != null) {
          final rows = await txn.query(
            'dream_states',
            orderBy: 'version DESC',
            limit: 1,
          );
          final previous = rows.isEmpty
              ? null
              : DreamState.fromRow(rows.single);
          await txn.insert(
            'dream_states',
            DreamState(
              id: _uuid.v4(),
              version: (previous?.version ?? 0) + 1,
              parentId: previous?.id,
              foundationStatements: dream.foundationStatements,
              themes: dream.themes,
              eventIds: dream.eventIds,
              createdAt: at,
            ).toRow(),
          );
        }
      });

  /// Applies a name spelling fix to every version of every point and of the
  /// dream state. Returns how many rows changed.
  Future<int> fixSpelling(String Function(String) fix) =>
      db.transaction((txn) async {
        var changed = 0;
        for (final row in await txn.query('learned_points')) {
          final content = row['content'] as String;
          final next = fix(content);
          if (next != content) {
            await txn.update(
              'learned_points',
              {'content': next},
              where: 'id = ?',
              whereArgs: [row['id']],
            );
            changed++;
          }
        }
        for (final row in await txn.query('dream_states')) {
          final dream = DreamState.fromRow(row);
          final statements = dream.foundationStatements.map(fix).toList();
          final themes = dream.themes.map(fix).toList();
          final fixed = DreamState(
            id: dream.id,
            version: dream.version,
            parentId: dream.parentId,
            foundationStatements: statements,
            themes: themes,
            eventIds: dream.eventIds,
            createdAt: dream.createdAt,
          ).toRow();
          if (fixed.toString() != row.toString()) {
            await txn.update(
              'dream_states',
              fixed,
              where: 'id = ?',
              whereArgs: [dream.id],
            );
            changed++;
          }
        }
        return changed;
      });

  /// Erases everything the AI remembers: every point, every version and the
  /// dream state with its history (the privacy policy's "Erase what the AI
  /// remembers").
  Future<void> deleteAll() => db.transaction((txn) async {
    await txn.delete('learned_points');
    await txn.delete('dream_states');
  });
}
