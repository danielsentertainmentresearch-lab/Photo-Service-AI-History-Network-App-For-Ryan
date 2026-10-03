import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../data/image_vault.dart';
import '../models/event.dart';
import '../models/memory_graph.dart';
import '../models/memory_item.dart';
import '../models/ring_palette.dart';

/// Builds a zip of the whole library:
///
/// * `EventLens/data.json`: everything, for re-import or other tools.
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

    // Backlinks for the people/place/tag/chapter/book/theme notes.
    final backlinks = <String, Set<String>>{};
    void link(String folder, String name, String eventId) => backlinks
        .putIfAbsent('$folder/${safeName(name)}', () => <String>{})
        .add(eventId);

    final chapterOf = <String, TimelineChapter>{};
    final bookTitle = {for (final b in graph?.books ?? <Book>[]) b.id: b.title};
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
      final links = <String>[
        if (chapter != null) '[[Chapters/${safeName(chapter.title)}]]',
        if (chapter?.bookId != null && bookTitle[chapter!.bookId] != null)
          '[[Books/${safeName(bookTitle[chapter.bookId]!)}]]',
        for (final person in e.people) '[[People/${safeName(person)}]]',
        for (final place in e.places) '[[Places/${safeName(place)}]]',
      ];
      if (links.isNotEmpty) note.writeln('${links.join(' · ')}\n');
      if (e.description.isNotEmpty) note.writeln('${e.description}\n');
      if (e.notes.isNotEmpty) {
        note.writeln('## My notes at the time\n\n${e.notes}\n');
      }
      for (final image in e.images) {
        final file = vault.fileFor(image.fileName);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          archive.addFile(
            ArchiveFile.bytes('$_vaultDir/attachments/${image.fileName}', bytes),
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

      if (chapter != null) link('Chapters', chapter.title, e.id);
      if (chapter?.bookId != null && bookTitle[chapter!.bookId] != null) {
        link('Books', bookTitle[chapter.bookId]!, e.id);
      }
      for (final person in e.people) {
        link('People', person, e.id);
      }
      for (final place in e.places) {
        link('Places', place, e.id);
      }
      for (final tag in e.tags) {
        link('Tags', tag, e.id);
      }
    }
    for (final t in graph?.themes ?? <StoryTheme>[]) {
      for (final id in t.eventIds) {
        if (eventNote.containsKey(id)) link('Themes', t.name, id);
      }
    }

    final descriptions = <String, String>{
      for (final c in graph?.chapters ?? <TimelineChapter>[])
        'Chapters/${safeName(c.title)}': c.summary,
      for (final t in graph?.themes ?? <StoryTheme>[])
        'Themes/${safeName(t.name)}': t.description,
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
      ArchiveFile.string(
        '$_root/README.txt',
        'EventLens export\n\n'
        'Vault/ opens in Obsidian (Open folder as vault). Its graph view\n'
        'shows events linked to their people, places, tags, chapters,\n'
        'books and themes. data.json holds everything in one file.\n',
      ),
    );
    return archive;
  }

  /// Writes the zip to [directory] and returns the file.
  Future<File> writeZip(
    Archive archive,
    Directory directory, {
    DateTime? exportedAt,
  }) async {
    final stamp = DateFormat('yyyy-MM-dd_HHmm').format(exportedAt ?? DateTime.now());
    final file = File(p.join(directory.path, 'EventLens-export-$stamp.zip'));
    await file.writeAsBytes(ZipEncoder().encode(archive));
    return file;
  }
}
