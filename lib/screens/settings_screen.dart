import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ai/event_describer.dart';
import '../app.dart';
import '../services/auth_service.dart';
import '../services/recents_privacy.dart';
import '../state/app_state.dart';
import 'data_screen.dart';

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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'That does not look like an Anthropic API key '
            '(they start with "sk-ant-").',
          ),
        ),
      );
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
          const _AccountSection(),
          const Divider(height: 32),
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
                  icon: Icon(
                    _obscure ? Icons.visibility : Icons.visibility_off,
                  ),
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
                onPressed: _saveKey,
                child: const Text('Save key'),
              ),
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
          const _ExportSection(),
          const Divider(height: 32),
          Text('Privacy', style: theme.textTheme.titleMedium),
          const _RecentsToggle(),
          const SizedBox(height: 4),
          Text(
            'Your photos, notes and memories are stored only on this device. '
            'When an event is described, its photos (resized), your notes, '
            'summaries of recent events and your saved memories are sent to '
            'Anthropic\'s API over an encrypted connection. Your free writes '
            'are sent to Anthropic only to make their labels. Uninstalling '
            'the app deletes all of its data.',
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

class _AccountSection extends StatelessWidget {
  const _AccountSection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthService>();
    final lock = context.watch<BiometricLock>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Account', style: theme.textTheme.titleMedium),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.person_outline),
          title: Text(auth.user?.label ?? 'Not signed in'),
          subtitle: const Text('Signed in'),
        ),
        FutureBuilder<bool>(
          future: lock.supported,
          builder: (context, snap) => SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.fingerprint),
            title: const Text('Unlock with fingerprint or face'),
            subtitle: snap.data == false
                ? const Text('Not available on this device')
                : const Text('Asked each time the app opens'),
            value: lock.enabled,
            onChanged: snap.data == true
                ? (on) async {
                    final ok = await lock.setEnabled(on);
                    if (!ok && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Not turned on.')),
                      );
                    }
                  }
                : null,
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () async {
              Navigator.of(context).popUntil((route) => route.isFirst);
              await auth.signOut();
            },
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            onPressed: () => _deleteAccount(context, auth),
            icon: const Icon(Icons.person_remove_outlined),
            label: const Text('Delete account'),
          ),
        ),
      ],
    );
  }

  Future<void> _deleteAccount(BuildContext context, AuthService auth) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete your account?'),
        content: const Text(
          'Your account is deleted permanently and you\'ll need a new one to '
          'use the app. Events, photos and memories on this phone are not '
          'deleted; uninstall the app to remove them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete account'),
          ),
        ],
      ),
    );
    if (yes != true || !context.mounted) return;
    try {
      await auth.deleteAccount();
      if (context.mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on AuthException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}

class _RecentsToggle extends StatelessWidget {
  const _RecentsToggle();

  @override
  Widget build(BuildContext context) {
    final privacy = context.watch<RecentsPrivacy?>();
    if (privacy == null) return const SizedBox.shrink();
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      secondary: const Icon(Icons.visibility_off_outlined),
      title: const Text('Hide in recent apps'),
      subtitle: const Text(
        'Blanks the app in the app switcher so photos aren\'t visible. '
        'Also blocks screenshots of the app.',
      ),
      value: privacy.enabled,
      onChanged: privacy.setEnabled,
    );
  }
}

class _ExportSection extends StatelessWidget {
  const _ExportSection();

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.insights_outlined),
      title: const Text('Your data and export'),
      subtitle: const Text(
        'Meters for your whole library, a free CSV export, and the full '
        'export once you reach 100 events.',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const DataScreen()),
      ),
    );
  }
}
