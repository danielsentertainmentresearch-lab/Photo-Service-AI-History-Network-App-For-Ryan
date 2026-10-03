import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/event.dart';
import '../models/memory_graph.dart';
import '../state/app_state.dart';

/// Hand-editing of every part of the organised timeline: overview, groups,
/// chapters (title, summary, colour, group, events, order), themes and
/// links between events.
///
/// Edits are made on a working copy and only saved when the user taps Save.
/// Saving goes through [AppState.saveGraph], which repairs anything invalid,
/// so no combination of edits can leave the app with data it can't show.
class GraphEditorScreen extends StatefulWidget {
  const GraphEditorScreen({super.key});

  @override
  State<GraphEditorScreen> createState() => _GraphEditorScreenState();
}

class _ChapterDraft {
  final String id;
  String title;
  String summary;
  List<String> eventIds;
  int? color;
  String? groupId;
  bool edited;

  _ChapterDraft(TimelineChapter c)
    : id = c.id.isEmpty ? const Uuid().v4() : c.id,
      title = c.title,
      summary = c.summary,
      eventIds = [...c.eventIds],
      color = c.color,
      groupId = c.groupId,
      edited = c.edited;

  TimelineChapter build() => TimelineChapter(
    id: id,
    title: title,
    summary: summary,
    eventIds: eventIds,
    color: color,
    groupId: groupId,
    edited: edited,
  );
}

class _ThemeDraft {
  final String key = const Uuid().v4();
  String name;
  String description;
  List<String> eventIds;
  bool manual;

  _ThemeDraft(StoryTheme t)
    : name = t.name,
      description = t.description,
      eventIds = [...t.eventIds],
      manual = t.manual;

  StoryTheme build() => StoryTheme(
    name: name,
    description: description,
    eventIds: eventIds,
    manual: manual,
  );
}

class _LinkDraft {
  final String key = const Uuid().v4();
  String from;
  String to;
  String relation;
  bool manual;

  _LinkDraft(EventLink l)
    : from = l.fromEventId,
      to = l.toEventId,
      relation = l.relation,
      manual = l.manual;

  EventLink build() => EventLink(
    fromEventId: from,
    toEventId: to,
    relation: relation,
    manual: manual,
  );
}

class _GraphEditorScreenState extends State<GraphEditorScreen> {
  late final GraphSnapshot _base;
  late String _overview;
  late bool _overviewEdited;
  late List<ChapterGroup> _groups;
  late List<_ChapterDraft> _chapters;
  late List<_ThemeDraft> _themes;
  late List<_LinkDraft> _links;
  late List<LifeEvent> _events;
  bool _dirty = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    _base = state.graphSnapshot ?? GraphSnapshot.empty(const Uuid().v4());
    _overview = _base.overview;
    _overviewEdited = _base.overviewEdited;
    _groups = [..._base.groups];
    _chapters = _base.chapters.map(_ChapterDraft.new).toList();
    _themes = _base.themes.map(_ThemeDraft.new).toList();
    _links = _base.links.map(_LinkDraft.new).toList();
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

  GraphSnapshot _result() => _base.copyWith(
    overview: _overview,
    overviewEdited: _overviewEdited,
    groups: _groups,
    chapters: _chapters.map((c) => c.build()).toList(),
    themes: _themes.map((t) => t.build()).toList(),
    links: _links.map((l) => l.build()).toList(),
  );

  Future<void> _save() async {
    final state = context.read<AppState>();
    // The AI may have rebuilt the timeline while this screen was open.
    final current = state.graphSnapshot;
    if (current != null && current.id != _base.id) {
      final overwrite = await _confirm(
        'The timeline changed',
        'The AI rebuilt the timeline while you were editing. Save your '
            'version anyway? This replaces the AI\'s new version.',
        'Save mine',
      );
      if (!overwrite) return;
    }
    setState(() => _saving = true);
    try {
      await state.saveGraph(_result());
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

  Future<void> _rebuildWithAi() async {
    final state = context.read<AppState>();
    if (state.describedCount < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Describe at least two events first.')),
      );
      return;
    }
    final ok = await _confirm(
      'Rebuild with AI?',
      'The AI re-reads every event and reorganises the chapters, themes and '
          'connections. Your ${groupingLabel.toLowerCase()}s, chapter colours, '
          'chapters you renamed, and the themes and connections you added are '
          'kept.${_dirty ? ' Unsaved changes on this screen are saved first.' : ''}',
      'Rebuild',
    );
    if (!ok || !mounted) return;
    if (_dirty) await state.saveGraph(_result());
    if (!mounted) return;
    Navigator.of(context).pop();
    await state.buildGraphNow();
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

  Future<String?> _askText(String title, String initial) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<List<String>?> _pickEvents(String title, List<String> selected) {
    final chosen = {...selected};
    return showDialog<List<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(title),
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          content: SizedBox(
            width: double.maxFinite,
            child: _events.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No described events yet.'),
                  )
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final e in _events)
                        CheckboxListTile(
                          value: chosen.contains(e.id),
                          title: Text(e.title.isEmpty ? 'Untitled' : e.title),
                          subtitle: Text(
                            DateFormat.yMMMd().format(e.occurredAt),
                          ),
                          onChanged: (on) => setDialog(
                            () => on == true
                                ? chosen.add(e.id)
                                : chosen.remove(e.id),
                          ),
                        ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              // Keep timeline order.
              onPressed: () => Navigator.pop(context, [
                for (final e in _events)
                  if (chosen.contains(e.id)) e.id,
              ]),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await _confirm(
          'Discard changes?',
          'Your edits to the timeline haven\'t been saved.',
          'Discard',
        );
        if (discard && context.mounted) {
          _dirty = false;
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Edit timeline'),
          actions: [
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'rebuild') _rebuildWithAi();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rebuild', child: Text('Rebuild with AI')),
              ],
            ),
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
              _Section('Overview'),
              TextFormField(
                initialValue: _overview,
                minLines: 2,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'What this stretch of your life was about',
                ),
                onChanged: (v) => _change(() {
                  _overview = v;
                  _overviewEdited = true;
                }),
              ),
              _Section(
                '${groupingLabel}s',
                hint:
                    'Larger groupings that hold several chapters. Name them '
                    'whatever you like.',
              ),
              for (final g in _groups)
                ListTile(
                  key: ValueKey('group-${g.id}'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(g.name),
                  subtitle: Text(
                    '${_chapters.where((c) => c.groupId == g.id).length} chapters',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Rename',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () async {
                          final name = await _askText(
                            'Rename ${groupingLabel.toLowerCase()}',
                            g.name,
                          );
                          if (name == null) return;
                          _change(() {
                            final i = _groups.indexWhere((x) => x.id == g.id);
                            if (i >= 0) _groups[i] = g.copyWith(name: name);
                          });
                        },
                      ),
                      IconButton(
                        tooltip: 'Delete',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _change(() {
                          _groups.removeWhere((x) => x.id == g.id);
                          for (final c in _chapters) {
                            if (c.groupId == g.id) c.groupId = null;
                          }
                        }),
                      ),
                    ],
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _change(
                    () => _groups.add(
                      ChapterGroup(
                        id: const Uuid().v4(),
                        name: untitledGroupName,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.create_new_folder_outlined),
                  label: Text('Add ${groupingLabel.toLowerCase()}'),
                ),
              ),
              _Section('Chapters'),
              for (var i = 0; i < _chapters.length; i++) _chapterCard(i, theme),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _change(
                    () => _chapters.add(
                      _ChapterDraft(
                        TimelineChapter(
                          id: const Uuid().v4(),
                          title: 'New chapter',
                          summary: '',
                          eventIds: const [],
                          edited: true,
                        ),
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Add chapter'),
                ),
              ),
              _Section('Themes'),
              for (final t in _themes) _themeCard(t),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _change(
                    () => _themes.add(
                      _ThemeDraft(
                        const StoryTheme(
                          name: 'New theme',
                          description: '',
                          eventIds: [],
                          manual: true,
                        ),
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Add theme'),
                ),
              ),
              _Section(
                'Connections',
                hint: 'Links between two events, drawn in purple on the graph.',
              ),
              for (final l in _links) _linkCard(l),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _events.length < 2
                      ? null
                      : () => _change(
                          () => _links.add(
                            _LinkDraft(
                              EventLink(
                                fromEventId: _events.first.id,
                                toEventId: _events.last.id,
                                relation: '',
                                manual: true,
                              ),
                            ),
                          ),
                        ),
                  icon: const Icon(Icons.add_link),
                  label: const Text('Add connection'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _eventChips(List<String> ids, void Function(String) onRemove) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      for (final id in ids)
        InputChip(label: Text(_eventTitle(id)), onDeleted: () => onRemove(id)),
    ],
  );

  Widget _chapterCard(int index, ThemeData theme) {
    final c = _chapters[index];
    return Card(
      key: ValueKey('chapter-${c.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Chapter ${index + 1}', style: theme.textTheme.labelLarge),
                const Spacer(),
                IconButton(
                  tooltip: 'Move up',
                  icon: const Icon(Icons.arrow_upward),
                  onPressed: index == 0
                      ? null
                      : () => _change(() {
                          _chapters.insert(
                            index - 1,
                            _chapters.removeAt(index),
                          );
                        }),
                ),
                IconButton(
                  tooltip: 'Move down',
                  icon: const Icon(Icons.arrow_downward),
                  onPressed: index == _chapters.length - 1
                      ? null
                      : () => _change(() {
                          _chapters.insert(
                            index + 1,
                            _chapters.removeAt(index),
                          );
                        }),
                ),
                IconButton(
                  tooltip: 'Delete chapter',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _change(() => _chapters.removeAt(index)),
                ),
              ],
            ),
            TextFormField(
              key: ValueKey('chapter-title-${c.id}'),
              initialValue: c.title,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Title'),
              onChanged: (v) => _change(() {
                c.title = v;
                c.edited = true;
              }),
            ),
            TextFormField(
              key: ValueKey('chapter-summary-${c.id}'),
              initialValue: c.summary,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Summary'),
              onChanged: (v) => _change(() {
                c.summary = v;
                c.edited = true;
              }),
            ),
            const SizedBox(height: 12),
            Text('Colour', style: theme.textTheme.labelMedium),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ColourDot(
                  color: null,
                  selected: c.color == null,
                  onTap: () => _change(() => c.color = null),
                ),
                for (final colour in chapterColors)
                  _ColourDot(
                    color: colour,
                    selected: c.color == colour,
                    onTap: () => _change(() => c.color = colour),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              key: ValueKey('chapter-group-${c.id}-${_groups.length}'),
              initialValue: _groups.any((g) => g.id == c.groupId)
                  ? c.groupId
                  : null,
              decoration: InputDecoration(labelText: groupingLabel),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('None'),
                ),
                for (final g in _groups)
                  DropdownMenuItem<String?>(value: g.id, child: Text(g.name)),
              ],
              onChanged: (v) => _change(() => c.groupId = v),
            ),
            const SizedBox(height: 12),
            Text('Events', style: theme.textTheme.labelMedium),
            const SizedBox(height: 4),
            _eventChips(
              c.eventIds,
              (id) => _change(() => c.eventIds.remove(id)),
            ),
            TextButton.icon(
              onPressed: () async {
                final picked = await _pickEvents(
                  'Events in this chapter',
                  c.eventIds,
                );
                if (picked == null) return;
                _change(() {
                  // An event belongs to one chapter: move it here.
                  for (final other in _chapters) {
                    if (other != c) {
                      other.eventIds.removeWhere(picked.contains);
                    }
                  }
                  c.eventIds = picked;
                });
              },
              icon: const Icon(Icons.playlist_add),
              label: const Text('Choose events'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _themeCard(_ThemeDraft t) {
    return Card(
      key: ValueKey('theme-${t.key}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: t.name,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(labelText: 'Theme'),
                    onChanged: (v) => _change(() {
                      t.name = v;
                      t.manual = true;
                    }),
                  ),
                ),
                IconButton(
                  tooltip: 'Delete theme',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _change(() => _themes.remove(t)),
                ),
              ],
            ),
            TextFormField(
              initialValue: t.description,
              maxLines: 3,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Description'),
              onChanged: (v) => _change(() {
                t.description = v;
                t.manual = true;
              }),
            ),
            const SizedBox(height: 8),
            _eventChips(
              t.eventIds,
              (id) => _change(() {
                t.eventIds.remove(id);
                t.manual = true;
              }),
            ),
            TextButton.icon(
              onPressed: () async {
                final picked = await _pickEvents(
                  'Events in this theme',
                  t.eventIds,
                );
                if (picked == null) return;
                _change(() {
                  t.eventIds = picked;
                  t.manual = true;
                });
              },
              icon: const Icon(Icons.playlist_add),
              label: const Text('Choose events'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _linkCard(_LinkDraft l) {
    final ids = _events.map((e) => e.id).toSet();
    DropdownButtonFormField<String> picker(
      String label,
      String value,
      void Function(String) onPick,
    ) => DropdownButtonFormField<String>(
      initialValue: ids.contains(value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final e in _events)
          DropdownMenuItem(
            value: e.id,
            child: Text(
              e.title.isEmpty ? 'Untitled' : e.title,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (v) {
        if (v != null) _change(() => onPick(v));
      },
    );

    return Card(
      key: ValueKey('link-${l.key}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: l.relation,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'How they connect',
                      hintText: 'e.g. same lake, one year later',
                    ),
                    onChanged: (v) => _change(() {
                      l.relation = v;
                      l.manual = true;
                    }),
                  ),
                ),
                IconButton(
                  tooltip: 'Delete connection',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _change(() => _links.remove(l)),
                ),
              ],
            ),
            picker('From', l.from, (v) {
              l.from = v;
              l.manual = true;
            }),
            picker('To', l.to, (v) {
              l.to = v;
              l.manual = true;
            }),
            if (l.from == l.to)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Pick two different events. A connection from an event to '
                  'itself is dropped when you save.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
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

class _ColourDot extends StatelessWidget {
  final int? color;
  final bool selected;
  final VoidCallback onTap;

  const _ColourDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: color == null ? 'No colour' : 'Colour',
      child: InkResponse(
        onTap: onTap,
        radius: 22,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color == null ? scheme.surface : Color(color!),
            border: Border.all(
              color: selected ? scheme.onSurface : scheme.outlineVariant,
              width: selected ? 3 : 1,
            ),
          ),
          child: color == null
              ? Icon(Icons.block, size: 16, color: scheme.outline)
              : null,
        ),
      ),
    );
  }
}
