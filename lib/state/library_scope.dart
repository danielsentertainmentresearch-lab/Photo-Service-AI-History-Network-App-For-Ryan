import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../data/app_database.dart';
import '../data/event_repository.dart';
import '../data/graph_repository.dart';
import '../data/image_vault.dart';
import '../data/memory_repository.dart';
import '../data/name_state_repository.dart';
import '../services/insight_pass.dart';
import '../services/rewards_service.dart';
import '../services/settings_service.dart';
import 'app_state.dart';

/// Everything that belongs to one account on this phone.
class Library {
  final AppState state;
  final RingUnlocks unlocks;
  final WeatherPass weather;
  final InsightPass insights;
  final Database? db;

  Library({
    required this.state,
    required this.unlocks,
    required this.weather,
    required this.insights,
    this.db,
  });

  Future<void> close() async => db?.close();
}

/// Opens (or creates) the library for an account.
typedef LibraryOpener = Future<Library> Function(String uid);

/// File-name-safe form of an account id.
String libraryKey(String uid) {
  final safe = uid.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  return safe.isEmpty ? 'account' : safe;
}

/// Opens the library of [uid]: its own database, photo folder, settings,
/// API key, ring unlocks and weather pass, so people sharing a phone never
/// see each other's events.
///
/// The library from before accounts existed (one unnamed database and
/// photo folder) is handed to the first account that signs in on this
/// phone, together with its API key and settings.
Future<Library> openLibrary({
  required String uid,
  required SharedPreferences prefs,
  required RewardedVideoProvider videos,
  required String databasesDir,
  required String documentsDir,
  FlutterSecureStorage secure = const FlutterSecureStorage(),
  DatabaseFactory? factory,
}) async {
  final key = libraryKey(uid);
  final dbPath = p.join(databasesDir, 'eventlens_$key.db');
  final vaultDir = Directory(p.join(documentsDir, 'vaults', key));

  if (!(prefs.getBool(_legacyClaimedKey) ?? false)) {
    await _claimLegacyLibrary(
      key: key,
      prefs: prefs,
      secure: secure,
      dbPath: dbPath,
      vaultDir: vaultDir,
      databasesDir: databasesDir,
      documentsDir: documentsDir,
    );
  }

  final db = await AppDatabase.open(factory: factory, path: dbPath);
  final state = AppState(
    events: EventRepository(db),
    memoryRepo: MemoryRepository(db),
    graphRepo: GraphRepository(db),
    vault: ImageVault(vaultDir),
    settings: SettingsService(secure, prefs, scope: key),
    nameStateRepo: NameStateRepository(db),
  );
  await state.load();
  return Library(
    state: state,
    unlocks: RingUnlocks(prefs, videos, scope: key),
    weather: WeatherPass(prefs, videos, scope: key),
    insights: InsightPass(prefs, videos, scope: key),
    db: db,
  );
}

const _legacyClaimedKey = 'legacy_library_claimed';

Future<void> _claimLegacyLibrary({
  required String key,
  required SharedPreferences prefs,
  required FlutterSecureStorage secure,
  required String dbPath,
  required Directory vaultDir,
  required String databasesDir,
  required String documentsDir,
}) async {
  final oldDb = File(p.join(databasesDir, 'eventlens.db'));
  final oldVault = Directory(p.join(documentsDir, 'vault'));
  if (await oldDb.exists() && !await File(dbPath).exists()) {
    await oldDb.rename(dbPath);
    for (final suffix in ['-wal', '-shm', '-journal']) {
      final side = File('${oldDb.path}$suffix');
      if (await side.exists()) await side.rename('$dbPath$suffix');
    }
  }
  if (await oldVault.exists() && !await vaultDir.exists()) {
    await vaultDir.parent.create(recursive: true);
    await oldVault.rename(vaultDir.path);
  }
  final oldKey = await secure.read(key: 'anthropic_api_key');
  if (oldKey != null) {
    await secure.write(key: 'anthropic_api_key_$key', value: oldKey);
    await secure.delete(key: 'anthropic_api_key');
  }
  for (final name in [
    'model',
    'effort',
    'ring_unlocked_count',
    'ring_unlock_progress',
  ]) {
    final value = prefs.get(name);
    if (value is String) await prefs.setString('${name}_$key', value);
    if (value is int) await prefs.setInt('${name}_$key', value);
    if (value != null) await prefs.remove(name);
  }
  await prefs.setBool(_legacyClaimedKey, true);
}

/// Opens the signed-in account's library and provides it to [child].
class LibraryScope extends StatefulWidget {
  final String uid;
  final Widget child;

  const LibraryScope({super.key, required this.uid, required this.child});

  @override
  State<LibraryScope> createState() => _LibraryScopeState();
}

class _LibraryScopeState extends State<LibraryScope> {
  late final Future<Library> _library;

  @override
  void initState() {
    super.initState();
    _library = context.read<LibraryOpener>()(widget.uid);
  }

  @override
  void dispose() {
    _library.then((l) => l.close()).catchError((_) {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Library>(
      future: _library,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Your library couldn\'t be opened: ${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        final library = snapshot.data;
        if (library == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: library.state),
            ChangeNotifierProvider.value(value: library.unlocks),
            ChangeNotifierProvider.value(value: library.weather),
            ChangeNotifierProvider.value(value: library.insights),
          ],
          child: widget.child,
        );
      },
    );
  }
}
