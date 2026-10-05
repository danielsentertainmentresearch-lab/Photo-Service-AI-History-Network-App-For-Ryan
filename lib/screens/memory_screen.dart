import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/learning_view.dart';
import '../models/memory_graph.dart';
import '../state/app_state.dart';

/// What the AI is learning about the person (owner, 5 Oct 2026). Memory is
/// the AI's: people can't add, edit or delete it here. The page shows the
/// AI's own findings a few at a time, rotating at unplanned times of day
/// (see [learningRotation]).
///
/// Interim: when the app's own memory file and dream state are built
/// (docs/AI_SERVER.md, step 8), this page shows what the dream pass learned.
class MemoryScreen extends StatefulWidget {
  const MemoryScreen({super.key});

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  Timer? _timer;

  /// Rebuilds when the selection rotates while the page is open.
  void _scheduleRotation(DateTime next) {
    _timer?.cancel();
    final wait = next.difference(DateTime.now());
    _timer = Timer(
      wait.isNegative ? Duration.zero : wait + const Duration(seconds: 1),
      () {
        if (mounted) setState(() {});
      },
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    final view = computeLearning(
      events: state.allEvents,
      memories: state.memories,
      graph: state.graphSnapshot,
      now: DateTime.now(),
      nameStates: state.nameStates,
    );
    _scheduleRotation(view.nextChange);

    return Scaffold(
      appBar: AppBar(title: const Text('What the AI is learning')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'The AI keeps its own memory of your life: who is who, the places '
            'that matter, and how your events connect. Here is some of what '
            'it has worked out. It changes through the day.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          if (view.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'The AI starts learning as you record events.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else ...[
            Row(
              children: [
                _Count(value: view.people, label: 'people'),
                _Count(value: view.places, label: 'places'),
                _Count(value: view.facts, label: 'other things'),
              ],
            ),
            if (view.remembering.isNotEmpty)
              _Section(
                icon: Icons.spa_outlined,
                title: 'Remembering',
                children: [
                  for (final r in view.remembering)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.name, style: theme.textTheme.bodyLarge),
                        Text(
                          [
                            r.moments == 1
                                ? '1 shared moment'
                                : '${r.moments} shared moments',
                            if (r.moment != null) r.moment!,
                          ].join(' · '),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                ],
              ),
            if (view.connections.isNotEmpty)
              _Section(
                icon: Icons.link,
                title: 'Connections it has found',
                children: [for (final c in view.connections) Text(c)],
              ),
            if (view.threads.isNotEmpty)
              _Section(
                icon: Icons.timeline,
                title: 'Threads in your life',
                children: [for (final t in view.threads) _Thread(theme: t)],
              ),
            if (view.remembers.isNotEmpty)
              _Section(
                icon: Icons.psychology_outlined,
                title: 'Some of what it remembers',
                children: [for (final r in view.remembers) Text(r)],
              ),
          ],
        ],
      ),
    );
  }
}

class _Count extends StatelessWidget {
  final int value;
  final String label;

  const _Count({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Text('$value', style: theme.textTheme.headlineSmall),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;

  const _Section({
    required this.icon,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(title, style: theme.textTheme.titleSmall),
                ),
              ],
            ),
            for (final child in children)
              Padding(padding: const EdgeInsets.only(top: 8), child: child),
          ],
        ),
      ),
    );
  }
}

class _Thread extends StatelessWidget {
  final StoryTheme theme;

  const _Thread({required this.theme});

  @override
  Widget build(BuildContext context) {
    final count = theme.eventIds.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${theme.name} · ${count == 1 ? '1 event' : '$count events'}',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        if (theme.description.trim().isNotEmpty)
          Text(
            theme.description.trim(),
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }
}
