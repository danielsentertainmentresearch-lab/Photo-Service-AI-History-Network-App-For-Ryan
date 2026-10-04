import 'package:intl/intl.dart';

import '../models/event.dart';
import '../models/memory_graph.dart';
import '../models/ring_palette.dart';

/// Events needed before the full export (zip + analysis file) unlocks.
/// Below it, the basic CSV is available to everyone, free.
const exportUnlockEvents = 100;

/// One column of the analysis file, for the in-app data dictionary.
class DataColumn {
  final String name;
  final String type;
  final String meaning;

  const DataColumn(this.name, this.type, this.meaning);
}

/// Stands in for an unknown number in the analysis file, so number columns
/// stay numbers. No real latitude, longitude, temperature, rain or wind
/// reading can be this value.
const unknownNumber = -999;

/// Columns of the analysis-ready CSV, in order. No cell is ever blank:
/// unknown text is a word ("unknown", "none"), unknown numbers are
/// [unknownNumber], and the has_ columns say which rows have real values.
const analysisColumns = <DataColumn>[
  DataColumn('event_id', 'text', 'Unique id of the event'),
  DataColumn('occurred_at', 'datetime', 'When it happened (ISO 8601)'),
  DataColumn('date', 'date', 'Day it happened (YYYY-MM-DD)'),
  DataColumn('year', 'integer', 'Year'),
  DataColumn('month', 'integer', 'Month, 1-12'),
  DataColumn('weekday', 'text', 'Day of the week (Mon-Sun)'),
  DataColumn('hour', 'integer', 'Hour of the day, 0-23'),
  DataColumn('title', 'text', 'Event title, "untitled" if none'),
  DataColumn('location', 'text', 'Place as typed or found from the photo, "unknown" if none'),
  DataColumn('has_location', '0/1', '1 if latitude and longitude are known'),
  DataColumn('latitude', 'number', 'Latitude, $unknownNumber if unknown'),
  DataColumn('longitude', 'number', 'Longitude, $unknownNumber if unknown'),
  DataColumn('described', '0/1', '1 if the AI has written the account'),
  DataColumn('photo_count', 'integer', 'Photos in the event'),
  DataColumn('notes_words', 'integer', 'Words in your own notes'),
  DataColumn('description_words', 'integer', 'Words in the AI account'),
  DataColumn('people_count', 'integer', 'People named'),
  DataColumn('places_count', 'integer', 'Places named'),
  DataColumn('tags_count', 'integer', 'Tags'),
  DataColumn('people', 'list', 'People, separated by |, "none" if none'),
  DataColumn('places', 'list', 'Places, separated by |, "none" if none'),
  DataColumn('tags', 'list', 'Tags, separated by |, "none" if none'),
  DataColumn('chapter', 'text', 'Timeline chapter, "none" if none'),
  DataColumn('book', 'text', 'Your Book, "none" if none'),
  DataColumn('themes', 'list', 'Story themes, separated by |, "none" if none'),
  DataColumn('ring_color', 'text', 'Ring colour as #RRGGBB, "none" if none'),
  DataColumn('has_weather', '0/1', '1 if the weather was looked up'),
  DataColumn('weather_condition', 'text', 'Weather, "not looked up" if none'),
  DataColumn('temperature_c', 'number', 'Temperature in °C, $unknownNumber if not looked up'),
  DataColumn('precipitation_mm', 'number', 'Rain or snow in mm, $unknownNumber if not looked up'),
  DataColumn('wind_kmh', 'number', 'Wind speed in km/h, $unknownNumber if not looked up'),
  DataColumn('created_at', 'datetime', 'When you added it to the app'),
  DataColumn('free_write_words', 'integer', 'Words in your free write, 0 if none'),
];

/// Titles of the label columns that follow [analysisColumns]: one per
/// free-write label, most used first. A label that matches a fixed column's
/// name gets " (label)" added so no two columns share a title.
List<String> labelColumns(List<LifeEvent> events) {
  final counts = <String, int>{};
  for (final e in events) {
    for (final label in e.experienceLabels) {
      counts[label] = (counts[label] ?? 0) + 1;
    }
  }
  return (counts.keys.toList()..sort(
        (a, b) => counts[b] != counts[a]
            ? counts[b]! - counts[a]!
            : a.compareTo(b),
      ));
}

String _labelTitle(String label) =>
    analysisColumns.any((c) => c.name == label) ? '$label (label)' : label;

/// RFC 4180 CSV: fields with commas, quotes or line breaks are quoted.
/// Lines end with CRLF, and a UTF-8 byte order mark is added by
/// [withBom] so spreadsheet apps read accents correctly.
String encodeCsv(List<List<Object?>> rows) {
  String field(Object? value) {
    final text = value == null ? '' : '$value';
    if (text.contains(RegExp('[",\r\n]'))) {
      return '"${text.replaceAll('"', '""')}"';
    }
    return text;
  }

  return '${rows.map((r) => r.map(field).join(',')).join('\r\n')}\r\n';
}

String withBom(String csv) => '﻿$csv';

int _words(String text) =>
    text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;

List<LifeEvent> _ordered(List<LifeEvent> events) =>
    [...events]..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));

/// The basic CSV: one readable row per event, for spreadsheets. Free for
/// everyone at any size of library.
String basicCsv(List<LifeEvent> events) {
  final date = DateFormat('yyyy-MM-dd');
  final time = DateFormat('HH:mm');
  return encodeCsv([
    [
      'Date',
      'Time',
      'Title',
      'Place',
      'People',
      'Places',
      'Tags',
      'Photos',
      'Summary',
      'Account',
      'My notes',
    ],
    for (final e in _ordered(events))
      [
        date.format(e.occurredAt),
        time.format(e.occurredAt),
        e.title,
        e.location,
        e.people.join('; '),
        e.places.join('; '),
        e.tags.join('; '),
        e.images.length,
        e.summary,
        e.description,
        e.notes,
      ],
  ]);
}

/// The analysis CSV: tidy, typed columns (see [analysisColumns]) that load
/// straight into pandas, Jupyter or similar tools.
String analysisCsv(List<LifeEvent> events, GraphSnapshot? graph) {
  final chapterOf = <String, TimelineChapter>{};
  for (final c in graph?.chapters ?? <TimelineChapter>[]) {
    for (final id in c.eventIds) {
      chapterOf[id] = c;
    }
  }
  final bookTitle = {for (final b in graph?.books ?? <Book>[]) b.id: b.title};
  final themesOf = <String, List<String>>{};
  for (final t in graph?.themes ?? <StoryTheme>[]) {
    for (final id in t.eventIds) {
      themesOf.putIfAbsent(id, () => []).add(t.name);
    }
  }
  final iso = DateFormat("yyyy-MM-dd'T'HH:mm:ss");
  final day = DateFormat('yyyy-MM-dd');
  final weekday = DateFormat('E', 'en_US');
  String list(Iterable<String> items) => items.isEmpty
      ? 'none'
      : items.map((s) => s.replaceAll('|', '/')).join('|');
  String text(String? value, String missing) =>
      value == null || value.trim().isEmpty ? missing : value;

  final labels = labelColumns(events);
  return encodeCsv([
    [for (final c in analysisColumns) c.name, for (final l in labels) _labelTitle(l)],
    for (final e in _ordered(events))
      () {
        final chapter = chapterOf[e.id];
        final ring = ringColorFor(graph?.rings[e.id]);
        final w = e.weather;
        return <Object?>[
          e.id,
          iso.format(e.occurredAt),
          day.format(e.occurredAt),
          e.occurredAt.year,
          e.occurredAt.month,
          weekday.format(e.occurredAt),
          e.occurredAt.hour,
          text(e.title, 'untitled'),
          text(e.location, 'unknown'),
          e.hasCoordinates ? 1 : 0,
          e.latitude ?? unknownNumber,
          e.longitude ?? unknownNumber,
          e.hasAccount ? 1 : 0,
          e.images.length,
          _words(e.notes),
          _words(e.description),
          e.people.length,
          e.places.length,
          e.tags.length,
          list(e.people),
          list(e.places),
          list(e.tags),
          text(chapter?.title, 'none'),
          text(
            chapter?.bookId == null ? null : bookTitle[chapter!.bookId],
            'none',
          ),
          list(themesOf[e.id] ?? const []),
          ring == null
              ? 'none'
              : '#${(ring & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
          w == null ? 0 : 1,
          text(w?.condition, 'not looked up'),
          w?.temperatureC ?? unknownNumber,
          w?.precipitationMm ?? unknownNumber,
          w?.windKmh ?? unknownNumber,
          iso.format(e.createdAt),
          _words(e.experience),
          for (final l in labels) e.experienceLabels.contains(l) ? 1 : 0,
        ];
      }(),
  ]);
}

/// Plain-text data dictionary that travels with the analysis file.
String analysisDictionary() {
  final b = StringBuffer(
    'EventLens analysis file: column guide\n'
    '=====================================\n\n'
    'File: eventlens-analysis.csv (UTF-8, comma-separated, one row per '
    'event,\noldest first). Lists use | between items. No cell is ever '
    'blank: unknown\ntext is a word ("unknown", "none", "not looked up") '
    'and unknown numbers are\n$unknownNumber. Use has_location and '
    'has_weather to keep only rows with real\nvalues, for example '
    "df[df['has_weather'] == 1].\n\n",
  );
  for (final c in analysisColumns) {
    b.writeln('${c.name.padRight(18)} ${c.type.padRight(9)} ${c.meaning}');
  }
  b.writeln(
    '\nAfter these columns comes one column per free-write label. Its title '
    'is the label\nitself (for example "calm"): 1 if the AI labelled that '
    "event's free write with\nit, 0 if not. The AI makes the labels from "
    'your free write and checks each one\nagainst it. These columns never '
    'have blanks.',
  );
  b.writeln(
    '\nFor fun, not professional analysis. Python knowledge is '
    'recommended.\nLearn more about notebooks and data science at '
    'https://jupyter.org\n',
  );
  return b.toString();
}
