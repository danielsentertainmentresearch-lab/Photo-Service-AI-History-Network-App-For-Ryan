import '../models/learned_point.dart';
import '../models/memory_item.dart';
import '../models/name_state.dart';
import 'dream_pass.dart';
import 'event_describer.dart' show parseStructured;

/// A new point the dream pass learned.
class PointAdd {
  final String kind;
  final String content;
  final Sentiment sentiment;
  final List<String> eventIds;
  final String reason;

  const PointAdd({
    required this.kind,
    required this.content,
    required this.sentiment,
    required this.eventIds,
    required this.reason,
  });
}

/// A new version of an existing point. Reviving an archived point is a
/// revision that makes it active again.
class PointRevision {
  final String pointId;
  final String content;
  final Sentiment sentiment;

  /// The new evidence; the coordinator adds it to the point's earlier
  /// evidence.
  final List<String> eventIds;
  final String reason;
  final bool revives;

  const PointRevision({
    required this.pointId,
    required this.content,
    required this.sentiment,
    required this.eventIds,
    required this.reason,
    this.revives = false,
  });
}

/// An active point archived ("true, but no longer current") or retired
/// ("no longer true").
class PointStatusChange {
  final String pointId;
  final String status;
  final List<String> eventIds;
  final String reason;

  const PointStatusChange({
    required this.pointId,
    required this.status,
    required this.eventIds,
    required this.reason,
  });
}

/// The next dream state.
class DreamUpdate {
  final List<String> foundationStatements;
  final List<String> themes;
  final List<String> eventIds;

  const DreamUpdate({
    required this.foundationStatements,
    required this.themes,
    required this.eventIds,
  });
}

/// The checked result of one dream pass: only changes that keep every rule.
/// The reply's overall reasoning is read here and never kept (settled
/// 12 Oct 2026, point 6).
class DreamChanges {
  final List<PointAdd> adds;
  final List<PointRevision> revisions;
  final List<PointStatusChange> statusChanges;
  final DreamUpdate? dream;

  /// How many proposed changes or dream lines the checker turned down.
  final int rejected;

  const DreamChanges({
    this.adds = const [],
    this.revisions = const [],
    this.statusChanges = const [],
    this.dream,
    this.rejected = 0,
  });

  bool get isEmpty =>
      adds.isEmpty &&
      revisions.isEmpty &&
      statusChanges.isEmpty &&
      dream == null;

  /// Words in a row from a free write that make a line a quote (point 10).
  static const quoteWords = 6;

  static final _marks = RegExp(r'\s*\[(Honored|Quiet)\]', caseSensitive: false);

  static List<String> _words(String text) => [
    for (final w in text.toLowerCase().split(
      RegExp(r'[^\p{L}\p{N}]+', unicode: true),
    ))
      if (w.isNotEmpty) w,
  ];

  /// Every run of [quoteWords] words in [freeWrites], joined by spaces.
  static Set<String> _quoteRuns(Iterable<String> freeWrites) => {
    for (final text in freeWrites)
      if (_words(text) case final w)
        for (var i = 0; i + quoteWords <= w.length; i++)
          w.sublist(i, i + quoteWords).join(' '),
  };

  static bool _quotes(String line, Set<String> runs) {
    if (runs.isEmpty) return false;
    final w = _words(line);
    for (var i = 0; i + quoteWords <= w.length; i++) {
      if (runs.contains(w.sublist(i, i + quoteWords).join(' '))) return true;
    }
    return false;
  }

  /// One plain line without echoed name marks, or empty.
  static String _clean(Object? raw) => '${raw ?? ''}'
      .replaceAll(_marks, '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Checks a dream pass [response] against [request] and [input].
  ///
  /// [freeWrites] are the person's free writes, read on the phone only to
  /// turn down quotes; they are never sent. Support readings can't reach
  /// memory: the request never contains them and the reply has no field for
  /// them, and the words a support reading quotes are part of a free write,
  /// so the quote check covers them too.
  static DreamChanges parse(
    Map<String, dynamic> response, {
    required DreamRequest request,
    required DreamInput input,
    Iterable<String> freeWrites = const [],
  }) {
    final data = parseStructured(response);
    final runs = _quoteRuns(freeWrites);
    var rejected = 0;

    List<String> evidence(Object? refs) {
      final ids = <String>[];
      for (final r in (refs is List ? refs : const [])) {
        final id = request.eventRefs['$r'.trim().toLowerCase()];
        if (id != null && !ids.contains(id)) ids.add(id);
      }
      return ids;
    }

    bool fitsPoint(String content) =>
        content.isNotEmpty &&
        content.length <= DreamPass.maxContent &&
        !_quotes(content, runs);

    Sentiment sentiment(Map item) => Sentiment.parse(
      item['polarity'] as String?,
      item['intensity'] as String?,
      dreamSentiment,
    );

    List<Map> items(String key) =>
        ((data[key] as List?) ?? const []).whereType<Map>().toList();

    final touched = <String>{};
    final known = {
      for (final p in input.active) p.content.trim().toLowerCase(),
    };

    final adds = <PointAdd>[];
    for (final item in items('add_active')) {
      final content = _clean(item['content']);
      final ids = evidence(item['event_ids']);
      final kind = '${item['kind']}';
      if (adds.length == DreamPass.maxChanges ||
          !memoryKinds.contains(kind) ||
          !fitsPoint(content) ||
          ids.isEmpty ||
          !known.add(content.toLowerCase())) {
        rejected++;
        continue;
      }
      adds.add(
        PointAdd(
          kind: kind,
          content: content,
          sentiment: sentiment(item),
          eventIds: ids,
          reason: _clean(item['reason']),
        ),
      );
    }

    final revisions = <PointRevision>[];
    for (final item in items('revise_active')) {
      final ref = '${item['id']}'.trim().toLowerCase();
      final pointId = request.pointRefs[ref];
      final content = _clean(item['new_content']);
      final ids = evidence(item['event_ids']);
      if (revisions.length == DreamPass.maxChanges ||
          pointId == null ||
          !fitsPoint(content) ||
          ids.isEmpty ||
          !touched.add(pointId)) {
        rejected++;
        continue;
      }
      revisions.add(
        PointRevision(
          pointId: pointId,
          content: content,
          sentiment: sentiment(item),
          eventIds: ids,
          reason: _clean(item['reason']),
          revives: request.archivedRefs.contains(ref),
        ),
      );
    }

    final statusChanges = <PointStatusChange>[];
    for (final (key, status) in [
      ('archive_active', pointArchived),
      ('retire_active', pointRetired),
    ]) {
      var count = 0;
      for (final item in items(key)) {
        final ref = '${item['id']}'.trim().toLowerCase();
        final pointId = request.pointRefs[ref];
        final ids = evidence(item['event_ids']);
        // Only active points can be archived or retired; an archived point
        // stays archived unless the pass revives it.
        if (count == DreamPass.maxChanges ||
            pointId == null ||
            request.archivedRefs.contains(ref) ||
            ids.isEmpty ||
            !touched.add(pointId)) {
          rejected++;
          continue;
        }
        count++;
        statusChanges.add(
          PointStatusChange(
            pointId: pointId,
            status: status,
            eventIds: ids,
            reason: _clean(item['reason']),
          ),
        );
      }
    }

    DreamUpdate? dream;
    final update = data['update_dream'];
    if (update is Map && update['changed'] == true) {
      List<String> lines(Object? raw, int max) {
        final out = <String>[];
        for (final r in (raw is List ? raw : const [])) {
          final line = _clean(r);
          if (out.length == max ||
              line.isEmpty ||
              line.length > DreamPass.maxDreamLine ||
              _quotes(line, runs) ||
              mentionsAny(line, input.quietNames) ||
              out.contains(line)) {
            rejected++;
            continue;
          }
          out.add(line);
        }
        return out;
      }

      final statements = lines(
        update['foundation_statements'],
        DreamPass.maxStatements,
      );
      final themes = lines(update['themes'], DreamPass.maxThemes);
      final ids = evidence(update['event_ids']);
      if (ids.isEmpty || (statements.isEmpty && themes.isEmpty)) {
        rejected++;
      } else {
        dream = DreamUpdate(
          foundationStatements: statements,
          themes: themes,
          eventIds: ids,
        );
      }
    }

    return DreamChanges(
      adds: adds,
      revisions: revisions,
      statusChanges: statusChanges,
      dream: dream,
      rejected: rejected,
    );
  }
}
