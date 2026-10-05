import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../widgets/markdown_text.dart';

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
            children: renderMarkdown(
              context,
              text,
              blocks: const {eraseButtonMarker: EraseAiMemoryButton()},
            ),
          );
        },
      ),
    );
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
