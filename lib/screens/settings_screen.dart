import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ai/event_describer.dart';
import '../app.dart';
import '../state/app_state.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _keyController = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _saveKey() async {
    final key = _keyController.text.trim();
    if (!key.startsWith('sk-ant-')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('That does not look like an Anthropic API key '
              '(they start with "sk-ant-").')));
      return;
    }
    await context.read<AppState>().setApiKey(key);
    _keyController.clear();
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('API key saved')));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Anthropic API key', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'The AI runs on Anthropic\'s Claude using your own API key. Create '
            'one at console.anthropic.com → API Keys. Usage is billed to your '
            'Anthropic account. The key is stored encrypted on this device.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          if (state.hasApiKey)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.check_circle, color: Colors.green),
              title: const Text('API key saved'),
              trailing: TextButton(
                onPressed: () => state.setApiKey(null),
                child: const Text('Remove'),
              ),
            )
          else
            TextField(
              controller: _keyController,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'sk-ant-…',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              onSubmitted: (_) => _saveKey(),
            ),
          if (!state.hasApiKey) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                  onPressed: _saveKey, child: const Text('Save key')),
            ),
          ],
          const Divider(height: 32),
          Text('AI model', style: theme.textTheme.titleMedium),
          RadioGroup<String>(
            groupValue: state.model,
            onChanged: (v) => v == null ? null : state.setModel(v),
            child: Column(
              children: [
                for (final entry in supportedModels.entries)
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    value: entry.key,
                    title: Text(entry.value),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text('Thinking effort', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Higher effort gives more careful, detailed accounts but takes '
            'longer and costs more.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: [
              for (final e in supportedEfforts)
                ButtonSegment(value: e, label: Text(_effortLabel(e))),
            ],
            selected: {state.effort},
            onSelectionChanged: (s) => state.setEffort(s.first),
          ),
          const Divider(height: 32),
          Text('Privacy', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Your photos, notes and memories are stored only on this device. '
            'When an event is described, its photos (resized), your notes, '
            'summaries of recent events and your saved memories are sent to '
            'Anthropic\'s API over an encrypted connection. Uninstalling the '
            'app deletes all of its data.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.info_outline),
            title: const Text('About'),
            onTap: () => showAboutDialog(
              context: context,
              applicationName: appName,
              applicationVersion: '1.0.0',
              applicationLegalese:
                  'Record events with photos; AI writes the full story.',
            ),
          ),
        ],
      ),
    );
  }

  static String _effortLabel(String e) => switch (e) {
        'low' => 'Low',
        'medium' => 'Medium',
        'high' => 'High',
        'xhigh' => 'Max',
        _ => e,
      };
}
