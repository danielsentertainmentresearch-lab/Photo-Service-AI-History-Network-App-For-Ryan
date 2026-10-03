import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../ai/event_describer.dart';
import '../models/event.dart';
import '../models/memory_item.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

class EventDetailScreen extends StatelessWidget {
  final String eventId;

  const EventDetailScreen({super.key, required this.eventId});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final event = state.eventById(eventId);
    if (event == null) {
      return Scaffold(
          appBar: AppBar(), body: const Center(child: Text('Event not found')));
    }
    final theme = Theme.of(context);
    final busy = event.status == EventStatus.describing;

    return Scaffold(
      appBar: AppBar(
        title: Text(event.title.isEmpty ? 'Event' : event.title,
            overflow: TextOverflow.ellipsis),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) => _onMenu(context, value, event),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit details')),
              if (event.hasAccount)
                const PopupMenuItem(
                    value: 'edit_text', child: Text('Edit description')),
              if (event.hasAccount)
                const PopupMenuItem(value: 'copy', child: Text('Copy text')),
              if (!busy)
                PopupMenuItem(
                    value: 'describe',
                    child: Text(event.hasAccount
                        ? 'Rewrite with AI'
                        : 'Describe with AI')),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (event.images.isNotEmpty) _Gallery(images: event.images),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(DateFormat.yMMMMEEEEd().add_jm().format(event.occurredAt),
                    style: theme.textTheme.bodyMedium),
                if (event.location.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(children: [
                      const Icon(Icons.place_outlined, size: 16),
                      const SizedBox(width: 4),
                      Expanded(child: Text(event.location)),
                    ]),
                  ),
                const SizedBox(height: 8),
                StatusChip(event.status),
                const SizedBox(height: 16),
                if (busy) const _DescribingCard(),
                if (event.status == EventStatus.failed)
                  _ErrorCard(
                    message: event.error ?? 'The description failed.',
                    onRetry: () =>
                        context.read<AppState>().describeEvent(event.id),
                  ),
                if (event.status == EventStatus.draft && !event.hasAccount)
                  FilledButton.icon(
                    onPressed: () =>
                        context.read<AppState>().describeEvent(event.id),
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text('Describe with AI'),
                  ),
                if (event.hasAccount) ...[
                  SelectableText(event.description,
                      style: theme.textTheme.bodyLarge?.copyWith(height: 1.5)),
                  const SizedBox(height: 16),
                  _LabelRow(
                      icon: Icons.people_outline, labels: event.people),
                  _LabelRow(icon: Icons.place_outlined, labels: event.places),
                  _LabelRow(icon: Icons.sell_outlined, labels: event.tags),
                  if (event.model != null && event.model!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Written by ${supportedModels[event.model] ?? event.model}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                ],
                if (event.suggestions.isNotEmpty)
                  _SuggestionsCard(event: event),
                if (event.notes.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text('Your notes at the time',
                      style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  SelectableText(event.notes),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onMenu(
      BuildContext context, String value, LifeEvent event) async {
    final state = context.read<AppState>();
    switch (value) {
      case 'edit':
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => _EditDetailsSheet(event: event),
        );
      case 'edit_text':
        final text = await _editText(context, event.description);
        if (text != null) await state.updateDescription(event, text);
      case 'copy':
        await Clipboard.setData(ClipboardData(
            text: '${event.title}\n\n${event.description}'));
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Copied')));
        }
      case 'describe':
        if (event.hasAccount) {
          final ok = await _confirm(context, 'Rewrite this account?',
              'The current description will be replaced. Edits you made to it will be lost.');
          if (!ok) return;
        }
        state.describeEvent(event.id);
      case 'delete':
        final ok = await _confirm(context, 'Delete this event?',
            'Its photos will be removed from the app. This cannot be undone.');
        if (!ok || !context.mounted) return;
        Navigator.of(context).pop();
        await state.deleteEvent(event);
    }
  }

  static Future<bool> _confirm(
      BuildContext context, String title, String body) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continue')),
        ],
      ),
    );
    return result ?? false;
  }

  static Future<String?> _editText(BuildContext context, String initial) {
    return Navigator.of(context).push<String>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _TextEditorPage(initial: initial),
    ));
  }
}

class _Gallery extends StatefulWidget {
  final List<EventImage> images;

  const _Gallery({required this.images});

  @override
  State<_Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<_Gallery> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 4 / 3,
          child: PageView.builder(
            itemCount: widget.images.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, i) => GestureDetector(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) =>
                      _FullScreenPhoto(fileName: widget.images[i].fileName))),
              child: VaultImage(widget.images[i].fileName),
            ),
          ),
        ),
        if (widget.images.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('${_page + 1} / ${widget.images.length}',
                style: Theme.of(context).textTheme.labelMedium),
          ),
      ],
    );
  }
}

class _FullScreenPhoto extends StatelessWidget {
  final String fileName;

  const _FullScreenPhoto({required this.fileName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
          backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: InteractiveViewer(
        maxScale: 5,
        child: Center(child: VaultImage(fileName, fit: BoxFit.contain)),
      ),
    );
  }
}

class _DescribingCard extends StatelessWidget {
  const _DescribingCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 3)),
            SizedBox(width: 16),
            Expanded(
              child: Text(
                  'The AI is studying your photos and memories and writing the '
                  'account. This can take a minute or two.'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message, style: TextStyle(color: scheme.onErrorContainer)),
            const SizedBox(height: 8),
            FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _LabelRow extends StatelessWidget {
  final IconData icon;
  final List<String> labels;

  const _LabelRow({required this.icon, required this.labels});

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Icon(icon, size: 18)),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final l in labels)
                  Chip(label: Text(l), visualDensity: VisualDensity.compact),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionsCard extends StatelessWidget {
  final LifeEvent event;

  const _SuggestionsCard({required this.event});

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Remember for next time?', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Saved memories help the AI understand future events.',
              style: theme.textTheme.bodySmall,
            ),
            for (final s in event.suggestions)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(s.content),
                subtitle: Text(memoryKindLabel(s.kind)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Dismiss',
                      icon: const Icon(Icons.close),
                      onPressed: () => state.dismissSuggestion(event, s),
                    ),
                    IconButton(
                      tooltip: 'Save to memory',
                      icon: const Icon(Icons.check),
                      onPressed: () => state.acceptSuggestion(event, s),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EditDetailsSheet extends StatefulWidget {
  final LifeEvent event;

  const _EditDetailsSheet({required this.event});

  @override
  State<_EditDetailsSheet> createState() => _EditDetailsSheetState();
}

class _EditDetailsSheetState extends State<_EditDetailsSheet> {
  late final _title = TextEditingController(text: widget.event.title);
  late final _location = TextEditingController(text: widget.event.location);
  late final _notes = TextEditingController(text: widget.event.notes);

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Edit details', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'Title')),
            const SizedBox(height: 12),
            TextField(
                controller: _location,
                decoration: const InputDecoration(labelText: 'Where')),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              minLines: 3,
              maxLines: 8,
              decoration: const InputDecoration(
                  labelText: 'Your notes', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            Text(
              'Changing notes does not rewrite the account. Use "Rewrite with AI" afterwards if you want it updated.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                await context.read<AppState>().updateEventDetails(
                      widget.event,
                      title: _title.text,
                      location: _location.text,
                      notes: _notes.text,
                    );
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TextEditorPage extends StatefulWidget {
  final String initial;

  const _TextEditorPage({required this.initial});

  @override
  State<_TextEditorPage> createState() => _TextEditorPageState();
}

class _TextEditorPageState extends State<_TextEditorPage> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit description'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: _controller,
          expands: true,
          maxLines: null,
          textAlignVertical: TextAlignVertical.top,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
      ),
    );
  }
}
