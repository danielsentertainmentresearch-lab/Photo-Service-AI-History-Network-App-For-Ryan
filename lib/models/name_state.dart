/// How the person keeps someone (or somewhere) in their story (owner,
/// 5 Oct 2026). Three equal choices, changeable any time in any direction,
/// never suggested by the app.
const nameAsUsual = 'usual';

/// The name stops coming up on its own (learning page, sneak-peek insights,
/// On this day). Nothing is deleted.
const nameQuiet = 'quiet';

/// Kept close with care: a Remembering space, gently marked moments, and
/// the AI mentions them with continuity and care.
const nameHonored = 'honored';

class NameState {
  final String name;

  /// `person` or `place`.
  final String kind;
  final String state;

  /// When this state was chosen.
  final DateTime since;

  const NameState({
    required this.name,
    required this.kind,
    required this.state,
    required this.since,
  });

  factory NameState.fromRow(Map<String, Object?> row) => NameState(
    name: row['name'] as String,
    kind: row['kind'] as String,
    state: row['state'] as String,
    since: DateTime.fromMillisecondsSinceEpoch(row['since'] as int),
  );

  Map<String, Object?> toRow() => {
    'name': name,
    'kind': kind,
    'state': state,
    'since': since.millisecondsSinceEpoch,
  };
}

/// Names (lowercase) the person keeps in [state].
Set<String> namesIn(Iterable<NameState> states, String state) => {
  for (final s in states)
    if (s.state == state) s.name.trim().toLowerCase(),
};

/// True when [text] mentions any of [names] as a whole word or phrase.
bool mentionsAny(String text, Set<String> names) {
  if (names.isEmpty || text.isEmpty) return false;
  final lower = text.toLowerCase();
  for (final n in names) {
    if (n.isEmpty) continue;
    final pattern = RegExp(
      '(?<![\\p{L}\\p{N}])${RegExp.escape(n)}(?![\\p{L}\\p{N}])',
      unicode: true,
    );
    if (pattern.hasMatch(lower)) return true;
  }
  return false;
}
