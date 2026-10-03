import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'screens/tutorial_screen.dart';
import 'services/auth_service.dart';

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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Lock again when the app goes to the background.
    if (state == AppLifecycleState.paused) {
      context.read<BiometricLock>().lockAgain();
    }
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = context.select<AuthService, bool>((a) => a.user != null);
    final unlocked = context.select<BiometricLock, bool>((l) => l.unlocked);
    return MaterialApp(
      title: appName,
      debugShowCheckedModeBanner: false,
      theme: EventLensApp._theme(Brightness.light),
      darkTheme: EventLensApp._theme(Brightness.dark),
      home: !signedIn
          ? const TutorialScreen()
          : !unlocked
          ? const LockScreen()
          : const HomeScreen(),
    );
  }
}
