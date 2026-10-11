import 'package:intl/intl.dart';

import 'learned_point.dart';
import 'memory_item.dart';

/// The readable `memory.md` in the full export: what the AI currently holds
/// about the person's story (docs/MEMORY_ARCHITECTURE.md, build note 7).
/// Active points and the current dream state only; versions stay in the
/// app.
String memoryMarkdown(
  List<LearnedPoint> points,
  DreamState? dream, {
  DateTime? at,
}) {
  final out = StringBuffer('# What the AI remembers\n\n');
  if (at != null) {
    out.writeln('Exported ${DateFormat.yMMMMd().add_jm().format(at)}.\n');
  }
  final active = points.where((p) => p.isActive).toList();
  if (active.isEmpty && dream == null) {
    out.writeln('The AI doesn\'t remember anything yet.');
    return out.toString();
  }
  if (dream != null &&
      (dream.foundationStatements.isNotEmpty || dream.themes.isNotEmpty)) {
    out.writeln('## The story so far\n');
    for (final s in dream.foundationStatements) {
      out.writeln('- $s');
    }
    if (dream.themes.isNotEmpty) {
      out.writeln('\nThemes: ${dream.themes.join(', ')}');
    }
    out.writeln();
  }
  for (final kind in memoryKinds) {
    final ofKind = active.where((p) => p.kind == kind).toList();
    if (ofKind.isEmpty) continue;
    out.writeln('## ${memoryKindLabel(kind)}\n');
    for (final p in ofKind) {
      out.writeln(
        '- ${p.content} (feeling: ${p.sentiment.polarity}, '
        '${p.sentiment.intensity})',
      );
    }
    out.writeln();
  }
  return out.toString();
}
