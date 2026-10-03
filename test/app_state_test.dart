import 'dart:convert';
import 'dart:io';

import 'package:eventlens/ai/anthropic_client.dart';
import 'package:eventlens/ai/event_describer.dart';
import 'package:eventlens/ai/graph_builder.dart';
import 'package:eventlens/data/app_database.dart';
import 'package:eventlens/data/event_repository.dart';
import 'package:eventlens/data/graph_repository.dart';
import 'package:eventlens/data/image_vault.dart';
import 'package:eventlens/data/memory_repository.dart';
import 'package:eventlens/models/event.dart';
import 'package:eventlens/models/memory_graph.dart';
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

  Future<AppState> build({required String? apiKey, int? graphEvery}) async {
    SharedPreferences.setMockInitialValues(
      graphEvery == null ? {} : {'graph_every_photos': graphEvery},
    );
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
        client: AnthropicClient(
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
        client: AnthropicClient(
          apiKey: key,
          httpClient: MockClient((request) async {
            graphBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
            return http.Response(
              jsonEncode({
                'model': model,
                'stop_reason': 'end_turn',
                'content': [
                  {
                    'type': 'text',
                    'text': jsonEncode({
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
                    }),
                  },
                ],
              }),
              200,
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

  test('AI rebuilds the timeline after 10 newly described photos', () async {
    state = await build(apiKey: 'sk-ant-test');
    expect(state.graphEvery, 10);
    final first = await describedEvent(state, 1, photoCount: 4);
    await describedEvent(state, 2, photoCount: 4);
    expect(graphBodies, isEmpty);
    expect(state.photosUntilNextGraph, 2);

    final third = await describedEvent(state, 3, photoCount: 2);
    expect(graphBodies, hasLength(1));
    final journal = graphBodies.single['messages'][0]['content'] as String;
    expect(journal, contains('E1 |'));
    expect(journal, contains('E3 |'));
    expect(journal, contains('User notes: Evening 1 at the lake with Sam'));

    final snapshot = state.graphSnapshot!;
    expect(snapshot.eventCount, 3);
    expect(snapshot.photoCount, 10);
    expect(snapshot.chapters.single.eventIds, hasLength(3));
    expect(snapshot.links.single.fromEventId, first.id);
    expect(snapshot.links.single.toEventId, third.id);
    expect(state.photosUntilNextGraph, 10);

    final graph = state.graph;
    expect(graph.nodes.where((n) => n.kind == NodeKind.event), hasLength(3));
    expect(graph.node('theme:time with sam'), isNotNull);
    expect(graph.edges.where((e) => e.kind == EdgeKind.aiLink), hasLength(1));
    // No automatic rings: nothing is coloured until the user picks colours.
    expect(graph.nodes.where((n) => n.ringColor != null), isEmpty);

    // Photo-less events don't count towards the next rebuild.
    await describedEvent(state, 4);
    expect(graphBodies, hasLength(1));
    expect(state.photosUntilNextGraph, 10);
    final reopened = await build(apiKey: 'sk-ant-test');
    expect(reopened.graphSnapshot!.id, snapshot.id);
  });

  test('automatic rebuilds can be turned off', () async {
    state = await build(apiKey: 'sk-ant-test', graphEvery: 0);
    for (var day = 1; day <= 3; day++) {
      await describedEvent(state, day, photoCount: 5);
    }
    expect(graphBodies, isEmpty);
    expect(state.photosUntilNextGraph, isNull);

    await state.buildGraphNow();
    expect(graphBodies, hasLength(1));
    expect(state.graphSnapshot, isNotNull);
  });

  test('manual AI build needs two described events', () async {
    state = await build(apiKey: 'sk-ant-test');
    await describedEvent(state, 1);
    await state.buildGraphNow();
    expect(graphBodies, isEmpty);
    expect(state.graphError, contains('two events'));
  });

  test('hand edits are saved, repaired, and survive an AI rebuild', () async {
    state = await build(apiKey: 'sk-ant-test', graphEvery: 0);
    final a = await describedEvent(state, 1);
    final b = await describedEvent(state, 2);
    final c = await describedEvent(state, 3);
    await state.buildGraphNow();
    final built = state.graphSnapshot!;

    const group = ChapterGroup(id: 'g1', name: 'Summer 2026');
    await state.saveGraph(
      built.copyWith(
        overview: 'My own summary of the summer.',
        overviewEdited: true,
        groups: const [group],
        chapters: [
          built.chapters.single.copyWith(
            title: 'Lake evenings',
            edited: true,
            color: chapterColors[3],
            groupId: 'g1',
          ),
          // Invalid bits the editor could produce; saving must repair them.
          const TimelineChapter(
            id: '',
            title: '   ',
            summary: '',
            eventIds: ['deleted-event'],
            color: 0x12345678,
            groupId: 'missing-group',
          ),
        ],
        links: [
          ...built.links,
          EventLink(
            fromEventId: a.id,
            toEventId: b.id,
            relation: 'next day',
            manual: true,
          ),
          EventLink(
            fromEventId: c.id,
            toEventId: c.id,
            relation: 'self',
            manual: true,
          ),
        ],
        themes: [
          ...built.themes,
          StoryTheme(
            name: 'Swims',
            description: '',
            eventIds: [a.id, c.id],
            manual: true,
          ),
        ],
      ),
    );

    var saved = state.graphSnapshot!;
    expect(saved.chapters, hasLength(2));
    final repaired = saved.chapters[1];
    expect(repaired.title, 'Untitled chapter');
    expect(repaired.id, isNotEmpty);
    expect(repaired.eventIds, isEmpty);
    expect(repaired.color, isNull);
    expect(repaired.groupId, isNull);
    expect(saved.links.where((l) => l.fromEventId == l.toEventId), isEmpty);
    // The user's colour rings the chapter's events in the graph.
    expect(state.graph.node('event:${a.id}')!.ringColor, chapterColors[3]);

    // The AI rebuild keeps the user's group, colour, wording and additions.
    await state.buildGraphNow();
    saved = state.graphSnapshot!;
    expect(graphBodies, hasLength(2));
    expect(saved.groups.single.name, 'Summer 2026');
    expect(saved.overview, 'My own summary of the summer.');
    final lake = saved.chapters.single;
    expect(lake.title, 'Lake evenings');
    expect(lake.color, chapterColors[3]);
    expect(lake.groupId, 'g1');
    expect(saved.links.where((l) => l.manual).single.relation, 'next day');
    expect(
      saved.themes.map((t) => t.name),
      containsAll(['Time with Sam', 'Swims']),
    );

    // Deleting an event leaves the saved timeline consistent.
    await state.deleteEvent(state.eventById(a.id)!);
    await state.saveGraph(state.graphSnapshot!);
    saved = state.graphSnapshot!;
    expect(saved.chapters.single.eventIds, isNot(contains(a.id)));
    expect(saved.links.where((l) => l.fromEventId == a.id), isEmpty);
    expect(state.graph.nodes, isNotEmpty);
  });
}
