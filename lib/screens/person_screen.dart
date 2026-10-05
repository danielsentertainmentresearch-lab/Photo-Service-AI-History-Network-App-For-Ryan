import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/name_state.dart';
import '../state/app_state.dart';
import 'how_support_works_screen.dart';
import 'name_spellings_screen.dart';

/// One person or place in the story (owner, 6 Oct 2026). Three equal
/// choices for how they're kept, side by side, changeable any time. The app
/// never suggests one: the choice is the person's own, in their own time.
class PersonScreen extends StatelessWidget {
  final String name;

  /// `person` or `place`.
  final String kind;

  const PersonScreen({super.key, required this.name, required this.kind});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    final current = state.nameStateOf(name, kind);
    final chosen = current?.state ?? nameAsUsual;
    final lower = name.trim().toLowerCase();
    final moments = state.allEvents
        .where(
          (e) => (kind == 'place' ? e.places : e.people).any(
            (n) => n.trim().toLowerCase() == lower,
          ),
        )
        .length;

    final options = [
      (nameAsUsual, 'As usual', '$name is part of your story as always.'),
      (
        nameQuiet,
        'Quiet',
        '$name doesn\'t come up on their own. Nothing is deleted.',
      ),
      (nameHonored, 'Honored', '$name is kept close and remembered with care.'),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            moments == 1 ? 'In 1 moment' : 'In $moments moments',
            style: theme.textTheme.bodyMedium,
          ),
          if (current != null)
            Text(
              '${current.state == nameQuiet ? 'Quiet' : 'Honored'} since '
              '${DateFormat.yMMMM().format(current.since)}',
              style: theme.textTheme.bodySmall,
            ),
          const SizedBox(height: 16),
          RadioGroup<String>(
            groupValue: chosen,
            onChanged: (v) {
              if (v != null) state.setNameState(name, kind, v);
            },
            child: Column(
              children: [
                for (final (value, title, about) in options)
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    value: value,
                    title: Text(title),
                    subtitle: Text(about),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You can change this any time.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.info_outline),
            title: const Text('How Quiet and Honored work'),

            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const HowSupportWorksScreen()),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.spellcheck),
            title: const Text('Fix the spelling'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NameSpellingsScreen()),
            ),
          ),
        ],
      ),
    );
  }
}
