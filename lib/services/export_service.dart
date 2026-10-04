import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../data/image_vault.dart';
import '../models/event.dart';
import '../models/memory_graph.dart';
import '../models/memory_item.dart';
import '../models/ring_palette.dart';
import 'data_files.dart';

/// Builds a zip of the whole library:
///
/// * `EventLens/data.json`: everything, for re-import or other tools.
/// * `EventLens/eventlens-basic.csv` and `eventlens-analysis.csv` (with its
///   column guide), the same files offered on their own in Your data.
/// * `EventLens/Vault/`: an Obsidian-compatible vault. One note per event,
///   with [[links]] to notes for each person, place, tag, chapter, book and
///   theme, so the vault's graph view mirrors the app's graph. Photos sit in
///   `attachments/` and are embedded in their event's note.
class LibraryExporter {
  final ImageVault vault;

  LibraryExporter(this.vault);

  static const _root = 'EventLens';
  static const _vaultDir = '$_root/Vault';

  /// File-name-safe version of [name] (Obsidian links use the file name).
  static String safeName(String name) {
    final cleaned = name
        .replaceAll(RegExp(r'[\\/:*?"<>|#^\[\]]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.isEmpty ? 'Untitled' : cleaned;
  }

  static String _yamlString(String s) => jsonEncode(s);

  Future<Archive> build({
    required List<LifeEvent> events,
    required List<MemoryItem> memories,
    GraphSnapshot? graph,
    DateTime? exportedAt,
  }) async {
    final archive = Archive();
    final when = exportedAt ?? DateTime.now();
    final day = DateFormat('yyyy-MM-dd');
    final ordered = [...events]
      ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));

    // Unique note names for events (two events can share a title and day).
    final eventNote = <String, String>{};
    final used = <String>{};
    for (final e in ordered) {
      final base = safeName(
        '${day.format(e.occurredAt)} ${e.title.isEmpty ? 'Untitled' : e.title}',
      );
      var name = base;
      for (var n = 2; used.contains(name.toLowerCase()); n++) {
        name = '$base ($n)';
      }
      used.add(name.toLowerCase());
      eventNote[e.id] = name;
    }

    // Note names per folder. Names are compared ignoring case, because
    // "Sam.md" and "sam.md" are the same file on Windows, macOS and
    // Android storage. People, places, tags and themes with the same name
    // share a note; chapters and books are separate even with equal titles.
    final taken = <String, Set<String>>{};
    String unique(String folder, String name) {
      final used = taken.putIfAbsent(folder, () => <String>{});
      final base = safeName(name);
      var candidate = base;
      for (var n = 2; used.contains(candidate.toLowerCase()); n++) {
        candidate = '$base ($n)';
      }
      used.add(candidate.toLowerCase());
      return candidate;
    }

    final sharedNames = <String, String>{};
    String named(String folder, String name) => sharedNames.putIfAbsent(
      '$folder/${safeName(name).toLowerCase()}',
      () => unique(folder, name),
    );

    final chapterNote = {
      for (final c in graph?.chapters ?? <TimelineChapter>[])
        c.id: unique('Chapters', c.title),
    };
    final bookNote = {
      for (final b in graph?.books ?? <Book>[]) b.id: unique('Books', b.title),
    };

    // Backlinks: note path -> events that link to it.
    final backlinks = <String, Set<String>>{};
    void link(String path, String eventId) =>
        backlinks.putIfAbsent(path, () => <String>{}).add(eventId);

    final chapterOf = <String, TimelineChapter>{};
    for (final c in graph?.chapters ?? <TimelineChapter>[]) {
      for (final id in c.eventIds) {
        chapterOf[id] = c;
      }
    }

    for (final e in ordered) {
      final note = StringBuffer('---\n')
        ..writeln('date: ${e.occurredAt.toIso8601String()}')
        ..writeln('title: ${_yamlString(e.title)}');
      if (e.location.isNotEmpty) {
        note.writeln('location: ${_yamlString(e.location)}');
      }
      if (e.hasCoordinates) {
        note.writeln('coordinates: [${e.latitude}, ${e.longitude}]');
      }
      if (e.tags.isNotEmpty) {
        note.writeln('tags: [${e.tags.map((t) => _yamlString(t)).join(', ')}]');
      }
      final ring = ringColorFor(graph?.rings[e.id]);
      if (ring != null) {
        note.writeln(
          'ring: "#${(ring & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}"',
        );
      }
      final w = e.weather;
      if (w != null) {
        note.writeln(
          'weather: ${_yamlString('${w.condition}, ${w.temperatureC.round()}°C')}',
        );
      }
      note.writeln('---\n\n# ${e.title.isEmpty ? 'Untitled event' : e.title}\n');

      final chapter = chapterOf[e.id];
      final chapterPath = chapter == null
          ? null
          : 'Chapters/${chapterNote[chapter.id]}';
      final bookPath = chapter?.bookId == null || bookNote[chapter!.bookId] == null
          ? null
          : 'Books/${bookNote[chapter.bookId]}';
      final links = <String>[
        if (chapterPath != null) '[[$chapterPath]]',
        if (bookPath != null) '[[$bookPath]]',
        for (final person in e.people) '[[People/${named('People', person)}]]',
        for (final place in e.places) '[[Places/${named('Places', place)}]]',
      ];
      if (links.isNotEmpty) note.writeln('${links.join(' · ')}\n');
      if (e.description.isNotEmpty) note.writeln('${e.description}\n');
      if (e.notes.isNotEmpty) {
        note.writeln('## My notes at the time\n\n${e.notes}\n');
      }
      if (e.experience.trim().isNotEmpty) {
        note.writeln('## My free write\n\n${e.experience.trim()}\n');
      }
      for (final image in e.images) {
        final file = vault.fileFor(image.fileName);
        if (await file.exists()) {
          // Streamed from disk when the zip is written, so a large library
          // never has to fit in memory. JPEGs are already compressed.
          archive.addFile(
            ArchiveFile.stream(
              '$_vaultDir/attachments/${image.fileName}',
              InputFileStream(file.path),
            )..compression = CompressionType.none,
          );
          note.writeln('![[${image.fileName}]]');
        }
      }
      archive.addFile(
        ArchiveFile.string(
          '$_vaultDir/Events/${eventNote[e.id]}.md',
          note.toString(),
        ),
      );

      if (chapterPath != null) link(chapterPath, e.id);
      if (bookPath != null) link(bookPath, e.id);
      for (final person in e.people) {
        link('People/${named('People', person)}', e.id);
      }
      for (final place in e.places) {
        link('Places/${named('Places', place)}', e.id);
      }
      for (final tag in e.tags) {
        link('Tags/${named('Tags', tag)}', e.id);
      }
    }
    for (final t in graph?.themes ?? <StoryTheme>[]) {
      for (final id in t.eventIds) {
        if (eventNote.containsKey(id)) {
          link('Themes/${named('Themes', t.name)}', id);
        }
      }
    }

    final descriptions = <String, String>{
      for (final c in graph?.chapters ?? <TimelineChapter>[])
        'Chapters/${chapterNote[c.id]}': c.summary,
      for (final t in graph?.themes ?? <StoryTheme>[])
        'Themes/${named('Themes', t.name)}': t.description,
    };
    for (final entry in backlinks.entries) {
      final title = entry.key.split('/').last;
      final buffer = StringBuffer('# $title\n\n');
      final about = descriptions[entry.key];
      if (about != null && about.isNotEmpty) buffer.writeln('$about\n');
      for (final id in ordered.map((e) => e.id).where(entry.value.contains)) {
        buffer.writeln('- [[Events/${eventNote[id]}]]');
      }
      archive.addFile(
        ArchiveFile.string('$_vaultDir/${entry.key}.md', buffer.toString()),
      );
    }

    final overview = StringBuffer('# EventLens library\n\n')
      ..writeln('Exported ${DateFormat.yMMMMd().add_jm().format(when)}.\n');
    if (graph != null && graph.overview.isNotEmpty) {
      overview.writeln('${graph.overview}\n');
    }
    if (memories.isNotEmpty) {
      overview.writeln('## Memories\n');
      for (final m in memories) {
        overview.writeln('- ${m.content}');
      }
    }
    archive.addFile(
      ArchiveFile.string('$_vaultDir/EventLens.md', overview.toString()),
    );

    archive.addFile(
      ArchiveFile.string(
        '$_root/data.json',
        const JsonEncoder.withIndent('  ').convert({
          'format': 'eventlens-export',
          'version': 1,
          'exported_at': when.toIso8601String(),
          'events': [
            for (final e in ordered)
              {
                ...e.toRow(),
                'images': [for (final i in e.images) i.toRow()],
              },
          ],
          'memories': [for (final m in memories) m.toRow()],
          'graph': graph == null
              ? null
              : jsonDecode(graph.toRow()['data'] as String),
        }),
      ),
    );
    archive.addFile(
      ArchiveFile.string('$_root/$basicCsvName', withBom(basicCsv(ordered))),
    );
    archive.addFile(
      ArchiveFile.string(
        '$_root/$analysisCsvName',
        analysisCsv(ordered, graph),
      ),
    );
    archive.addFile(
      ArchiveFile.string('$_root/$dictionaryName', analysisDictionary()),
    );
    archive.addFile(
      ArchiveFile.string(
        '$_root/README.txt',
        'EventLens export\n\n'
        'Vault/ opens in Obsidian (Open folder as vault). Its graph view\n'
        'shows events linked to their people, places, tags, chapters,\n'
        'books and themes. data.json holds everything in one file.\n'
        '$basicCsvName opens in any spreadsheet app.\n'
        '$analysisCsvName loads into Python tools such as pandas in a\n'
        'Jupyter notebook; $dictionaryName explains each column.\n',
      ),
    );
    return archive;
  }

  static const basicCsvName = 'eventlens-basic.csv';
  static const analysisCsvName = 'eventlens-analysis.csv';
  static const dictionaryName = 'eventlens-analysis-columns.txt';

  /// Writes a single text file (a CSV) to [directory] and returns it.
  Future<File> writeText(String text, Directory directory, String name) async {
    final file = File(p.join(directory.path, name));
    await file.writeAsString(text, flush: true);
    return file;
  }

  /// Writes the zip to [directory] and returns the file.
  Future<File> writeZip(
    Archive archive,
    Directory directory, {
    DateTime? exportedAt,
  }) async {
    final stamp = DateFormat('yyyy-MM-dd_HHmm').format(exportedAt ?? DateTime.now());
    final file = File(p.join(directory.path, 'EventLens-export-$stamp.zip'));
    final output = OutputFileStream(file.path);
    try {
      ZipEncoder().encodeStream(archive, output, autoClose: true);
    } finally {
      await output.close();
      await archive.clear();
    }
    return file;
  }

  /// Builds and writes the full export on a background isolate, so the
  /// screen stays responsive however large the library is.
  Future<File> exportZip({
    required List<LifeEvent> events,
    required List<MemoryItem> memories,
    required GraphSnapshot? graph,
    required Directory directory,
  }) {
    final exporter = LibraryExporter(vault);
    return Isolate.run(() async {
      final archive = await exporter.build(
        events: events,
        memories: memories,
        graph: graph,
      );
      final file = await exporter.writeZip(archive, directory);
      return file.path;
    }).then(File.new);
  }
}
