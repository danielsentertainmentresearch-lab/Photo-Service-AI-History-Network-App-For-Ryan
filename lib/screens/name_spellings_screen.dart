import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/name_spelling.dart';
import '../state/app_state.dart';

/// Correct how the people and places the AI knows are spelled (owner,
/// 5 Oct 2026). Spelling only: a few letters or capitals, never a different
/// name or new information, so the AI can't be steered into something untrue.
class NameSpellingsScreen extends StatelessWidget {
  const NameSpellingsScreen({super.key});

  static Future<void> _fix(
    BuildContext context,
    String from,
    String to,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final count = await context.read<AppState>().fixNameSpelling(from, to);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '"$from" is now "$to"'
          '${count == 0 ? '' : ' in ${count == 1 ? '1 event' : '$count events'}'}.',
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, KnownName name) async {
    final to = await showDialog<String>(
      context: context,
      builder: (_) => _SpellingDialog(from: name.name),
    );
    if (to != null && context.mounted) await _fix(context, name.name, to);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    final names = knownNames(state.allEvents, state.memories);
    final suggestions = spellingSuggestions(names);

    return Scaffold(
      appBar: AppBar(title: const Text('Name spellings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Fix how a person or place is spelled, everywhere the AI uses '
            'it. Only spelling: a few letters or capitals. A name can\'t be '
            'swapped for another or given new details.',
            style: theme.textTheme.bodyMedium,
          ),
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Possible typos', style: theme.textTheme.titleSmall),
            for (final s in suggestions)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.spellcheck),
                title: Text('"${s.from}" → "${s.to}"'),
                trailing: TextButton(
                  onPressed: () => _fix(context, s.from, s.to),
                  child: const Text('Fix'),
                ),
              ),
          ],
          const SizedBox(height: 16),
          if (names.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'Names show here once the AI knows who and where.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          for (final kind in ['person', 'place'])
            if (names.any((n) => n.kind == kind)) ...[
              Text(
                kind == 'person' ? 'People' : 'Places',
                style: theme.textTheme.titleSmall,
              ),
              for (final n in names.where((n) => n.kind == kind))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(n.name),
                  subtitle: Text(
                    n.events == 1 ? 'In 1 event' : 'In ${n.events} events',
                  ),
                  trailing: IconButton(
                    tooltip: 'Fix spelling of ${n.name}',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _edit(context, n),
                  ),
                ),
              const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }
}

class _SpellingDialog extends StatefulWidget {
  final String from;

  const _SpellingDialog({required this.from});

  @override
  State<_SpellingDialog> createState() => _SpellingDialogState();
}

class _SpellingDialogState extends State<_SpellingDialog> {
  late final _to = TextEditingController(text: widget.from);

  @override
  void dispose() {
    _to.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = _to.text.trim();
    final valid = isSpellingFix(widget.from, text);
    final changed = text != widget.from.trim() && text.isNotEmpty;
    return AlertDialog(
      title: Text('Spelling of "${widget.from}"'),
      content: TextField(
        controller: _to,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          errorText: changed && !valid
              ? 'Only spelling fixes: a few letters or capitals'
              : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: valid ? () => Navigator.pop(context, text) : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
