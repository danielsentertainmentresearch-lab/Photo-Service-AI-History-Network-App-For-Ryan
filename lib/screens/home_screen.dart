import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../models/event.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import 'data_screen.dart';
import 'event_detail_screen.dart';
import 'graph_screen.dart';
import 'support_screen.dart';
import 'memory_screen.dart';
import 'new_event_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final events = state.allEvents;

    return Scaffold(
      appBar: AppBar(
        title: const Text(appName),
        actions: [
          IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.search),
            onPressed: events.isEmpty
                ? null
                : () => showSearch(context: context, delegate: _EventSearch()),
          ),
          IconButton(
            tooltip: 'Timeline graph',
            icon: const Icon(Icons.hub_outlined),
            onPressed: () => _push(context, const GraphScreen()),
          ),
          IconButton(
            tooltip: 'Your data',
            icon: const Icon(Icons.insights_outlined),
            onPressed: () => _push(context, const DataScreen()),
          ),
          IconButton(
            tooltip: 'What the AI is learning',
            icon: const Icon(Icons.psychology_outlined),
            onPressed: () => _push(context, const MemoryScreen()),
          ),
          IconButton(
            tooltip: 'Support',
            icon: const Icon(Icons.volunteer_activism_outlined),
            onPressed: () => _push(context, const SupportScreen()),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => _push(context, const SettingsScreen()),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!state.aiReady)
            MaterialBanner(
              leading: const Icon(Icons.key_outlined),
              content: const Text(
                'Add your Anthropic API key so the AI can describe events.',
              ),
              actions: [
                TextButton(
                  onPressed: () => _push(context, const SettingsScreen()),
                  child: const Text('Add key'),
                ),
              ],
            ),
          if (state.onThisDay().isNotEmpty)
            _OnThisDay(events: state.onThisDay()),
          Expanded(
            child: events.isEmpty
                ? const _EmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 96),
                    itemCount: events.length,
                    itemBuilder: (context, i) {
                      final showHeader =
                          i == 0 ||
                          !_sameMonth(
                            events[i - 1].occurredAt,
                            events[i].occurredAt,
                          );
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (showHeader)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                              child: Text(
                                DateFormat.yMMMM().format(events[i].occurredAt),
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ),
                          EventTile(event: events[i]),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _push(context, const NewEventScreen()),
        icon: const Icon(Icons.add_a_photo_outlined),
        label: const Text('New event'),
      ),
    );
  }

  static bool _sameMonth(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month;

  static void _push(BuildContext context, Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
}

class EventTile extends StatelessWidget {
  final LifeEvent event;

  const EventTile({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = event.title.isEmpty ? 'Untitled event' : event.title;
    final subtitle = event.summary.isNotEmpty ? event.summary : event.notes;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => EventDetailScreen(eventId: event.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: event.images.isEmpty
                    ? Container(
                        width: 72,
                        height: 72,
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.event_note_outlined),
                      )
                    : VaultImage(event.images.first.fileName, size: 72),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat.MMMEd().add_jm().format(event.occurredAt),
                      style: theme.textTheme.bodySmall,
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                    const SizedBox(height: 6),
                    StatusChip(event.status),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.photo_camera_back_outlined,
              size: 64,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text('No events yet', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              'Tap "New event", add a few photos and some notes about what is '
              'happening, and let the AI write the full story.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _EventSearch extends SearchDelegate<void> {
  @override
  List<Widget> buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
  ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
    icon: const BackButtonIcon(),
    onPressed: () => close(context, null),
  );

  @override
  Widget buildResults(BuildContext context) => _results(context);

  @override
  Widget buildSuggestions(BuildContext context) => _results(context);

  Widget _results(BuildContext context) {
    final q = query.toLowerCase().trim();
    final events = context.watch<AppState>().allEvents.where((e) {
      if (q.isEmpty) return true;
      return [
        e.title,
        e.notes,
        e.experience,
        e.location,
        e.summary,
        e.description,
        ...e.people,
        ...e.places,
        ...e.tags,
      ].any((field) => field.toLowerCase().contains(q));
    }).toList();
    if (events.isEmpty) {
      return const Center(child: Text('No matching events'));
    }
    return ListView(children: [for (final e in events) EventTile(event: e)]);
  }
}

/// Events from this calendar day in earlier years.
class _OnThisDay extends StatelessWidget {
  final List<LifeEvent> events;

  const _OnThisDay({required this.events});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final honored = context.watch<AppState>().honoredNames;
    bool remembered(LifeEvent e) => [
      ...e.people,
      ...e.places,
    ].any((n) => honored.contains(n.trim().toLowerCase()));
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Card(
        color: theme.colorScheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'On this day',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
              for (final e in events.take(3))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: remembered(e)
                      ? Tooltip(
                          message: 'Someone you honor is part of this',
                          child: Icon(
                            Icons.spa_outlined,
                            color: theme.colorScheme.onSecondaryContainer,
                          ),
                        )
                      : null,
                  title: Text(e.title.isEmpty ? 'Untitled event' : e.title),
                  subtitle: Text(_ago(now.year - e.occurredAt.year)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => EventDetailScreen(eventId: e.id),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _ago(int years) =>
      years == 1 ? '1 year ago today' : '$years years ago today';
}
