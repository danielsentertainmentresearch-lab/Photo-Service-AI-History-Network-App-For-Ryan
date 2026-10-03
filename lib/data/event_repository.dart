import 'package:sqflite/sqflite.dart';

import '../models/event.dart';

class EventRepository {
  final Database db;

  EventRepository(this.db);

  Future<List<LifeEvent>> all() async {
    final rows = await db.query('events', orderBy: 'occurred_at DESC');
    final images = await _imagesByEvent();
    return rows
        .map((r) =>
            LifeEvent.fromRow(r, images: images[r['id'] as String] ?? const []))
        .toList();
  }

  Future<LifeEvent?> byId(String id) async {
    final rows = await db.query('events', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return LifeEvent.fromRow(rows.first, images: await imagesFor(id));
  }

  /// Saves the event row and replaces its image list in one transaction.
  Future<void> save(LifeEvent event) async {
    await db.transaction((txn) async {
      // Update-then-insert rather than INSERT OR REPLACE: a replace deletes
      // the row first, which would fire ON DELETE actions on linked memories.
      final updated = await txn.update('events', event.toRow(),
          where: 'id = ?', whereArgs: [event.id]);
      if (updated == 0) await txn.insert('events', event.toRow());
      await txn.delete('event_images',
          where: 'event_id = ?', whereArgs: [event.id]);
      for (final image in event.images) {
        await txn.insert('event_images', image.toRow());
      }
    });
  }

  /// Updates only the event row, leaving images untouched.
  Future<void> update(LifeEvent event) => db.update('events', event.toRow(),
      where: 'id = ?', whereArgs: [event.id]);

  Future<void> delete(String id) =>
      db.delete('events', where: 'id = ?', whereArgs: [id]);

  Future<List<EventImage>> imagesFor(String eventId) async {
    final rows = await db.query('event_images',
        where: 'event_id = ?', whereArgs: [eventId], orderBy: 'position');
    return rows.map(EventImage.fromRow).toList();
  }

  Future<Map<String, List<EventImage>>> _imagesByEvent() async {
    final rows = await db.query('event_images', orderBy: 'position');
    final result = <String, List<EventImage>>{};
    for (final row in rows) {
      final image = EventImage.fromRow(row);
      result.putIfAbsent(image.eventId, () => []).add(image);
    }
    return result;
  }

  /// Any event left mid-description (e.g. the app was killed) is marked
  /// failed on startup so the user can retry it.
  Future<void> recoverInterrupted() => db.update(
        'events',
        {
          'status': EventStatus.failed.name,
          'error': 'Interrupted before the description finished. Tap retry.',
        },
        where: 'status = ?',
        whereArgs: [EventStatus.describing.name],
      );
}
