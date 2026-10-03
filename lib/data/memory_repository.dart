import 'package:sqflite/sqflite.dart';

import '../models/memory_item.dart';

class MemoryRepository {
  final Database db;

  MemoryRepository(this.db);

  Future<List<MemoryItem>> all() async {
    final rows = await db.query('memories', orderBy: 'kind, created_at');
    return rows.map(MemoryItem.fromRow).toList();
  }

  Future<void> save(MemoryItem item) => db.insert('memories', item.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> delete(String id) =>
      db.delete('memories', where: 'id = ?', whereArgs: [id]);
}
