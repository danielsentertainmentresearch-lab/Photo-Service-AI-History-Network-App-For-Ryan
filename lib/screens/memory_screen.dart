import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/memory_item.dart';
import '../state/app_state.dart';

/// Long-term ("contextual") memory: durable facts the AI reads before
/// describing any event.
class MemoryScreen extends StatelessWidget {
  const MemoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final memories = context.watch<AppState>().memories;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Memory')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, null),
        icon: const Icon(Icons.add),
        label: const Text('Add memory'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Things the AI should always know when describing your events: '
              'who people are, places that matter, ongoing situations, how you '
              'like things described. Every saved memory is sent with each '
              'description request.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          if (memories.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'No memories yet.\nTry: "Sam is my younger brother; he plays '
                  'drums in a band called Lowtide."',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          for (final kind in memoryKinds)
            ..._section(
              context,
              kind,
              memories.where((m) => m.kind == kind).toList(),
            ),
        ],
      ),
    );
  }

  List<Widget> _section(
    BuildContext context,
    String kind,
    List<MemoryItem> items,
  ) {
    if (items.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          memoryKindLabel(kind),
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ),
      for (final item in items)
        Dismissible(
          key: ValueKey(item.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            color: Theme.of(context).colorScheme.errorContainer,
            child: const Icon(Icons.delete_outline),
          ),
          onDismissed: (_) => context.read<AppState>().deleteMemory(item),
          child: ListTile(
            title: Text(item.content),
            subtitle: switch (item.source) {
              'ai' => const Text('Suggested by AI from an event'),
              answerSource => const Text('Your answer to the AI\'s question'),
              _ => null,
            },
            onTap: () => _edit(context, item),
          ),
        ),
    ];
  }

  static Future<void> _edit(BuildContext context, MemoryItem? item) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _MemoryEditor(item: item),
    );
  }
}

class _MemoryEditor extends StatefulWidget {
  final MemoryItem? item;

  const _MemoryEditor({this.item});

  @override
  State<_MemoryEditor> createState() => _MemoryEditorState();
}

class _MemoryEditorState extends State<_MemoryEditor> {
  late final _content = TextEditingController(text: widget.item?.content);
  late String _kind = widget.item?.kind ?? 'person';

  @override
  void dispose() {
    _content.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final state = context.read<AppState>();
    if (_content.text.trim().isEmpty) return;
    if (widget.item == null) {
      await state.addMemory(_kind, _content.text);
    } else {
      await state.updateMemory(widget.item!, _kind, _content.text);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.item == null ? 'Add memory' : 'Edit memory',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final kind in memoryKinds)
                ChoiceChip(
                  label: Text(memoryKindLabel(kind)),
                  selected: _kind == kind,
                  onSelected: (_) => setState(() => _kind = kind),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _content,
            autofocus: widget.item == null,
            minLines: 2,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'e.g. "Grandma\'s house is the blue cottage in Ely."',
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (widget.item != null)
                TextButton.icon(
                  onPressed: () async {
                    await context.read<AppState>().deleteMemory(widget.item!);
                    if (context.mounted) Navigator.pop(context);
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete'),
                ),
              const Spacer(),
              FilledButton(onPressed: _save, child: const Text('Save')),
            ],
          ),
        ],
      ),
    );
  }
}
