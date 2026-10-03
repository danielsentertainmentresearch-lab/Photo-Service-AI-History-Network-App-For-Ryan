import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'screens/welcome_screen.dart';
import 'state/app_state.dart';

const appName = 'EventLens';

class EventLensApp extends StatelessWidget {
  const EventLensApp({super.key});

  static ThemeData _theme(Brightness brightness) => ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3F51B5),
          brightness: brightness,
        ),
        useMaterial3: true,
      );

  @override
  Widget build(BuildContext context) {
    final onboarded = context.select<AppState, bool>(
        (s) => s.settings.onboarded);
    return MaterialApp(
      title: appName,
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: onboarded ? const HomeScreen() : const WelcomeScreen(),
    );
  }
}
