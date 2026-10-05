import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/support_resources.dart';
import 'how_support_works_screen.dart';

/// Support, always one tap from home (owner, 6 Oct 2026). Harm reduction is
/// the ground rule: no judgement, nothing to qualify for, nothing recorded
/// about what anyone reads here. The crisis line and emergency number come
/// first, big and quick to reach.
class SupportScreen extends StatelessWidget {
  /// The phone's country code; read from the device when null.
  final String? countryCode;

  const SupportScreen({super.key, this.countryCode});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final first = crisisFirstFor(
      countryCode ?? PlatformDispatcher.instance.locale.countryCode,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Support')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Whatever is going on, you don\'t have to carry it alone. '
            'Reach out any time. Nothing you do here is recorded.',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          _CrisisFirstCard(first: first),
          for (final section in supportSections) ...[
            const SizedBox(height: 20),
            Text(section.title, style: theme.textTheme.titleMedium),
            for (final r in section.resources) _ResourceTile(resource: r),
          ],
          const SizedBox(height: 20),
          Text('Grounding, right now', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'When everything feels like too much, slow your breathing and '
            'take these one at a time:',
            style: theme.textTheme.bodyMedium,
          ),
          for (final (i, step) in groundingSteps.indexed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: CircleAvatar(radius: 14, child: Text('${5 - i}')),
              title: Text(step),
            ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.info_outline),
            title: const Text('How support works in EventLens'),
            subtitle: const Text('What happens, what doesn\'t, and why'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const HowSupportWorksScreen()),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

Future<void> openReach(BuildContext context, Reach reach) async {
  final ok = await launchUrl(
    reach.uri,
    mode: LaunchMode.externalApplication,
  ).catchError((_) => false);
  if (!ok && context.mounted) {
    await Clipboard.setData(ClipboardData(text: reach.target));
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Copied: ${reach.target}')));
    }
  }
}

class _CrisisFirstCard extends StatelessWidget {
  final CrisisFirst first;

  const _CrisisFirstCard({required this.first});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final emergency = Reach.call(
      'Emergency: ${first.emergency}',
      first.emergency,
    );
    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'If you\'re in crisis right now',
              style: theme.textTheme.titleLarge?.copyWith(
                color: scheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${first.crisisLine.name}. ${first.crisisLine.about}',
              style: TextStyle(color: scheme.onErrorContainer),
            ),
            const SizedBox(height: 12),
            for (final reach in first.crisisLine.reach)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: () => openReach(context, reach),
                  icon: Icon(_icon(reach.kind)),
                  label: Text(reach.label),
                ),
              ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              onPressed: () => openReach(context, emergency),
              icon: const Icon(Icons.emergency_outlined),
              label: Text(emergency.label),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _icon(ReachKind kind) => switch (kind) {
  ReachKind.call => Icons.call,
  ReachKind.text => Icons.sms_outlined,
  ReachKind.web => Icons.open_in_new,
};

class _ResourceTile extends StatelessWidget {
  final SupportResource resource;

  const _ResourceTile({required this.resource});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(resource.name, style: theme.textTheme.titleSmall),
          Text(resource.about, style: theme.textTheme.bodySmall),
          Wrap(
            spacing: 8,
            children: [
              for (final reach in resource.reach)
                TextButton.icon(
                  onPressed: () => openReach(context, reach),
                  icon: Icon(_icon(reach.kind), size: 18),
                  label: Text(reach.label),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
