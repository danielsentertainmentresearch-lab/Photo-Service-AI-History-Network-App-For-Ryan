import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/app_database.dart';
import 'data/event_repository.dart';
import 'data/graph_repository.dart';
import 'data/image_vault.dart';
import 'data/memory_repository.dart';
import 'services/auth_service.dart';
import 'services/rewards_service.dart';
import 'services/settings_service.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final db = await AppDatabase.open();
  final docs = await getApplicationDocumentsDirectory();
  final state = AppState(
    events: EventRepository(db),
    memoryRepo: MemoryRepository(db),
    graphRepo: GraphRepository(db),
    vault: ImageVault(Directory(p.join(docs.path, 'vault'))),
    settings: await SettingsService.create(),
  );
  await state.load();

  AuthService auth = LocalReviewAuthService(prefs);
  if (FirebaseConfig.configured) {
    try {
      auth = await FirebaseAuthService.create();
    } catch (e) {
      debugPrint('Firebase unavailable, accounts disabled: $e');
    }
  }

  // Ads load in the background; failures only affect unlocking colours.
  AdMobRewardedProvider.initialize().catchError(
    (Object e) => debugPrint('Ads unavailable: $e'),
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: state),
        ChangeNotifierProvider<AuthService>.value(value: auth),
        ChangeNotifierProvider(create: (_) => BiometricLock(prefs)),
        ChangeNotifierProvider(
          create: (_) => RingUnlocks(prefs, AdMobRewardedProvider()),
        ),
      ],
      child: const EventLensApp(),
    ),
  );
}
