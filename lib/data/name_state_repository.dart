import 'package:sqflite/sqflite.dart';

import '../models/name_state.dart';

class NameStateRepository {
  final Database db;

  NameStateRepository(this.db);

  Future<List<NameState>> all() async =>
      (await db.query('name_states')).map(NameState.fromRow).toList();

  /// Sets how [name] is kept; [nameAsUsual] simply forgets the choice.
  Future<void> set(String name, String kind, String state, DateTime now) =>
      state == nameAsUsual
      ? db.delete(
          'name_states',
          where: 'name = ? AND kind = ?',
          whereArgs: [name, kind],
        )
      : db.insert(
          'name_states',
          NameState(name: name, kind: kind, state: state, since: now).toRow(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
}
