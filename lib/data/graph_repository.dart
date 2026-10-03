import 'package:sqflite/sqflite.dart';

import '../models/memory_graph.dart';

/// Stores the latest AI-organised timeline. Only the newest is kept.
class GraphRepository {
  final Database db;

  GraphRepository(this.db);

  Future<GraphSnapshot?> latest() async {
    final rows = await db.query(
      'graph_snapshots',
      orderBy: 'created_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : GraphSnapshot.fromRow(rows.first);
  }

  Future<void> replace(GraphSnapshot snapshot) => db.transaction((txn) async {
    await txn.delete('graph_snapshots');
    await txn.insert('graph_snapshots', snapshot.toRow());
  });
}
