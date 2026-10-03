import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'data/app_database.dart';
import 'data/event_repository.dart';
import 'data/image_vault.dart';
import 'data/memory_repository.dart';
import 'services/settings_service.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final db = await AppDatabase.open();
  final docs = await getApplicationDocumentsDirectory();
  final state = AppState(
    events: EventRepository(db),
    memoryRepo: MemoryRepository(db),
    vault: ImageVault(Directory(p.join(docs.path, 'vault'))),
    settings: await SettingsService.create(),
  );
  await state.load();

  runApp(ChangeNotifierProvider.value(value: state, child: const EventLensApp()));
}
