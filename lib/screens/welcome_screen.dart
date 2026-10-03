import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../state/app_state.dart';
import 'home_screen.dart';

/// First-run screen: explains what the app does and where data goes.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 24),
            Icon(Icons.auto_stories, size: 72, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('Welcome to $appName',
                style: theme.textTheme.headlineMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            const _Point(
              icon: Icons.photo_library_outlined,
              title: 'Record events with photos',
              body: 'Add photos and a few quick notes about what is happening '
                  'right now.',
            ),
            const _Point(
              icon: Icons.auto_awesome_outlined,
              title: 'AI writes the full story',
              body: 'The AI turns your photos and notes into a richly detailed '
                  'account, remembering the people, places and events you '
                  'have recorded before.',
            ),
            const _Point(
              icon: Icons.lock_outline,
              title: 'Your library stays on your phone',
              body: 'Photos, notes and memories are stored only on this device. '
                  'When you ask for a description, that event\'s photos, notes '
                  'and your saved memories are sent to Anthropic\'s Claude API '
                  'using your own API key. Nothing else leaves your phone.',
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () async {
                await context.read<AppState>().settings.setOnboarded();
                if (!context.mounted) return;
                Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const HomeScreen()));
              },
              child: const Text('Get started'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _Point({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(body, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
