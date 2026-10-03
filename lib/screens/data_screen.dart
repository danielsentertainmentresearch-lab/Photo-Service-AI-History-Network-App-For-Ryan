import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ai/data_platform_advisor.dart';
import '../models/library_meters.dart';
import '../services/data_files.dart';
import '../services/export_service.dart';
import '../state/app_state.dart';

/// Where the whole library is measured and exported. Every meter is free;
/// people can remove any meter and bring it back later.
class DataScreen extends StatelessWidget {
  const DataScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final hidden = state.hiddenMeters;
    final meters = computeMeters(
      events: state.allEvents,
      memories: state.memories,
      graph: state.graphSnapshot,
    );
    final shown = meters.where((m) => !hidden.contains(m.id)).toList();
    final hiddenCount = meters.length - shown.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your data'),
        actions: [
          IconButton(
            tooltip: 'Choose meters',
            icon: const Icon(Icons.tune),
            onPressed: () => _editMeters(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const _ExportCard(),
          const SizedBox(height: 20),
          Text(
            'Your library at a glance',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (shown.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('All meters are hidden.'),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 600 ? 3 : 2;
                final width =
                    (constraints.maxWidth - 8 * (columns - 1)) / columns;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final m in shown)
                      SizedBox(
                        width: width,
                        child: _MeterCard(meter: m),
                      ),
                  ],
                );
              },
            ),
          if (hiddenCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextButton.icon(
                onPressed: () => _editMeters(context),
                icon: const Icon(Icons.visibility_outlined),
                label: Text(
                  hiddenCount == 1
                      ? '1 hidden meter: show it again'
                      : '$hiddenCount hidden meters: show them again',
                ),
              ),
            ),
        ],
      ),
    );
  }

  static Future<void> _editMeters(BuildContext context) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => const _MeterPicker(),
      );
}

class _MeterCard extends StatelessWidget {
  final Meter meter;

  const _MeterCard({required this.meter});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(meter.label, style: theme.textTheme.labelMedium),
            const SizedBox(height: 4),
            Text(
              meter.value,
              style: theme.textTheme.titleLarge,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (meter.detail != null)
              Text(
                meter.detail!,
                style: theme.textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }
}

class _MeterPicker extends StatelessWidget {
  const _MeterPicker();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final hidden = state.hiddenMeters;
    final meters = computeMeters(
      events: state.allEvents,
      memories: state.memories,
      graph: state.graphSnapshot,
    );
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, controller) => ListView(
        controller: controller,
        children: [
          ListTile(
            title: Text(
              'Choose meters',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            subtitle: const Text(
              'Turn off what you don\'t need. You can turn it back on any '
              'time. All meters are free.',
            ),
            trailing: hidden.isEmpty
                ? null
                : TextButton(
                    onPressed: () async {
                      for (final id in hidden) {
                        await state.setMeterHidden(id, false);
                      }
                    },
                    child: const Text('Show all'),
                  ),
          ),
          for (final m in meters)
            SwitchListTile(
              title: Text(m.label),
              value: !hidden.contains(m.id),
              onChanged: (on) => state.setMeterHidden(m.id, !on),
            ),
        ],
      ),
    );
  }
}

/// Export: a free basic CSV for everyone; the full export (zip, analysis
/// file and guide) once the library reaches [exportUnlockEvents] events.
class _ExportCard extends StatefulWidget {
  const _ExportCard();

  @override
  State<_ExportCard> createState() => _ExportCardState();
}

class _ExportCardState extends State<_ExportCard> {
  String? _busy;

  Future<void> _share(
    String label,
    Future<File> Function(Directory) make,
  ) async {
    setState(() => _busy = label);
    try {
      final file = await make(await getTemporaryDirectory());
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], subject: 'EventLens $label'),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Widget _button(
    String label,
    IconData icon,
    Future<File> Function(Directory) make, {
    bool primary = false,
  }) {
    final busy = _busy == label;
    final iconWidget = busy
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(icon);
    final onPressed = _busy != null ? null : () => _share(label, make);
    return SizedBox(
      width: double.infinity,
      child: primary
          ? FilledButton.icon(
              onPressed: onPressed,
              icon: iconWidget,
              label: Text(label),
            )
          : OutlinedButton.icon(
              onPressed: onPressed,
              icon: iconWidget,
              label: Text(label),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = context.watch<AppState>();
    final exporter = LibraryExporter(state.vault);
    final count = state.allEvents.length;

    final basic = _button(
      'Basic CSV',
      Icons.table_chart_outlined,
      (dir) => exporter.writeText(
        withBom(basicCsv(state.allEvents)),
        dir,
        LibraryExporter.basicCsvName,
      ),
      primary: !state.exportUnlocked,
    );

    if (!state.exportUnlocked) {
      return Card(
        color: theme.colorScheme.surfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Export', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Save your events as a spreadsheet file (CSV). Free, any '
                'time.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              basic,
              const SizedBox(height: 16),
              _PreviewBanner(count: count),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Export', style: theme.textTheme.titleMedium),
                Chip(
                  label: const Text('Full export unlocked'),
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.lock_open, size: 16),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'The full export holds everything: photos, an Obsidian vault, '
              'both CSV files and a data file.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            _button(
              'Full export (zip)',
              Icons.folder_zip_outlined,
              (dir) => exporter.exportZip(
                events: state.allEvents,
                memories: state.memories,
                graph: state.graphSnapshot,
                directory: dir,
              ),
              primary: true,
            ),
            const SizedBox(height: 8),
            basic,
            const SizedBox(height: 8),
            _button(
              'Analysis CSV (for Python)',
              Icons.analytics_outlined,
              (dir) => exporter.writeText(
                analysisCsv(state.allEvents, state.graphSnapshot),
                dir,
                LibraryExporter.analysisCsvName,
              ),
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DataGuideScreen()),
              ),
              icon: const Icon(Icons.menu_book_outlined),
              label: const Text('How to explore your data with Python'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown until the full export unlocks: what it holds and how close it is.
class _PreviewBanner extends StatelessWidget {
  final int count;

  const _PreviewBanner({required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final left = exportUnlockEvents - count;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.lock_outline,
                size: 18,
                color: theme.colorScheme.onSecondaryContainer,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Preview: full export',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Unlocks at $exportUnlockEvents events. '
            '${left == 1 ? '1 more event' : '$left more events'} to go.',
            style: TextStyle(color: theme.colorScheme.onSecondaryContainer),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: count / exportUnlockEvents),
          const SizedBox(height: 4),
          Text(
            '$count of $exportUnlockEvents events',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(height: 8),
          for (final item in const [
            'Everything in one zip, with your original photos',
            'A folder of linked notes that opens in Obsidian',
            'An analysis CSV ready for Python and Jupyter notebooks',
            'A simple guide to exploring your data',
          ])
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.check,
                    size: 16,
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      item,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

const _jupyterUrl = 'https://jupyter.org';
const _anacondaUrl = 'https://www.anaconda.com/download';

Future<void> _open(BuildContext context, String url) async {
  final ok = await launchUrl(
    Uri.parse(url),
    mode: LaunchMode.externalApplication,
  ).catchError((_) => false);
  if (!ok && context.mounted) {
    await Clipboard.setData(ClipboardData(text: url));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Couldn\'t open a browser. Link copied: $url')),
      );
    }
  }
}

/// A plain-language guide to opening the analysis CSV in Python, for fun
/// rather than professional work.
class DataGuideScreen extends StatefulWidget {
  const DataGuideScreen({super.key});

  @override
  State<DataGuideScreen> createState() => _DataGuideScreenState();
}

class _DataGuideScreenState extends State<DataGuideScreen> {
  late Future<PlatformAdvice> _advice;

  @override
  void initState() {
    super.initState();
    _advice = context.read<AppState>().dataPlatforms();
  }

  static const _loadCode =
      'import pandas as pd\n'
      'events = pd.read_csv("eventlens-analysis.csv",\n'
      '                     parse_dates=["occurred_at", "created_at"])\n'
      'events.head()';

  static const _tryCode =
      '# Events per year, as a bar chart\n'
      'events.groupby("year").size().plot(kind="bar")\n\n'
      '# The people you record most\n'
      'events["people"].str.split("|").explode().value_counts().head(10)';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget step(int n, String title, String body, {Widget? extra}) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(radius: 14, child: Text('$n')),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(body),
                ?extra,
              ],
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Explore your data')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Card(
            color: theme.colorScheme.tertiaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'This guide is for fun, not professional analysis. Some '
                'Python knowledge is recommended, but you can follow the '
                'steps without it.',
                style: TextStyle(color: theme.colorScheme.onTertiaryContainer),
              ),
            ),
          ),
          const SizedBox(height: 16),
          step(
            1,
            'Get the free tools',
            'Install Anaconda on a computer. It includes Python and Jupyter '
                'Notebook, so there is nothing else to set up.',
            extra: TextButton(
              onPressed: () => _open(context, _anacondaUrl),
              child: const Text('anaconda.com/download'),
            ),
          ),
          step(
            2,
            'Send the file to your computer',
            'Tap "Analysis CSV (for Python)" in Your data and email it to '
                'yourself, or save it to a cloud folder. Put it in a folder '
                'you can find.',
          ),
          step(
            3,
            'Open a notebook',
            'Start Jupyter Notebook from Anaconda, go to that folder, and '
                'create a new Python notebook.',
          ),
          step(
            4,
            'Load your events',
            'Paste this into the first box and press Shift + Enter:',
            extra: const _Code(_loadCode),
          ),
          step(
            5,
            'Try something',
            'Each line is one idea. Paste one into a new box:',
            extra: const _Code(_tryCode),
          ),
          const Divider(height: 32),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Python platforms that can use this file',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Ask the AI again',
                icon: const Icon(Icons.refresh),
                onPressed: () => setState(() {
                  _advice = context.read<AppState>().dataPlatforms(
                    refresh: true,
                  );
                }),
              ),
            ],
          ),
          Text(
            'Chosen by the app\'s AI from the file\'s columns. Only the '
            'column names are sent, never your events.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          FutureBuilder<PlatformAdvice>(
            future: _advice,
            builder: (context, snapshot) {
              final advice = snapshot.data;
              if (advice == null) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 12),
                      Text('Finding platforms…'),
                    ],
                  ),
                );
              }
              if (advice.noneDeterminable) {
                return const ListTile(
                  leading: Icon(Icons.help_outline),
                  title: Text('None determinable'),
                  subtitle: Text(
                    'The AI couldn\'t name a platform for this file.',
                  ),
                );
              }
              return Column(
                children: [
                  if (!advice.fromAi)
                    const ListTile(
                      dense: true,
                      leading: Icon(Icons.info_outline),
                      title: Text(
                        'The AI couldn\'t be reached (it needs your API key '
                        'and a connection), so this is the most likely '
                        'platform rather than a checked list.',
                      ),
                    ),
                  for (final p in advice.platforms)
                    ListTile(
                      leading: const Icon(Icons.terminal),
                      title: Text(p.name),
                      subtitle: Text(p.use),
                      trailing: Text(
                        p.determined ? 'Fits' : 'Likely',
                        style: theme.textTheme.labelMedium,
                      ),
                    ),
                ],
              );
            },
          ),
          const Divider(height: 32),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('What each column means'),
            children: [
              for (final c in analysisColumns)
                ListTile(
                  dense: true,
                  title: Text(c.name),
                  subtitle: Text('${c.type} · ${c.meaning}'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Want to go further? Jupyter\'s official site covers '
            'professional data science and analysis.',
            style: theme.textTheme.bodyMedium,
          ),
          TextButton.icon(
            onPressed: () => _open(context, _jupyterUrl),
            icon: const Icon(Icons.open_in_new),
            label: const Text('jupyter.org'),
          ),
        ],
      ),
    );
  }
}

class _Code extends StatelessWidget {
  final String code;

  const _Code(this.code);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SelectableText(
              code,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
          IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code));
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Copied')));
              }
            },
          ),
        ],
      ),
    );
  }
}
