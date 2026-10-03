import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'screens/tutorial_screen.dart';
import 'services/auth_service.dart';
import 'state/library_scope.dart';

const appName = 'EventLens';

/// Root of the app. Without an account only the tutorial is available;
/// with the biometric lock on, the app asks for it every time it opens.
class EventLensApp extends StatefulWidget {
  const EventLensApp({super.key});

  static ThemeData _theme(Brightness brightness) => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF3F51B5),
      brightness: brightness,
    ),
    useMaterial3: true,
  );

  @override
  State<EventLensApp> createState() => _EventLensAppState();
}

class _EventLensAppState extends State<EventLensApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Time away before the fingerprint/face lock is asked for again. Short
  /// trips (the camera, the share sheet, a rewarded video) don't relock;
  /// the app is hidden from the recent-apps screen meanwhile.
  static const relockAfter = Duration(seconds: 30);

  DateTime? _pausedAt;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pausedAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final away = _pausedAt;
      _pausedAt = null;
      if (away != null && DateTime.now().difference(away) >= relockAfter) {
        context.read<BiometricLock>().lockAgain();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = context.select<AuthService, String?>((a) => a.user?.uid);
    final locked = !context.select<BiometricLock, bool>((l) => l.unlocked);
    return MaterialApp(
      // A different account starts from a clean screen stack, so no screen
      // from the last person's library stays open.
      key: ValueKey(uid),
      title: appName,
      debugShowCheckedModeBanner: false,
      theme: EventLensApp._theme(Brightness.light),
      darkTheme: EventLensApp._theme(Brightness.dark),
      home: uid == null ? const TutorialScreen() : const HomeScreen(),
      // The account's library sits above the navigator so every screen
      // pushed from Home can reach it. Locking covers the screens instead
      // of closing the library, so work in progress (an AI description,
      // a camera trip) carries on behind the lock.
      builder: (context, navigator) {
        if (uid == null || navigator == null) {
          return navigator ?? const SizedBox.shrink();
        }
        return LibraryScope(
          uid: uid,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ExcludeSemantics(
                excluding: locked,
                child: AbsorbPointer(absorbing: locked, child: navigator),
              ),
              if (locked)
                Overlay(
                  initialEntries: [
                    OverlayEntry(builder: (_) => const LockScreen()),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}
