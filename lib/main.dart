import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'app.dart';
import 'services/auth_service.dart';
import 'services/recents_privacy.dart';
import 'services/rewards_service.dart';
import 'state/library_scope.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final databasesDir = await getDatabasesPath();
  final documentsDir = (await getApplicationDocumentsDirectory()).path;

  AuthService auth = LocalReviewAuthService(prefs);
  if (FirebaseConfig.configured) {
    try {
      auth = await FirebaseAuthService.create();
    } catch (e) {
      debugPrint('Firebase unavailable, accounts disabled: $e');
    }
  }

  final privacy = RecentsPrivacy(prefs);
  await privacy.apply();

  // Ads load in the background; failures only affect video unlocks.
  AdMobRewardedProvider.initialize().catchError(
    (Object e) => debugPrint('Ads unavailable: $e'),
  );
  final RewardedVideoProvider videos = AdMobRewardedProvider();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>.value(value: auth),
        ChangeNotifierProvider(create: (_) => BiometricLock(prefs)),
        ChangeNotifierProvider.value(value: privacy),
        Provider<RewardedVideoProvider>.value(value: videos),
        Provider<LibraryOpener>.value(
          value: (uid) => openLibrary(
            uid: uid,
            prefs: prefs,
            videos: videos,
            databasesDir: databasesDir,
            documentsDir: documentsDir,
          ),
        ),
      ],
      child: const EventLensApp(showTitle: true),
    ),
  );
}
