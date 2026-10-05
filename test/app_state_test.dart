import 'dart:convert';
import 'dart:io';

import 'package:eventlens/ai/anthropic_ai_client.dart';
import 'package:eventlens/ai/event_describer.dart';
import 'package:eventlens/ai/graph_builder.dart';
import 'package:eventlens/data/app_database.dart';
import 'package:eventlens/data/event_repository.dart';
import 'package:eventlens/data/graph_repository.dart';
import 'package:eventlens/data/image_vault.dart';
import 'package:eventlens/data/memory_repository.dart';
import 'package:eventlens/models/event.dart';
import 'package:eventlens/models/memory_graph.dart';
import 'package:eventlens/models/ring_palette.dart';
import 'package:eventlens/services/settings_service.dart';
import 'package:eventlens/state/app_state.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory tmp;
  late AppState state;
  late List<Map<String, dynamic>> sentBodies;
  late List<Map<String, dynamic>> graphBodies;

  // What the mocked AI returns for the first build and for later updates.
  var graphBuild = <String, dynamic>{};
  var graphUpdate = <String, dynamic>{};
  var graphStatus = 200;

  Future<AppState> build({required String? apiKey}) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues(
      apiKey == null ? {} : {'anthropic_api_key': apiKey},
    );
    final db = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: '${tmp.path}/test.db',
    );
    final settings = SettingsService(
      const FlutterSecureStorage(),
      await SharedPreferences.getInstance(),
    );
    final s = AppState(
      events: EventRepository(db),
      memoryRepo: MemoryRepository(db),
      graphRepo: GraphRepository(db),
      vault: ImageVault(Directory('${tmp.path}/vault')),
      settings: settings,
      describerFactory: (key, model, effort) => EventDescriber(
        model: model,
        effort: effort,
        client: AnthropicAIClient(
          apiKey: key,
          httpClient: MockClient((request) async {
            sentBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
            return http.Response(
              jsonEncode({
                'model': model,
                'stop_reason': 'end_turn',
                'content': [
                  {
                    'type': 'text',
                    'text': jsonEncode({
                      'title': 'Lake evening',
                      'summary': 'Sam and I watched the sunset.',
                      'description': 'The sky turned orange over the lake.',
                      'people': ['Sam'],
                      'places': ['Lake'],
                      'tags': ['sunset'],
                      'memory_suggestions': [
                        {'kind': 'place', 'content': 'The lake is our spot'},
                      ],
                    }),
                  },
                ],
              }),
              200,
            );
          }),
        ),
      ),
      graphBuilderFactory: (key, model, effort) => GraphBuilder(
        model: model,
        effort: effort,
        client: AnthropicAIClient(
          apiKey: key,
          httpClient: MockClient((request) async {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            graphBodies.add(body);
            final isUpdate =
                (body['output_config']['format']['schema']['required'] as List)
                    .contains('placements');
            return http.Response(
              jsonEncode({
                'model': model,
                'stop_reason': 'end_turn',
                'content': [
                  {
                    'type': 'text',
                    'text': jsonEncode(isUpdate ? graphUpdate : graphBuild),
                  },
                ],
              }),
              graphStatus,
            );
          }),
        ),
      ),
    );
    await s.load();
    return s;
  }

  File photo() {
    final file = File('${tmp.path}/photo.png');
    file.writeAsBytesSync(img.encodePng(img.Image(width: 3000, height: 2000)));
    return file;
  }

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('eventlens_test');
    sentBodies = [];
    graphBodies = [];
    graphStatus = 200;
    graphBuild = {
      'overview': 'A summer of evenings at the lake.',
      'chapters': [
        {
          'title': 'Lake summer',
          'summary': 'Evenings by the water.',
          'event_refs': ['E1', 'E2', 'E3'],
        },
      ],
      'links': [
        {'from': 'E1', 'to': 'E3', 'relation': 'same lake'},
      ],
      'themes': [
        {
          'name': 'Time with Sam',
          'description': 'Evenings with my brother.',
          'event_refs': ['E1', 'E2'],
        },
      ],
    };
    graphUpdate = {
      'overview': 'A summer of evenings at the lake, then a trip away.',
      'placements': [
        {
          'event': 'N1',
          'chapter': 'NEW',
          'new_chapter_title': 'Road trip',
          'new_chapter_summary': 'Leaving the lake behind.',
        },
      ],
      'links': [
        {'from': 'N1', 'to': 'E1', 'relation': 'missed the lake'},
      ],
      'themes': [
        {
          'name': 'Time with Sam',
          'description': '',
          'event_refs': ['N1'],
        },
      ],
    };
  });

  tearDown(() => tmp.delete(recursive: true));

  test('create, describe, then remember a suggestion', () async {
    state = await build(apiKey: 'sk-ant-test');
    final event = await state.createEvent(
      title: '',
      notes: 'Sam and I at the lake after work',
      location: '',
      occurredAt: DateTime(2026, 7, 4, 19),
      photos: [photo()],
    );
    expect(state.allEvents, hasLength(1));
    expect(
      state.vault.fileFor(event.images.single.fileName).existsSync(),
      isTrue,
    );

    await state.describeEvent(event.id);

    final described = state.eventById(event.id)!;
    expect(described.status, EventStatus.described);
    expect(described.title, 'Lake evening');
    expect(described.description, contains('orange'));
    expect(described.suggestions.single.content, 'The lake is our spot');

    // The photo was downscaled to the AI limit before upload.
    final imageBlock = (sentBodies.single['messages'][0]['content'] as List)
        .firstWhere((b) => b['type'] == 'image');
    final sent = img.decodeJpg(base64Decode(imageBlock['source']['data']))!;
    expect(sent.width, ImageVault.aiMaxEdge);

    await state.acceptSuggestion(described, described.suggestions.single);
    expect(state.memories.single.content, 'The lake is our spot');
    expect(state.memories.single.source, 'ai');
    expect(state.eventById(event.id)!.suggestions, isEmpty);

    // A second event now carries the memory and the earlier summary.
    final second = await state.createEvent(
      title: 'Back again',
      notes: 'Same spot',
      location: '',
      occurredAt: DateTime(2026, 7, 5, 19),
      photos: const [],
    );
    await state.describeEvent(second.id);
    final body = sentBodies.last;
    expect(
      (body['system'] as List).last['text'],
      contains('The lake is our spot'),
    );
    expect(
      (body['messages'][0]['content'] as List).last['text'],
      contains('Sam and I watched the sunset.'),
    );
    // Known memories are not suggested again.
    expect(state.eventById(second.id)!.suggestions, isEmpty);
  });

  test('describe without an API key fails with guidance', () async {
    state = await build(apiKey: null);
    final event = await state.createEvent(
      title: 't',
      notes: 'n',
      location: '',
      occurredAt: DateTime(2026),
      photos: const [],
    );
    await state.describeEvent(event.id);
    final failed = state.eventById(event.id)!;
    expect(failed.status, EventStatus.failed);
    expect(failed.error, contains('API key'));
    expect(sentBodies, isEmpty);
  });

  test('deleting an event removes its photos from the vault', () async {
    state = await build(apiKey: 'sk-ant-test');
    final event = await state.createEvent(
      title: 't',
      notes: '',
      location: '',
      occurredAt: DateTime(2026),
      photos: [photo()],
    );
    final file = state.vault.fileFor(event.images.single.fileName);
    await state.deleteEvent(state.eventById(event.id)!);
    expect(state.allEvents, isEmpty);
    expect(file.existsSync(), isFalse);
  });

  /// Creates and describes an event with [photoCount] small photos.
  Future<LifeEvent> describedEvent(
    AppState s,
    int day, {
    int photoCount = 0,
  }) async {
    final photos = [
      for (var i = 0; i < photoCount; i++)
        File('${tmp.path}/p$day-$i.png')
          ..writeAsBytesSync(img.encodePng(img.Image(width: 8, height: 8))),
    ];
    final e = await s.createEvent(
      title: '',
      notes: 'Evening $day at the lake with Sam',
      location: '',
      occurredAt: DateTime(2026, 7, day, 19),
      photos: photos,
    );
    await s.describeEvent(e.id);
    return s.eventById(e.id)!;
  }

  test('the first 10 described photos unlock the graph, once', () async {
    state = await build(apiKey: 'sk-ant-test');
    expect(state.graphUnlocked, isFalse);
    final first = await describedEvent(state, 1, photoCount: 4);
    await describedEvent(state, 2, photoCount: 4);
    expect(graphBodies, isEmpty);
    expect(state.photosUntilUnlock, 2);

    final third = await describedEvent(state, 3, photoCount: 2);
    expect(graphBodies, hasLength(1));
    expect(state.graphUnlocked, isTrue);
    expect(state.photosUntilUnlock, 0);
    final journal = graphBodies.single['messages'][0]['content'] as String;
    expect(journal, contains('E1 |'));
    expect(journal, contains('User notes: Evening 1 at the lake with Sam'));

    final graph = state.graphSnapshot!;
    expect(graph.chapters.single.eventIds, hasLength(3));
    expect(graph.links.single.fromEventId, first.id);
    expect(graph.links.single.toEventId, third.id);
    expect(state.eventsAwaitingGraph, 0);
    // Rings are the user's: none until they add one.
    expect(state.graph.nodes.where((n) => n.ringColor != null), isEmpty);
    final reopened = await build(apiKey: 'sk-ant-test');
    expect(reopened.graphUnlocked, isTrue);
  });

  test(
    'after unlocking, the AI builds on the graph without rewriting it',
    () async {
      state = await build(apiKey: 'sk-ant-test');
      for (var day = 1; day <= 3; day++) {
        await describedEvent(state, day, photoCount: 4);
      }
      final before = state.graphSnapshot!;
      expect(graphBodies, hasLength(1));

      final trip = await describedEvent(state, 10);
      expect(graphBodies, hasLength(2));
      final update = graphBodies.last;
      expect(
        (update['output_config']['format']['schema']['required'] as List),
        contains('placements'),
      );
      final text = update['messages'][0]['content'] as String;
      expect(text, contains('C1 | Lake summer'));
      expect(text, contains('N1 |'));

      final after = state.graphSnapshot!;
      // Earlier AI work is untouched…
      expect(after.chapters.first.title, before.chapters.first.title);
      expect(after.chapters.first.summary, before.chapters.first.summary);
      expect(after.chapters.first.eventIds, before.chapters.first.eventIds);
      expect(after.links.first.relation, 'same lake');
      // …and the new event is built on top.
      expect(after.chapters.last.title, 'Road trip');
      expect(after.chapters.last.eventIds, [trip.id]);
      expect(after.links.last.fromEventId, trip.id);
      expect(after.themes.single.eventIds, contains(trip.id));
      expect(after.overview, contains('trip away'));
      expect(state.eventsAwaitingGraph, 0);

      // Nothing new: no AI call.
      await state.advanceGraph();
      expect(graphBodies, hasLength(2));
    },
  );

  test('an incomplete AI update still places every new event', () async {
    state = await build(apiKey: 'sk-ant-test');
    for (var day = 1; day <= 3; day++) {
      await describedEvent(state, day, photoCount: 4);
    }
    graphUpdate = {'overview': '', 'placements': [], 'links': [], 'themes': []};
    final late = await describedEvent(state, 10);
    expect(state.eventsAwaitingGraph, 0);
    expect(state.graphSnapshot!.chapters.last.eventIds, contains(late.id));
    expect(state.graphSnapshot!.overview, 'A summer of evenings at the lake.');
  });

  test('a failed update stays pending and Retry adds it', () async {
    state = await build(apiKey: 'sk-ant-test');
    for (var day = 1; day <= 3; day++) {
      await describedEvent(state, day, photoCount: 4);
    }
    graphStatus = 400;
    await describedEvent(state, 10);
    expect(state.graphError, isNotNull);
    expect(state.eventsAwaitingGraph, 1);
    expect(state.graphSnapshot!.chapters, hasLength(1));

    graphStatus = 200;
    await state.advanceGraph();
    expect(state.graphError, isNull);
    expect(state.eventsAwaitingGraph, 0);
    expect(state.graphSnapshot!.chapters.last.title, 'Road trip');
  });

  test('the user layer changes only books, placement and rings', () async {
    state = await build(apiKey: 'sk-ant-test');
    final a = await describedEvent(state, 1, photoCount: 5);
    await describedEvent(state, 2, photoCount: 5);
    final before = state.graphSnapshot!;
    final chapter = before.chapters.single;

    const book = Book(id: 'b1', title: 'Summer 2026');
    await state.updateUserLayer(
      books: const [
        book,
        Book(id: 'b2', title: '  '),
      ],
      chapterBooks: {chapter.id: 'b1', 'not-a-chapter': 'b1'},
      rings: {a.id: 2, 'deleted-event': 1, 'x': 99},
    );
    final after = state.graphSnapshot!;
    expect(after.books.map((b) => b.title), ['Summer 2026', untitledBookTitle]);
    expect(after.chapters.single.bookId, 'b1');
    expect(after.rings, {a.id: 2});
    expect(state.graph.node('event:${a.id}')!.ringColor, ringPalette[2]);
    // The AI's content is exactly as it was.
    expect(after.overview, before.overview);
    expect(after.chapters.single.title, chapter.title);
    expect(after.chapters.single.eventIds, chapter.eventIds);
    expect(after.links.length, before.links.length);
    expect(after.themes.single.name, before.themes.single.name);

    // Books and rings survive the AI building on the graph.
    await describedEvent(state, 9);
    final grown = state.graphSnapshot!;
    expect(grown.chapters.first.bookId, 'b1');
    expect(grown.rings, {a.id: 2});
    expect(grown.books.first.title, 'Summer 2026');

    // Deleting an event drops its ring and keeps everything consistent.
    await state.deleteEvent(state.eventById(a.id)!);
    await state.updateUserLayer(
      books: grown.books,
      chapterBooks: const {},
      rings: grown.rings,
    );
    expect(state.graphSnapshot!.rings, isEmpty);
    expect(state.graphSnapshot!.chapters.first.eventIds, isNot(contains(a.id)));
  });
}
