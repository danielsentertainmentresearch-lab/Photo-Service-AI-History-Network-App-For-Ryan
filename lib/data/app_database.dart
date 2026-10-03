import 'package:sqflite/sqflite.dart';

/// Opens (and migrates) the on-device SQLite database.
///
/// [factory] and [path] are injectable so tests can use an in-memory FFI
/// database instead of the platform plugin.
class AppDatabase {
  static const int version = 3;

  static Future<Database> open({DatabaseFactory? factory, String? path}) async {
    final dbFactory = factory ?? databaseFactory;
    final dbPath = path ?? '${await dbFactory.getDatabasesPath()}/eventlens.db';
    return dbFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: version,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) async {
          await _createV1(db);
          await _createV2(db);
          await _createV3(db);
        },
        onUpgrade: (db, oldVersion, _) async {
          if (oldVersion < 2) await _createV2(db);
          if (oldVersion < 3) await _createV3(db);
        },
      ),
    );
  }

  static Future<void> _createV1(Database db) async {
    await db.execute('''
      CREATE TABLE events (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT '',
        location TEXT NOT NULL DEFAULT '',
        occurred_at INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        summary TEXT NOT NULL DEFAULT '',
        description TEXT NOT NULL DEFAULT '',
        people TEXT NOT NULL DEFAULT '[]',
        places TEXT NOT NULL DEFAULT '[]',
        tags TEXT NOT NULL DEFAULT '[]',
        suggestions TEXT NOT NULL DEFAULT '[]',
        status TEXT NOT NULL DEFAULT 'draft',
        error TEXT,
        model TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_events_occurred_at ON events (occurred_at DESC)',
    );
    await db.execute('''
      CREATE TABLE event_images (
        id TEXT PRIMARY KEY,
        event_id TEXT NOT NULL REFERENCES events (id) ON DELETE CASCADE,
        file_name TEXT NOT NULL,
        position INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_event_images_event ON event_images (event_id)',
    );
    await db.execute('''
      CREATE TABLE memories (
        id TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        content TEXT NOT NULL,
        source TEXT NOT NULL,
        event_id TEXT REFERENCES events (id) ON DELETE SET NULL,
        created_at INTEGER NOT NULL
      )
    ''');
  }

  /// v2: the AI-organised timeline (chapters, links, themes).
  static Future<void> _createV2(Database db) async {
    await db.execute('''
      CREATE TABLE graph_snapshots (
        id TEXT PRIMARY KEY,
        created_at INTEGER NOT NULL,
        event_count INTEGER NOT NULL,
        model TEXT,
        data TEXT NOT NULL
      )
    ''');
  }

  /// v3: optional place coordinates and weather on events.
  static Future<void> _createV3(Database db) async {
    await db.execute('ALTER TABLE events ADD COLUMN latitude REAL');
    await db.execute('ALTER TABLE events ADD COLUMN longitude REAL');
    await db.execute('ALTER TABLE events ADD COLUMN weather TEXT');
  }
}
