import 'package:flutter/material.dart';

import '../ai/graph_builder.dart';
import '../app.dart';
import 'auth_screen.dart';

/// Shown to anyone without an account. It walks through the basics of the
/// app; using the app itself requires creating an account at the end.
class TutorialScreen extends StatefulWidget {
  const TutorialScreen({super.key});

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _Step {
  final IconData icon;
  final String title;
  final String body;

  const _Step(this.icon, this.title, this.body);
}

const _steps = [
  _Step(
    Icons.auto_stories,
    'Welcome to $appName',
    'Your life, remembered in detail. Record moments with photos and a few '
        'notes, and an AI writes the full story for you.',
  ),
  _Step(
    Icons.add_a_photo_outlined,
    'Record an event',
    'Tap New event, add up to 10 photos from your camera or gallery, and '
        'jot down what\'s happening: who\'s there and what led up to it.',
  ),
  _Step(
    Icons.auto_awesome_outlined,
    'The AI writes the account',
    'The AI studies every photo and your notes and writes a detailed, '
        'factual account, then suggests things worth remembering.',
  ),
  _Step(
    Icons.psychology_outlined,
    'It remembers',
    'Saved memories about people, places and ongoing situations help the AI '
        'connect every new event to the ones before it.',
  ),
  _Step(
    Icons.hub_outlined,
    'Your timeline becomes a graph',
    'After your first $graphUnlockPhotos described photos, the AI turns your '
        'timeline into a connected graph of chapters, people, places and '
        'themes, and keeps building on it as you add events.',
  ),
  _Step(
    Icons.menu_book_outlined,
    'Books and rings',
    'Gather chapters into your own titled books, and mark events with '
        'coloured rings. One colour is free; more unlock by watching short '
        'videos.',
  ),
  _Step(
    Icons.lock_outline,
    'Private by design',
    'Photos, notes and memories stay on your phone. When you ask for an '
        'account, that event is sent to the AI with your own API key, and '
        'free writes are sent only to make their labels. An account is '
        'needed to start using the app.',
  ),
];

class _TutorialScreenState extends State<TutorialScreen> {
  final _pages = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _openAuth({required bool signUp}) => Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => AuthScreen(startWithSignUp: signUp)),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = _page == _steps.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _openAuth(signUp: false),
                child: const Text('Sign in'),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pages,
                itemCount: _steps.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) {
                  final step = _steps[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          step.icon,
                          size: 88,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          step.title,
                          style: theme.textTheme.headlineSmall,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          step.body,
                          style: theme.textTheme.bodyLarge,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _steps.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.all(4),
                    width: i == _page ? 20 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _page
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: last
                      ? () => _openAuth(signUp: true)
                      : () => _pages.nextPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                        ),
                  child: Text(last ? 'Create your account' : 'Next'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
