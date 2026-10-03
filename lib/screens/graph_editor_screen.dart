import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/event.dart';
import '../models/memory_graph.dart';
import '../models/ring_palette.dart';
import '../services/rewards_service.dart';
import '../state/app_state.dart';

/// The user's own layer of the timeline graph: Books (titled collections of
/// chapters), which Book each chapter is in, and rings on events.
///
/// Everything the AI wrote (chapter titles, summaries and events, themes,
/// connections, overview) is shown read-only and can't be changed here;
/// saving goes through [AppState.updateUserLayer], which only accepts the
/// user layer.
class GraphEditorScreen extends StatefulWidget {
  const GraphEditorScreen({super.key});

  @override
  State<GraphEditorScreen> createState() => _GraphEditorScreenState();
}

class _GraphEditorScreenState extends State<GraphEditorScreen> {
  late List<Book> _books;
  late Map<String, String?> _chapterBooks;
  late Map<String, int> _rings;
  late List<TimelineChapter> _chapters;
  late List<LifeEvent> _events;
  bool _dirty = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    final graph = state.graphSnapshot;
    _books = [...?graph?.books];
    _chapters = [...?graph?.chapters];
    _chapterBooks = {for (final c in _chapters) c.id: c.bookId};
    _rings = {...?graph?.rings};
    _events = state.allEvents.where((e) => e.hasAccount).toList()
      ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
  }

  void _change(VoidCallback edit) => setState(() {
    edit();
    _dirty = true;
  });

  String _eventTitle(String id) {
    for (final e in _events) {
      if (e.id == id) return e.title.isEmpty ? 'Untitled' : e.title;
    }
    return 'Deleted event';
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await context.read<AppState>().updateUserLayer(
        books: _books,
        chapterBooks: _chapterBooks,
        rings: _rings,
      );
      if (!mounted) return;
      _dirty = false;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<String?> _askTitle(String title, String initial) => showDialog<String>(
    context: context,
    builder: (_) => _TitleDialog(title: title, initial: initial),
  );

  Future<void> _showUnlock(int index) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => _UnlockSheet(index: index),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unlocks = context.watch<RingUnlocks>();
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await _confirm(
          'Discard changes?',
          'Your changes to books and rings haven\'t been saved.',
          'Discard',
        );
        if (discard && context.mounted) {
          _dirty = false;
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Books & rings'),
          actions: [
            TextButton(
              onPressed: _saving ? null : _save,
              child: const Text('Save'),
            ),
          ],
        ),
        body: AbsorbPointer(
          absorbing: _saving,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
            children: [
              Text(
                'Chapters, themes and connections are written by the AI and '
                'grow as you add events. Here you arrange chapters into your '
                'own books and mark events with rings.',
                style: theme.textTheme.bodySmall,
              ),
              const _Section('Books'),
              for (final b in _books)
                ListTile(
                  key: ValueKey('book-${b.id}'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.menu_book_outlined),
                  title: Text(b.title),
                  subtitle: Text(
                    '${_chapterBooks.values.where((id) => id == b.id).length} chapters',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Rename book',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () async {
                          final title = await _askTitle('Rename book', b.title);
                          if (title == null) return;
                          _change(() {
                            final i = _books.indexWhere((x) => x.id == b.id);
                            if (i >= 0) _books[i] = b.copyWith(title: title);
                          });
                        },
                      ),
                      IconButton(
                        tooltip: 'Delete book',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _change(() {
                          _books.removeWhere((x) => x.id == b.id);
                          _chapterBooks.updateAll(
                            (_, id) => id == b.id ? null : id,
                          );
                        }),
                      ),
                    ],
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () async {
                    final title = await _askTitle('New book', '');
                    if (title == null) return;
                    _change(
                      () =>
                          _books.add(Book(id: const Uuid().v4(), title: title)),
                    );
                  },
                  icon: const Icon(Icons.library_add_outlined),
                  label: const Text('Add book'),
                ),
              ),
              const _Section('Chapters'),
              if (_chapters.isEmpty)
                Text('No chapters yet.', style: theme.textTheme.bodySmall),
              for (var i = 0; i < _chapters.length; i++)
                Card(
                  key: ValueKey('chapter-${_chapters[i].id}'),
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Chapter ${i + 1}',
                              style: theme.textTheme.labelMedium,
                            ),
                            const Spacer(),
                            Icon(
                              Icons.lock_outline,
                              size: 14,
                              color: theme.colorScheme.outline,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Written by the AI',
                              style: theme.textTheme.labelSmall,
                            ),
                          ],
                        ),
                        Text(
                          _chapters[i].title,
                          style: theme.textTheme.titleMedium,
                        ),
                        Text(
                          _chapters[i].eventIds.map(_eventTitle).join(' · '),
                          style: theme.textTheme.bodySmall,
                        ),
                        DropdownButtonFormField<String?>(
                          key: ValueKey(
                            'chapter-book-${_chapters[i].id}-${_books.length}',
                          ),
                          initialValue:
                              _books.any(
                                (b) => b.id == _chapterBooks[_chapters[i].id],
                              )
                              ? _chapterBooks[_chapters[i].id]
                              : null,
                          decoration: const InputDecoration(labelText: 'Book'),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('Not in a book'),
                            ),
                            for (final b in _books)
                              DropdownMenuItem<String?>(
                                value: b.id,
                                child: Text(b.title),
                              ),
                          ],
                          onChanged: (v) =>
                              _change(() => _chapterBooks[_chapters[i].id] = v),
                        ),
                      ],
                    ),
                  ),
                ),
              _Section(
                'Rings',
                hint:
                    'Mark events with a coloured ring in the graph. '
                    '${unlocks.unlockedCount} of ${ringPalette.length} '
                    'colours unlocked.',
              ),
              for (final e in _events)
                Padding(
                  key: ValueKey('ring-${e.id}'),
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.title.isEmpty ? 'Untitled' : e.title,
                        style: theme.textTheme.titleSmall,
                      ),
                      Text(
                        DateFormat.yMMMd().format(e.occurredAt),
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _RingDot(
                            color: null,
                            selected: _rings[e.id] == null,
                            onTap: () => _change(() => _rings.remove(e.id)),
                          ),
                          for (var i = 0; i < ringPalette.length; i++)
                            _RingDot(
                              color: ringPalette[i],
                              selected: _rings[e.id] == i,
                              locked: !unlocks.isUnlocked(i),
                              onTap: unlocks.isUnlocked(i)
                                  ? () => _change(() => _rings[e.id] = i)
                                  : () => _showUnlock(i),
                            ),
                        ],
                      ),
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

/// Explains how a locked colour unlocks and plays the rewarded videos.
class _UnlockSheet extends StatelessWidget {
  final int index;

  const _UnlockSheet({required this.index});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unlocks = context.watch<RingUnlocks>();
    final next = unlocks.nextLocked;
    final Widget body;
    if (unlocks.isUnlocked(index)) {
      body = const Text('Unlocked! Close this and pick the colour.');
    } else if (next != index) {
      body = Text(
        'Colours unlock in order. Unlock the earlier colours first: the next '
        'one to unlock needs ${unlocks.videosForNext} more '
        'video${unlocks.videosForNext == 1 ? '' : 's'}.',
      );
    } else {
      final cost = ringUnlockCost(index);
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Watch $cost short videos to unlock this colour. Each later colour '
            'takes one more video.',
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(value: unlocks.progress / cost),
          const SizedBox(height: 4),
          Text(
            '${unlocks.progress} of $cost watched',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: unlocks.watching
                ? null
                : () async {
                    final counted = await unlocks.watchVideo();
                    if (!counted && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'The video didn\'t finish or couldn\'t load, so '
                            'it wasn\'t counted. Try again.',
                          ),
                        ),
                      );
                    }
                  },
            icon: unlocks.watching
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_circle_outline),
            label: const Text('Watch a video'),
          ),
        ],
      );
    }
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _RingDot(color: ringPalette[index], selected: false),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Unlock this ring colour',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            body,
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String? hint;

  const _Section(this.title, {this.hint});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          if (hint != null) Text(hint!, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _RingDot extends StatelessWidget {
  final int? color;
  final bool selected;
  final bool locked;
  final VoidCallback? onTap;

  const _RingDot({
    required this.color,
    required this.selected,
    this.locked = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: onTap != null,
      selected: selected,
      label: color == null
          ? 'No ring'
          : locked
          ? 'Locked ring colour'
          : 'Ring colour',
      child: InkResponse(
        onTap: onTap,
        radius: 22,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: color == null
                  ? scheme.outlineVariant
                  : Color(color!).withValues(alpha: locked ? 0.35 : 1),
              width: 5,
            ),
          ),
          foregroundDecoration: selected
              ? BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.onSurface, width: 2),
                )
              : null,
          child: color == null
              ? Icon(Icons.block, size: 14, color: scheme.outline)
              : locked
              ? Icon(Icons.lock, size: 14, color: scheme.outline)
              : null,
        ),
      ),
    );
  }
}

/// Asks for a book title. Owns its text controller so it is only disposed
/// after the dialog has fully closed.
class _TitleDialog extends StatefulWidget {
  final String title;
  final String initial;

  const _TitleDialog({required this.title, required this.initial});

  @override
  State<_TitleDialog> createState() => _TitleDialogState();
}

class _TitleDialogState extends State<_TitleDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 80,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Book title'),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
