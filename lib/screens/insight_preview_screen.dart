import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/insights.dart';
import '../services/data_files.dart';
import '../services/insight_pass.dart';
import '../state/app_state.dart';

/// A sneak peek at the insights the full export holds, before it unlocks at
/// 100 events: three videos open two insights for 12 hours (once every 48
/// hours); the $1 pass opens all of them for 72 hours.
class InsightPreviewScreen extends StatelessWidget {
  const InsightPreviewScreen({super.key});

  static String _when(DateTime t) => DateFormat('EEE h:mm a').format(t);

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final pass = context.watch<InsightPass>();
    final theme = Theme.of(context);
    final tier = pass.tier;
    final openIds = switch (tier) {
      InsightTier.pass => passInsights,
      InsightTier.video => videoInsights,
      InsightTier.none => const <String>[],
    };
    final lockedIds = passInsights.where((id) => !openIds.contains(id));

    return Scaffold(
      appBar: AppBar(title: const Text('Sneak peek')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'A taste of what your full export can show, worked out on your '
            'phone from your own events. The full export opens for good at '
            '$exportUnlockEvents events.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          if (tier != InsightTier.none)
            Text(
              'Open until ${_when((tier == InsightTier.pass ? pass.passUntil : pass.videoUntil)!)}',
              style: theme.textTheme.titleSmall,
            ),
          for (final insight in computeInsights(
            state.allEvents,
            openIds,
            quiet: state.quietNames,
          ))
            _InsightCard(insight: insight),
          if (lockedIds.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              tier == InsightTier.none
                  ? 'What you can see'
                  : 'More with the $insightPassPrice pass',
              style: theme.textTheme.titleSmall,
            ),
            for (final id in lockedIds)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.lock_outline),
                title: Text(insightTitles[id]!),
                subtitle: Text(
                  videoInsights.contains(id)
                      ? 'With 3 videos or the $insightPassPrice pass'
                      : 'With the $insightPassPrice pass',
                ),
              ),
          ],
          const SizedBox(height: 16),
          if (tier == InsightTier.none) _VideoOffer(pass: pass),
          _PassOffer(pass: pass),
        ],
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  final Insight insight;

  const _InsightCard({required this.insight});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(insight.title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              insight.text,
              style: insight.found
                  ? theme.textTheme.bodyLarge
                  : theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoOffer extends StatelessWidget {
  final InsightPass pass;

  const _VideoOffer({required this.pass});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final next = pass.videoAvailableAt;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$insightVideos videos · $insightVideoHours hours',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              next != null
                  ? 'Available again ${InsightPreviewScreen._when(next)}.'
                  : 'Opens ${videoInsights.length} insights. Once every '
                        '$insightVideoCooldownHours hours.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: pass.canWatch ? pass.watchVideo : null,
              icon: const Icon(Icons.play_circle_outline),
              label: Text('Watch a video (${pass.progress}/$insightVideos)'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PassOffer extends StatelessWidget {
  final InsightPass pass;

  const _PassOffer({required this.pass});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final open = pass.tier == InsightTier.pass;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$insightPassPrice · $insightPassHours hours',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              pass.purchases.available
                  ? 'Opens all ${passInsights.length} insights.'
                  : 'Opens all ${passInsights.length} insights. Purchases '
                        'aren\'t connected in this build yet.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: pass.purchases.available && !pass.busy
                  ? pass.buyPass
                  : null,
              icon: const Icon(Icons.auto_awesome),
              label: Text(
                open
                    ? 'Add $insightPassHours hours for $insightPassPrice'
                    : 'Get the pass for $insightPassPrice',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
