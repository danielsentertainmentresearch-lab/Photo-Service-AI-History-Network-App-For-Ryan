import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:eventlens/ai/anthropic_ai_client.dart';
import 'package:eventlens/ai/event_describer.dart';
import 'package:eventlens/data/app_database.dart';
import 'package:eventlens/data/event_repository.dart';
import 'package:eventlens/data/graph_repository.dart';
import 'package:eventlens/data/image_vault.dart';
import 'package:eventlens/data/memory_repository.dart';
import 'package:eventlens/models/event.dart';
import 'package:eventlens/models/memory_graph.dart';
import 'package:eventlens/services/export_service.dart';
import 'package:eventlens/services/photo_metadata.dart';
import 'package:eventlens/services/places_service.dart';
import 'package:eventlens/services/rewards_service.dart';
import 'package:eventlens/services/settings_service.dart';
import 'package:eventlens/state/app_state.dart';
import 'package:eventlens/state/library_scope.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
// ignore: implementation_imports
import 'package:image/src/util/rational.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Videos implements RewardedVideoProvider {
  bool finish = true;
  int shown = 0;

  @override
  Future<bool> showRewardedVideo() async {
    shown++;
    return finish;
  }
}

/// Fake Open-Meteo / Nominatim server.
MockClient fakePlaces({List<Uri>? seen, int status = 200}) =>
    MockClient((request) async {
      seen?.add(request.url);
      if (status != 200) return http.Response('busy', status);
      final path = request.url.path;
      if (path.endsWith('/reverse')) {
        return http.Response(
          jsonEncode({
            'name': 'Somewhere',
            'address': {'natural': 'Fallen Leaf Lake', 'state': 'California'},
          }),
          200,
        );
      }
      if (path.endsWith('/v1/search')) {
        final name = request.url.queryParameters['name'];
        return http.Response(
          jsonEncode(
            name == 'Nowhere'
                ? {}
                : {
                    'results': [
                      {'latitude': 38.9, 'longitude': -120.05},
                    ],
                  },
          ),
          200,
        );
      }
      final day = request.url.queryParameters['start_date']!;
      return http.Response(
        jsonEncode({
          'hourly': {
            'time': ['${day}T19:00', '${day}T20:00'],
            'temperature_2m': [21.4, 19.6],
            'weather_code': [1, 3],
            'precipitation': [0.0, 0.2],
            'wind_speed_10m': [7.0, 9.4],
          },
        }),
        200,
      );
    });

void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  group('photo metadata', () {
    test('reads capture time and GPS from a JPEG', () {
      final image = img.Image(width: 8, height: 8);
      image.exif.exifIfd[0x9003] = img.IfdValueAscii('2026:06:06 20:10:33');
      image.exif.gpsIfd.setGpsLocation(latitude: 38.92, longitude: -120.05);
      final meta = readPhotoMetadata(img.encodeJpg(image));
      expect(meta.takenAt, DateTime(2026, 6, 6, 20, 10, 33));
      expect(meta.latitude, closeTo(38.92, 1e-6));
      expect(meta.longitude, closeTo(-120.05, 1e-6));
    });

    test('reads degrees/minutes/seconds GPS values', () {
      final image = img.Image(width: 8, height: 8);
      final gps = image.exif.gpsIfd;
      gps[0x0001] = img.IfdValueAscii('S');
      gps[0x0002] = img.IfdValueRational.list([
        Rational(33, 1),
        Rational(52, 1),
        Rational(1800, 100),
      ]);
      gps[0x0003] = img.IfdValueAscii('E');
      gps[0x0004] = img.IfdValueRational.list([
        Rational(151, 1),
        Rational(12, 1),
        Rational(36, 1),
      ]);
      final meta = readPhotoMetadata(img.encodeJpg(image));
      expect(meta.latitude, closeTo(-(33 + 52 / 60 + 18 / 3600), 1e-6));
      expect(meta.longitude, closeTo(151 + 12 / 60 + 36 / 3600, 1e-6));
    });

    test('photos without EXIF, and odd dates, are handled', () {
      final png = img.encodePng(img.Image(width: 4, height: 4));
      expect(readPhotoMetadata(png).isEmpty, isTrue);
      expect(readPhotoMetadata(Uint8List(0)).isEmpty, isTrue);
      expect(parseExifDate('0000:00:00 00:00:00'), isNull);
      expect(parseExifDate('2026:13:01 10:00:00'), isNull);
      expect(parseExifDate('2026:07:04 19:45'), DateTime(2026, 7, 4, 19, 45));
    });
  });

  group('places and weather', () {
    test('place names, search, and the weather for the event hour', () async {
      final seen = <Uri>[];
      final places = PlacesService(
        httpClient: fakePlaces(seen: seen),
        now: () => DateTime(2026, 7, 10),
      );
      expect(
        await places.placeName(38.9, -120.0),
        'Fallen Leaf Lake, California',
      );
      expect(await places.findPlace('Fallen Leaf Lake'), (38.9, -120.05));
      expect(await places.findPlace('Nowhere'), isNull);
      expect(await places.findPlace('  '), isNull);

      final recent = await places.weatherAt(
        38.9,
        -120.0,
        DateTime(2026, 7, 4, 20, 10),
      );
      expect(recent.condition, 'Overcast');
      expect(recent.temperatureC, 19.6);
      expect(recent.precipitationMm, 0.2);
      expect(seen.last.host, 'api.open-meteo.com');

      await places.weatherAt(38.9, -120.0, DateTime(2024, 7, 4, 19, 5));
      expect(seen.last.host, 'archive-api.open-meteo.com');
      // Every request identifies the app, as the services ask.
      expect(seen.every((u) => u.scheme == 'https'), isTrue);
    });

    test('missing data and errors become readable messages', () async {
      final places = PlacesService(httpClient: fakePlaces());
      await expectLater(
        places.weatherAt(1, 2, DateTime(2026, 7, 4, 3)),
        throwsA(isA<PlacesException>()),
      );
      final down = PlacesService(httpClient: fakePlaces(status: 503));
      await expectLater(
        down.findPlace('Lake'),
        throwsA(
          isA<PlacesException>().having(
            (e) => e.message,
            'message',
            contains('503'),
          ),
        ),
      );
    });
  });

  group('daily weather pass', () {
    test('the day runs from noon to noon', () {
      expect(
        dailyWindowStart(DateTime(2026, 7, 4, 11, 59)),
        DateTime(2026, 7, 3, 12),
      );
      expect(
        dailyWindowStart(DateTime(2026, 7, 4, 12)),
        DateTime(2026, 7, 4, 12),
      );
    });

    test('three videos unlock it until the next noon', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var now = DateTime(2026, 7, 4, 9);
      final videos = _Videos();
      final pass = WeatherPass(prefs, videos, scope: 'u1', now: () => now);
      expect(pass.unlocked, isFalse);
      expect(pass.resetsAt, DateTime(2026, 7, 4, 12));

      videos.finish = false;
      expect(await pass.watchVideo(), isFalse);
      expect(pass.progress, 0);
      videos.finish = true;
      await pass.watchVideo();
      await pass.watchVideo();
      expect(pass.unlocked, isFalse);
      await pass.watchVideo();
      expect(pass.unlocked, isTrue);
      expect(await pass.watchVideo(), isFalse); // nothing more to unlock
      expect(videos.shown, 4);

      now = DateTime(2026, 7, 4, 11, 59);
      expect(pass.unlocked, isTrue);
      now = DateTime(2026, 7, 4, 12);
      expect(pass.unlocked, isFalse);
      expect(pass.progress, 0);
      expect(pass.resetsAt, DateTime(2026, 7, 5, 12));

      // Another account on the phone has its own pass.
      final other = WeatherPass(prefs, videos, scope: 'u2', now: () => now);
      expect(other.progress, 0);
    });
  });

  group('app features', () {
    late Directory tmp;
    late AppState state;
    late List<Map<String, dynamic>> aiBodies;

    Future<void> setUpState({http.Client? placesClient}) async {
      tmp = await Directory.systemTemp.createTemp('eventlens_features');
      aiBodies = [];
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({
        'anthropic_api_key': 'sk-ant-t',
      });
      final db = await AppDatabase.open(
        factory: databaseFactoryFfi,
        path: '${tmp.path}/f.db',
      );
      state = AppState(
        events: EventRepository(db),
        memoryRepo: MemoryRepository(db),
        graphRepo: GraphRepository(db),
        vault: ImageVault(Directory('${tmp.path}/vault')),
        settings: SettingsService(
          const FlutterSecureStorage(),
          await SharedPreferences.getInstance(),
        ),
        places: PlacesService(
          httpClient: placesClient ?? fakePlaces(),
          now: () => DateTime(2026, 7, 10),
        ),
        describerFactory: (key, model, effort) => EventDescriber(
          model: model,
          effort: effort,
          client: AnthropicAIClient(
            apiKey: key,
            httpClient: MockClient((request) async {
              aiBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
              return http.Response(
                jsonEncode({
                  'model': model,
                  'stop_reason': 'end_turn',
                  'content': [
                    {
                      'type': 'text',
                      'text': jsonEncode({
                        'title': 'T',
                        'summary': 'S',
                        'description': 'D',
                        'people': <String>[],
                        'places': <String>[],
                        'tags': <String>[],
                        'memory_suggestions': <Object>[],
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
      await state.load();
    }

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('on this day finds earlier years only', () async {
      await setUpState();
      for (final (id, at) in [
        ('a', DateTime(2025, 7, 4, 10)),
        ('b', DateTime(2023, 7, 4, 18)),
        ('c', DateTime(2026, 7, 4, 9)),
        ('d', DateTime(2025, 7, 5, 9)),
      ]) {
        await state.events.save(
          LifeEvent(
            id: id,
            title: id,
            notes: '',
            location: '',
            occurredAt: at,
            createdAt: at,
            updatedAt: at,
          ),
        );
      }
      await state.load();
      expect(state.onThisDay(DateTime(2026, 7, 4)).map((e) => e.id), [
        'a',
        'b',
      ]);
    });

    test('weather uses photo coordinates or the place name, and is never '
        'sent to the AI', () async {
      final seen = <Uri>[];
      await setUpState(placesClient: fakePlaces(seen: seen));
      final withGps = await state.createEvent(
        title: 'Swim',
        notes: 'Evening swim',
        location: '',
        occurredAt: DateTime(2026, 7, 4, 20, 10),
        photos: const [],
        latitude: 38.92,
        longitude: -120.05,
      );
      await state.lookUpWeather(withGps.id);
      final w = state.eventById(withGps.id)!.weather!;
      expect(w.condition, 'Overcast');
      expect(seen.single.queryParameters['latitude'], '38.92');

      final named = await state.createEvent(
        title: 'Lake',
        notes: '',
        location: 'Fallen Leaf Lake',
        occurredAt: DateTime(2026, 7, 4, 19),
        photos: const [],
      );
      await state.lookUpWeather(named.id);
      final saved = state.eventById(named.id)!;
      expect(saved.weather!.condition, 'Mainly clear');
      expect(saved.latitude, 38.9);

      final nowhere = await state.createEvent(
        title: 'X',
        notes: 'n',
        location: '',
        occurredAt: DateTime(2026, 7, 4, 19),
        photos: const [],
      );
      await expectLater(
        state.lookUpWeather(nowhere.id),
        throwsA(
          isA<PlacesException>().having(
            (e) => e.message,
            'message',
            contains('Add a place'),
          ),
        ),
      );

      // Describing an event with weather sends nothing about the weather.
      await state.describeEvent(withGps.id);
      final sent = jsonEncode(aiBodies.single);
      final eventText = jsonEncode(aiBodies.single['messages']);
      expect(sent, isNot(contains('Overcast')));
      expect(sent, isNot(contains('19.6')));
      expect(eventText.toLowerCase(), isNot(contains('weather')));
      expect(sent, isNot(contains('38.92')));
      // And the weather survives the AI writing the account.
      expect(state.eventById(withGps.id)!.weather, isNotNull);
    });

    test(
      'export builds a linked Obsidian vault and a full data file',
      () async {
        await setUpState();
        final photo = File('${tmp.path}/p.jpg')
          ..writeAsBytesSync(img.encodeJpg(img.Image(width: 4, height: 4)));
        final a = await state.createEvent(
          title: 'Sunset: swim?',
          notes: 'Sam dared me',
          location: 'Fallen Leaf Lake',
          occurredAt: DateTime(2026, 6, 6, 20),
          photos: [photo],
        );
        final b = await state.createEvent(
          title: 'Sunset: swim?',
          notes: '',
          location: '',
          occurredAt: DateTime(2026, 6, 6, 21),
          photos: const [],
        );
        for (final e in [a, b]) {
          await state.events.update(
            state
                .eventById(e.id)!
                .copyWith(
                  description: 'The water was copper.',
                  people: const ['Sam'],
                  places: const ['Fallen Leaf Lake'],
                  tags: const ['summer'],
                  status: EventStatus.described,
                ),
          );
        }
        await state.addMemory('person', 'Sam is my brother');
        await state.graphRepo.replace(
          GraphSnapshot(
            id: 'g',
            createdAt: DateTime(2026, 7, 1),
            eventCount: 2,
            model: 'm',
            overview: 'A summer.',
            chapters: [
              TimelineChapter(
                id: 'c',
                title: 'Lake weeks',
                summary: 'Water.',
                eventIds: [a.id, b.id],
                bookId: 'bk',
              ),
            ],
            links: const [],
            themes: [
              StoryTheme(
                name: 'Swims',
                description: 'Cold water.',
                eventIds: [a.id],
              ),
            ],
            books: const [Book(id: 'bk', title: 'Summer 2026')],
            rings: {a.id: 1},
          ),
        );
        await state.load();

        final exporter = LibraryExporter(state.vault);
        final archive = await exporter.build(
          events: state.allEvents,
          memories: state.memories,
          graph: state.graphSnapshot,
          exportedAt: DateTime(2026, 7, 10),
        );
        String text(String name) =>
            utf8.decode(archive.findFile(name)!.content as List<int>);
        final names = archive.files.map((f) => f.name).toSet();

        const first = 'EventLens/Vault/Events/2026-06-06 Sunset swim.md';
        const second = 'EventLens/Vault/Events/2026-06-06 Sunset swim (2).md';
        expect(names, containsAll([first, second]));
        final note = text(first);
        expect(note, contains('[[People/Sam]]'));
        expect(note, contains('[[Places/Fallen Leaf Lake]]'));
        expect(note, contains('[[Chapters/Lake weeks]]'));
        expect(note, contains('[[Books/Summer 2026]]'));
        expect(note, contains('ring: "#e53935"'));
        expect(note, contains('## My notes at the time'));
        final image = state.eventById(a.id)!.images.single.fileName;
        expect(note, contains('![[$image]]'));
        expect(names, contains('EventLens/Vault/attachments/$image'));

        final sam = text('EventLens/Vault/People/Sam.md');
        expect(sam, contains('[[Events/2026-06-06 Sunset swim]]'));
        expect(sam, contains('[[Events/2026-06-06 Sunset swim (2)]]'));
        expect(
          text('EventLens/Vault/Themes/Swims.md'),
          contains('Cold water.'),
        );
        expect(
          text('EventLens/Vault/EventLens.md'),
          contains('Sam is my brother'),
        );

        final data =
            jsonDecode(text('EventLens/data.json')) as Map<String, dynamic>;
        expect((data['events'] as List), hasLength(2));
        expect(data['graph']['books'][0]['title'], 'Summer 2026');

        final zip = await exporter.writeZip(
          archive,
          tmp,
          exportedAt: DateTime(2026, 7, 10, 9, 5),
        );
        expect(zip.path, endsWith('EventLens-export-2026-07-10_0905.zip'));
        final reread = ZipDecoder().decodeBytes(await zip.readAsBytes());
        expect(reread.findFile(first), isNotNull);
      },
    );
  });

  group('separate libraries per account', () {
    test('each account has its own data; the old library goes to the first '
        'person to sign in', () async {
      final tmp = await Directory.systemTemp.createTemp('eventlens_libs');
      addTearDown(() => tmp.delete(recursive: true));
      final dbDir = '${tmp.path}/db';
      final docs = '${tmp.path}/docs';
      await Directory(dbDir).create();

      // A library from before accounts existed.
      final legacyDb = await AppDatabase.open(
        factory: databaseFactoryFfi,
        path: '$dbDir/eventlens.db',
      );
      final at = DateTime(2026, 6, 1);
      await EventRepository(legacyDb).save(
        LifeEvent(
          id: 'old',
          title: 'From before accounts',
          notes: '',
          location: '',
          occurredAt: at,
          createdAt: at,
          updatedAt: at,
        ),
      );
      await legacyDb.close();
      await Directory('$docs/vault').create(recursive: true);
      await File('$docs/vault/photo.jpg').writeAsString('x');

      SharedPreferences.setMockInitialValues({
        'model': 'claude-sonnet-5-5',
        'ring_unlocked_count': 3,
      });
      FlutterSecureStorage.setMockInitialValues({
        'anthropic_api_key': 'sk-ant-old',
      });
      final prefs = await SharedPreferences.getInstance();
      final videos = _Videos();

      Future<Library> open(String uid) => openLibrary(
        uid: uid,
        prefs: prefs,
        videos: videos,
        databasesDir: dbDir,
        documentsDir: docs,
        factory: databaseFactoryFfi,
      );

      final first = await open('alice/123');
      expect(first.state.allEvents.single.title, 'From before accounts');
      expect(await first.state.settings.readApiKey(), 'sk-ant-old');
      expect(first.state.model, 'claude-sonnet-5-5');
      expect(first.unlocks.unlockedCount, 3);
      expect(File('$docs/vaults/alice_123/photo.jpg').existsSync(), isTrue);
      expect(File('$dbDir/eventlens.db').existsSync(), isFalse);
      await first.state.addMemory('fact', 'Alice only');
      await first.close();

      final second = await open('bob');
      expect(second.state.allEvents, isEmpty);
      expect(second.state.memories, isEmpty);
      expect(await second.state.settings.readApiKey(), isNull);
      expect(second.unlocks.unlockedCount, 1);
      await second.state.createEvent(
        title: 'Bob\'s',
        notes: 'n',
        location: '',
        occurredAt: at,
        photos: const [],
      );
      await second.close();

      final again = await open('alice/123');
      expect(again.state.allEvents.single.title, 'From before accounts');
      expect(again.state.memories.single.content, 'Alice only');
      await again.close();
      expect(libraryKey('a b/c'), 'a_b_c');
    });
  });
}
