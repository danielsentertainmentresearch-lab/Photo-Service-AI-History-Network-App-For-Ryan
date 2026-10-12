import 'learned_point.dart';
import 'name_state.dart';

/// The memory as prompts read it: the compact text from
/// docs/MEMORY_ARCHITECTURE.md section 2, holding the dream state and the
/// active points that matter most to one request (settled 12 Oct 2026,
/// point 9).
///
/// Evidence is shown as event dates rather than ids, because the requests
/// that read this block know events by date.
class MemoryPrompt {
  /// The limits from build note 8. They apply to the active points; the
  /// dream state has its own limits (5 lines of each kind, 140 characters).
  static const maxPoints = 20;
  static const maxChars = 2000;

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static String _quoted(String text) =>
      '"${text.replaceAll(RegExp(r'\s+'), ' ').trim().replaceAll('"', "'")}"';

  /// The block for one request.
  ///
  /// [points] may hold every status; only active points are shown.
  /// [requestNames] are the people and places the request involves: their
  /// points come first, and a Quiet name's points are shown only when it is
  /// one of them (build note 3). [eventDates] gives each event's date, for
  /// ordering by the most recent evidence.
  static String render({
    required List<LearnedPoint> points,
    DreamState? dream,
    Iterable<String> requestNames = const [],
    Set<String> quietNames = const {},
    Set<String> honoredNames = const {},
    Map<String, DateTime> eventDates = const {},
  }) {
    final involved = {
      for (final n in requestNames)
        if (n.trim().isNotEmpty) n.trim().toLowerCase(),
    };
    // A Quiet name stays out unless the person brought it up in this request.
    final hidden = quietNames.difference(involved);

    DateTime? latest(LearnedPoint p) {
      DateTime? best;
      for (final id in p.eventIds) {
        final d = eventDates[id];
        if (d != null && (best == null || d.isAfter(best))) best = d;
      }
      return best;
    }

    final candidates = [
      for (final p in points)
        if (p.isActive && !mentionsAny(p.content, hidden)) p,
    ];
    final aboutRequest = {
      for (final p in candidates)
        if (mentionsAny(p.content, involved)) p.id,
    };
    final latestOf = {for (final p in candidates) p.id: latest(p)};
    candidates.sort((a, b) {
      final byRequest = (aboutRequest.contains(a.id) ? 0 : 1).compareTo(
        aboutRequest.contains(b.id) ? 0 : 1,
      );
      if (byRequest != 0) return byRequest;
      final la = latestOf[a.id], lb = latestOf[b.id];
      if (la != lb) {
        if (la == null) return 1;
        if (lb == null) return -1;
        return lb.compareTo(la);
      }
      final byEvidence = b.eventIds.length.compareTo(a.eventIds.length);
      if (byEvidence != 0) return byEvidence;
      return b.createdAt.compareTo(a.createdAt);
    });

    String line(LearnedPoint p) {
      final dates = [
        for (final id in p.eventIds)
          if (eventDates[id] case final d?) _date(d),
      ]..sort();
      final honored = mentionsAny(p.content, honoredNames) ? ' [Honored]' : '';
      return '- {kind: ${p.kind}, sent: ${p.sentiment.compact}, '
          'cont: ${_quoted(p.content)}, src: ${p.source}, '
          'ev: [${dates.join(', ')}]}$honored';
    }

    final shown = <String>[];
    var used = 0;
    for (final p in candidates) {
      if (shown.length == maxPoints) break;
      final l = line(p);
      if (used + l.length + 1 > maxChars) continue;
      shown.add(l);
      used += l.length + 1;
    }

    String dreamText() {
      if (dream == null) return '[DREAM: none yet]';
      String mark(String s) =>
          mentionsAny(s, honoredNames) ? '$s [Honored]' : s;
      final statements = [
        for (final s in dream.foundationStatements)
          if (!mentionsAny(s, hidden)) mark(s.trim()),
      ];
      final themes = [
        for (final t in dream.themes)
          if (!mentionsAny(t, hidden)) mark(t.trim()),
      ];
      if (statements.isEmpty && themes.isEmpty) return '[DREAM: none yet]';
      return '[DREAM: ${statements.join(' | ')}'
          '${themes.isEmpty ? '' : '. Themes: ${themes.join(', ')}'}.]';
    }

    return [
      'MEMORY_V8:',
      dreamText(),
      if (shown.isEmpty)
        '[ACTIVE: none]'
      else
        '[ACTIVE:\n${shown.join('\n')}\n]',
    ].join('\n');
  }
}
