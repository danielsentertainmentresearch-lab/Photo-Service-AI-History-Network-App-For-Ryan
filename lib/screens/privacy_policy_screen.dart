import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

/// Where the erase button sits in PRIVACY_POLICY.md: directly under the
/// promise about what the AI remembers and the consequences of erasing it.
const eraseButtonMarker = '<!-- erase-ai-memory-button -->';

/// The privacy policy, bundled with the app (PRIVACY_POLICY.md, the same
/// text as the web copy). The "Erase what the AI remembers" button lives
/// inside it, under its own section (owner, 5 Oct 2026).
class PrivacyPolicyScreen extends StatelessWidget {
  /// The policy text; read from the bundled PRIVACY_POLICY.md when null.
  final String? policy;

  const PrivacyPolicyScreen({super.key, this.policy});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy policy')),
      body: FutureBuilder<String>(
        future: policy != null
            ? Future.value(policy)
            : DefaultAssetBundle.of(context).loadString('PRIVACY_POLICY.md'),
        builder: (context, snap) {
          final text = snap.data;
          if (text == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: _render(context, text),
          );
        },
      ),
    );
  }

  /// A small Markdown reader for the policy: headings, paragraphs and
  /// bullet lists; links and emphasis shown as plain text.
  static List<Widget> _render(BuildContext context, String markdown) {
    final theme = Theme.of(context);
    String plain(String s) => s
        .replaceAll(RegExp(r'\*\*|__'), '')
        .replaceAllMapped(RegExp(r'(^|\s)_([^_]+)_'), (m) => '${m[1]}${m[2]}')
        .replaceAllMapped(RegExp(r'<(https?://[^>]+)>'), (m) => m[1]!)
        .replaceAll('`', '');

    final widgets = <Widget>[];
    final paragraph = <String>[];
    final bullets = <String>[];

    void flush() {
      if (paragraph.isNotEmpty) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(plain(paragraph.join(' '))),
          ),
        );
        paragraph.clear();
      }
      if (bullets.isNotEmpty) {
        for (final b in bullets) {
          widgets.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 6, left: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  '),
                  Expanded(child: Text(plain(b))),
                ],
              ),
            ),
          );
        }
        widgets.add(const SizedBox(height: 6));
        bullets.clear();
      }
    }

    for (final raw in markdown.split('\n')) {
      final line = raw.trimRight();
      if (line.trim() == eraseButtonMarker) {
        flush();
        widgets.add(const EraseAiMemoryButton());
      } else if (line.startsWith('#')) {
        flush();
        final level = line.indexOf(' ');
        final style = switch (level) {
          1 => theme.textTheme.headlineSmall,
          2 => theme.textTheme.titleLarge,
          _ => theme.textTheme.titleMedium,
        };
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: Text(plain(line.substring(level + 1)), style: style),
          ),
        );
      } else if (line.trim().isEmpty) {
        flush();
      } else if (line.startsWith('- ')) {
        if (paragraph.isNotEmpty) flush();
        bullets.add(line.substring(2));
      } else if (bullets.isNotEmpty && line.startsWith('  ')) {
        bullets[bullets.length - 1] += ' ${line.trim()}';
      } else {
        if (bullets.isNotEmpty) flush();
        paragraph.add(line.trim());
      }
    }
    flush();
    return widgets;
  }
}

/// Erases everything the AI remembers, after the person types ERASE.
class EraseAiMemoryButton extends StatelessWidget {
  const EraseAiMemoryButton({super.key});

  Future<void> _confirm(BuildContext context) async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => const _EraseDialog(),
    );
    if (ok != true) return;
    await state.eraseAiMemory();
    messenger.showSnackBar(
      const SnackBar(content: Text('Everything the AI remembered is erased.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final empty = context.watch<AppState>().memories.isEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: empty ? null : () => _confirm(context),
            icon: const Icon(Icons.delete_forever_outlined),
            label: const Text('Erase what the AI remembers'),
          ),
          if (empty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'The AI doesn\'t remember anything yet.',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}

class _EraseDialog extends StatefulWidget {
  const _EraseDialog();

  @override
  State<_EraseDialog> createState() => _EraseDialogState();
}

class _EraseDialogState extends State<_EraseDialog> {
  final _typed = TextEditingController();

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _typed.text.trim() == 'ERASE';
    return AlertDialog(
      title: const Text('Erase what the AI remembers?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This can\'t be undone. The AI will no longer know who anyone is '
            'and will start learning again. Your events, photos, accounts '
            'and free writes stay.\n\nType ERASE to confirm.',
          ),
          TextField(
            controller: _typed,
            autocorrect: false,
            textCapitalization: TextCapitalization.characters,
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: ready ? () => Navigator.pop(context, true) : null,
          child: const Text('Erase'),
        ),
      ],
    );
  }
}
