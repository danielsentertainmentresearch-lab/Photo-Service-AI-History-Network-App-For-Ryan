import 'event.dart';
import 'memory_item.dart';

/// Spelling fixes for the names the AI knows (owner, 5 Oct 2026). Memory is
/// the AI's: people can correct how a person or place is spelled, but not
/// rename them or add anything new, so no one can steer the AI into
/// believing something untrue.

/// Case-insensitive Levenshtein distance.
int editDistance(String a, String b) {
  final s = a.toLowerCase();
  final t = b.toLowerCase();
  var previous = List<int>.generate(t.length + 1, (i) => i);
  for (var i = 1; i <= s.length; i++) {
    final current = List<int>.filled(t.length + 1, 0)..[0] = i;
    for (var j = 1; j <= t.length; j++) {
      final cost = s[i - 1] == t[j - 1] ? 0 : 1;
      current[j] = [
        previous[j] + 1,
        current[j - 1] + 1,
        previous[j - 1] + cost,
      ].reduce((x, y) => x < y ? x : y);
    }
    previous = current;
  }
  return previous[t.length];
}

/// Letters that may change for a name of [length] characters.
int allowedEdits(int length) => length <= 4
    ? 1
    : length <= 8
    ? 2
    : 3;

int _words(String s) => s.trim().split(RegExp(r'\s+')).length;

/// True when [to] is a spelling fix of [from]: a few letters or capitals
/// different, the same number of words, nothing added.
bool isSpellingFix(String from, String to) {
  final a = from.trim();
  final b = to.trim();
  if (a.isEmpty || b.isEmpty || a == b) return false;
  if (b.contains('\n') || b.length > 60) return false;
  if (_words(a) != _words(b)) return false;
  return editDistance(a, b) <= allowedEdits(a.length);
}

/// A person or place the AI knows by name, and how many events name it.
class KnownName {
  final String name;

  /// `person` or `place`.
  final String kind;
  final int events;

  const KnownName(this.name, this.kind, this.events);
}

/// The name an answer memory gives ("Ana: a friend in a red jacket in …").
String? answerName(MemoryItem m) {
  if (m.source != answerSource) return null;
  final name = m.content.split(':').first.trim();
  return name.isEmpty ? null : name;
}

/// Every person and place the AI knows by name, most-used first.
List<KnownName> knownNames(List<LifeEvent> events, List<MemoryItem> memories) {
  final counts = <(String, String), int>{};
  void add(String name, String kind, int n) {
    final key = (name.trim(), kind);
    if (key.$1.isEmpty) return;
    counts[key] = (counts[key] ?? 0) + n;
  }

  for (final e in events) {
    for (final p in e.people.toSet()) {
      add(p, 'person', 1);
    }
    for (final p in e.places.toSet()) {
      add(p, 'place', 1);
    }
  }
  for (final m in memories) {
    final name = answerName(m);
    if (name != null) add(name, m.kind == 'place' ? 'place' : 'person', 0);
  }
  return [
    for (final entry in counts.entries)
      KnownName(entry.key.$1, entry.key.$2, entry.value),
  ]..sort(
    (a, b) => b.events != a.events
        ? b.events - a.events
        : a.name.compareTo(b.name),
  );
}

/// A likely typo: [from] is rarer than [to] and spelled almost the same.
class SpellingSuggestion {
  final String from;
  final String to;
  final String kind;

  const SpellingSuggestion(this.from, this.to, this.kind);
}

/// Names that look like misspellings of a more common name of the same kind
/// ("Jon" in 1 event, "John" in 6).
List<SpellingSuggestion> spellingSuggestions(List<KnownName> names) {
  final suggestions = <SpellingSuggestion>[];
  for (final rare in names) {
    KnownName? best;
    for (final common in names) {
      if (common.kind != rare.kind || common.events <= rare.events) continue;
      if (!isSpellingFix(rare.name, common.name)) continue;
      if (best == null || common.events > best.events) best = common;
    }
    if (best != null) {
      suggestions.add(SpellingSuggestion(rare.name, best.name, rare.kind));
    }
  }
  return suggestions;
}

/// Replaces [from] with [to] wherever it stands as a whole word or phrase.
String replaceName(String text, String from, String to) {
  if (text.isEmpty || from.trim().isEmpty) return text;
  final pattern = RegExp(
    '(?<![\\p{L}\\p{N}])${RegExp.escape(from.trim())}(?![\\p{L}\\p{N}])',
    unicode: true,
  );
  return text.replaceAll(pattern, to.trim());
}
