import 'package:flutter/material.dart';

/// A small Markdown reader for the app's bundled documents (privacy policy,
/// how support works): headings, paragraphs and bullet lists; links and
/// emphasis shown as plain text. A line that is exactly a key of [blocks]
/// (an HTML comment, invisible on the web) is replaced by that widget.
List<Widget> renderMarkdown(
  BuildContext context,
  String markdown, {
  Map<String, Widget> blocks = const {},
}) {
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
    if (blocks.containsKey(line.trim())) {
      flush();
      widgets.add(blocks[line.trim()]!);
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
