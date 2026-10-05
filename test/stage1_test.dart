import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:eventlens/ai/anthropic_ai_client.dart';
import 'package:eventlens/ai/data_platform_advisor.dart';
import 'package:eventlens/ai/event_describer.dart';
import 'package:eventlens/app.dart';
import 'package:eventlens/data/app_database.dart';
import 'package:eventlens/data/event_repository.dart';
import 'package:eventlens/data/graph_repository.dart';
import 'package:eventlens/data/image_vault.dart';
import 'package:eventlens/data/memory_repository.dart';
import 'package:eventlens/models/event.dart';
import 'package:eventlens/models/library_meters.dart';
import 'package:eventlens/models/memory_graph.dart';
import 'package:eventlens/screens/auth_screen.dart';
import 'package:eventlens/screens/data_screen.dart';
import 'package:eventlens/screens/memory_screen.dart';
import 'package:eventlens/services/auth_service.dart';
import 'package:eventlens/services/data_files.dart';
import 'package:eventlens/services/export_service.dart';
import 'package:eventlens/services/insight_pass.dart';
import 'package:eventlens/services/rewards_service.dart';
import 'package:eventlens/services/settings_service.dart';
import 'package:eventlens/services/web3_identity.dart';
import 'package:eventlens/state/app_state.dart';
import 'package:eventlens/state/library_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _NoVideos implements RewardedVideoProvider {
  @override
  Future<bool> showRewardedVideo() async => false;
}

class _SignedIn extends LocalReviewAuthService {
  _SignedIn(super.prefs);

  bool out = false;

  @override
  AppUser? get user => out ? null : const AppUser(uid: 'u', label: 'me');

  @override
  Future<void> signOut() async {
    out = true;
    notifyListeners();
  }
}

/// A Claude API stand-in. [gate] holds every reply until completed.
class _Ai {
  final List<Map<String, dynamic>> bodies = [];
  Completer<void>? gate;
  Object Function(Map<String, dynamic> body) reply = (_) => {};
  int status = 200;

  http.Client get client => MockClient((request) async {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    bodies.add(body);
    await gate?.future;
    if (status != 200) return http.Response('{}', status);
    return http.Response(
      jsonEncode({
        'model': body['model'],
        'stop_reason': 'end_turn',
        'content': [
          {'type': 'text', 'text': jsonEncode(reply(body))},
        ],
      }),
      200,
    );
  });
}

LifeEvent _event(
  String id,
  DateTime at, {
  String title = '',
  List<String> people = const [],
  List<String> places = const [],
  List<String> tags = const [],
  String notes = '',
  String description = '',
  int photos = 0,
}) => LifeEvent(
  id: id,
  title: title.isEmpty ? id : title,
  notes: notes,
  location: '',
  occurredAt: at,
  createdAt: at,
  updatedAt: at,
  description: description,
  people: people,
  places: places,
  tags: tags,
  status: description.isEmpty ? EventStatus.draft : EventStatus.described,
  images: [
    for (var i = 0; i < photos; i++)
      EventImage(
        id: '$id-$i',
        eventId: id,
        fileName: '$id-$i.jpg',
        position: i,
      ),
  ],
);

void main() {
  sqfliteFfiInit();

  late Directory tmp;
  late SharedPreferences prefs;
  late _Ai ai;

  Future<AppState> makeState({String? apiKey, String file = 's.db'}) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      'anthropic_api_key': ?apiKey,
    });
    prefs = await SharedPreferences.getInstance();
    final db = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: '${tmp.path}/$file',
    );
    final state = AppState(
      events: EventRepository(db),
      memoryRepo: MemoryRepository(db),
      graphRepo: GraphRepository(db),
      vault: ImageVault(Directory('${tmp.path}/vault')),
      settings: SettingsService(const FlutterSecureStorage(), prefs),
      describerFactory: (key, model, effort) => EventDescriber(
        model: model,
        effort: effort,
        client: AnthropicAIClient(apiKey: key, httpClient: ai.client),
      ),
      advisorFactory: (key, model) => DataPlatformAdvisor(
        model: model,
        client: AnthropicAIClient(
          apiKey: key,
          httpClient: ai.client,
          maxRetries: 0,
        ),
      ),
    );
    await state.load();
    return state;
  }

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('eventlens_stage1');
    ai = _Ai();
  });
  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  group('CSV files', () {
    test('fields with commas, quotes and line breaks are quoted', () {
      expect(
        encodeCsv([
          ['a', 'b,c', 'say "hi"', 'two\nlines', null, 3],
        ]),
        'a,"b,c","say ""hi""","two\nlines",,3\r\n',
      );
      expect(withBom('x').codeUnitAt(0), 0xFEFF);
    });

    test('basic and analysis files hold one row per event, oldest first', () {
      final events = [
        _event(
          'b',
          DateTime(2026, 7, 4, 20, 5),
          people: ['Sam', 'Mum'],
          tags: ['summer'],
          notes: 'hot day',
          description: 'We swam.',
          photos: 2,
        ),
        _event('a', DateTime(2026, 1, 2, 9), title: 'New year, new start'),
      ];
      final graph = GraphSnapshot(
        id: 'g',
        createdAt: DateTime(2026, 7, 5),
        eventCount: 1,
        model: 'm',
        overview: '',
        chapters: const [
          TimelineChapter(
            id: 'c',
            title: 'Summer',
            summary: '',
            eventIds: ['b'],
            bookId: 'bk',
          ),
        ],
        links: const [],
        themes: const [
          StoryTheme(name: 'Water', description: '', eventIds: ['b']),
        ],
        books: const [Book(id: 'bk', title: '2026')],
        rings: const {'b': 0},
      );

      final basic = const LineSplitter().convert(basicCsv(events));
      expect(basic.first, startsWith('Date,Time,Title,Place,People'));
      expect(basic[1], startsWith('2026-01-02,09:00,"New year, new start"'));
      expect(basic[2], contains('Sam; Mum'));

      final rows = const LineSplitter().convert(analysisCsv(events, graph));
      expect(rows.first.split(','), [for (final c in analysisColumns) c.name]);
      final b = rows[2].split(',');
      String col(String name) =>
          b[analysisColumns.indexWhere((c) => c.name == name)];
      expect(col('occurred_at'), '2026-07-04T20:05:00');
      expect(col('weekday'), 'Sat');
      expect(col('hour'), '20');
      expect(col('described'), '1');
      expect(col('photo_count'), '2');
      expect(col('notes_words'), '2');
      expect(col('people'), 'Sam|Mum');
      expect(col('chapter'), 'Summer');
      expect(col('book'), '2026');
      expect(col('themes'), 'Water');
      expect(col('ring_color'), startsWith('#'));
      expect(analysisDictionary(), contains('https://jupyter.org'));
    });
  });

  group('Your data meters', () {
    test('meters measure the whole library', () {
      final meters = {
        for (final m in computeMeters(
          events: [
            _event(
              'a',
              DateTime(2025, 6, 1),
              people: ['Sam'],
              places: ['Lake'],
              photos: 2,
              description: 'one two three',
            ),
            _event(
              'b',
              DateTime(2026, 6, 3),
              people: ['Sam', 'Mum'],
              photos: 1,
              notes: 'four five',
            ),
            _event('c', DateTime(2026, 6, 9), people: ['Mum', 'Sam']),
          ],
          memories: const [],
        ))
          m.id: m,
      };
      expect(meters.keys, meterIds);
      expect(meters['events']!.value, '3');
      expect(meters['photos']!.value, '3');
      expect(meters['described']!.detail, '33% of events');
      expect(meters['people']!.value, '2');
      expect(meters['top_person']!.value, 'Sam');
      expect(meters['top_person']!.detail, 'in 3 events');
      expect(meters['busiest_month']!.value, 'Jun 2026');
      expect(meters['span']!.value, '12 months');
      expect(meters['words_ai']!.value, '3');
      expect(meters['words_mine']!.value, '2');
      expect(meters['graph']!.value, '2 of 10 photos');
    });

    test('an empty library shows sensible values', () {
      final meters = computeMeters(events: const [], memories: const []);
      expect(meters.firstWhere((m) => m.id == 'span').value, 'None yet');
      expect(meters.firstWhere((m) => m.id == 'photos_per_event').value, '0');
    });

    test('hidden meters are kept per account and can come back', () async {
      final state = await makeState();
      await state.setMeterHidden('photos', true);
      await state.setMeterHidden('tags', true);
      expect(state.hiddenMeters, {'photos', 'tags'});
      await state.setMeterHidden('photos', false);
      expect(state.hiddenMeters, {'tags'});
      final other = SettingsService(
        const FlutterSecureStorage(),
        prefs,
        scope: 'someone-else',
      );
      expect(other.hiddenMeters, isEmpty);
    });
  });

  group('export unlock', () {
    test('the full export unlocks at 100 events and stays unlocked', () async {
      final state = await makeState();
      for (var i = 0; i < exportUnlockEvents - 1; i++) {
        await state.events.save(
          _event('e$i', DateTime(2026, 1, 1).add(Duration(hours: i))),
        );
      }
      await state.load();
      expect(state.exportUnlocked, isFalse);
      expect(state.eventsUntilExport, 1);
      await state.createEvent(
        title: 'The 100th',
        notes: '',
        location: '',
        occurredAt: DateTime(2026, 9, 1),
        photos: const [],
      );
      expect(state.exportUnlocked, isTrue);
      expect(state.eventsUntilExport, 0);
      await state.deleteEvent(state.allEvents.first);
      expect(state.allEvents, hasLength(exportUnlockEvents - 1));
      expect(state.exportUnlocked, isTrue);
    });
  });

  group('data platforms from the AI', () {
    test('without a key the most likely platform is shown', () async {
      final state = await makeState();
      final advice = await state.dataPlatforms();
      expect(advice.fromAi, isFalse);
      expect(advice.platforms.single.determined, isFalse);
      expect(ai.bodies, isEmpty);
    });

    test('the AI is asked once with column names only, then cached', () async {
      final state = await makeState(apiKey: 'sk-ant-t');
      await state.events.save(
        _event('a', DateTime(2026, 1, 1), title: 'Secret trip'),
      );
      await state.load();
      ai.reply = (_) => {
        'platforms': [
          {'name': 'pandas', 'use': 'Tables.', 'fit': 'determined'},
          {'name': 'Plotly', 'use': 'Charts.', 'fit': 'likely'},
        ],
        'none_determinable': false,
      };
      final advice = await state.dataPlatforms();
      expect(advice.fromAi, isTrue);
      expect(advice.platforms.map((p) => p.name), ['pandas', 'Plotly']);
      expect(advice.platforms.first.determined, isTrue);
      final sent = jsonEncode(ai.bodies.single);
      expect(sent, contains('occurred_at'));
      expect(sent, isNot(contains('Secret trip')));

      final again = await state.dataPlatforms();
      expect(again.platforms, hasLength(2));
      expect(ai.bodies, hasLength(1));
    });

    test(
      '"none determinable" and failures are reported, failures not kept',
      () async {
        final state = await makeState(apiKey: 'sk-ant-t');
        ai.reply = (_) => {'platforms': [], 'none_determinable': true};
        expect((await state.dataPlatforms()).noneDeterminable, isTrue);

        ai.status = 400;
        final failed = await state.dataPlatforms(refresh: true);
        expect(failed.fromAi, isFalse);
        expect(
          PlatformAdvice.fromJsonString(state.settings.platformAdvice)!
              .noneDeterminable,
          isTrue,
        );
      },
    );

    test('cached answers expire when the columns change', () {
      const advice = PlatformAdvice(
        platforms: [DataPlatform(name: 'pandas', use: 'x', determined: true)],
      );
      final text = advice.toJsonString();
      expect(
        PlatformAdvice.fromJsonString(text)!.platforms.single.name,
        'pandas',
      );
      final stale = (jsonDecode(text) as Map)..['columns_version'] = 'old';
      expect(PlatformAdvice.fromJsonString(jsonEncode(stale)), isNull);
      expect(PlatformAdvice.fromJsonString('not json'), isNull);
    });
  });

  group('editing while the AI works', () {
    Map<String, dynamic> account(Map<String, dynamic> _) => {
      'title': 'AI title',
      'summary': 'S',
      'description': 'The AI account.',
      'people': <String>[],
      'places': <String>[],
      'tags': <String>[],
      'memory_suggestions': <Object>[],
    };

    test(
      'an edit made while describing is kept, and the account too',
      () async {
        final state = await makeState(apiKey: 'sk-ant-t');
        ai.reply = account;
        ai.gate = Completer();
        final e = await state.createEvent(
          title: 'Swim',
          notes: 'n',
          location: '',
          occurredAt: DateTime(2026, 7, 4),
          photos: const [],
        );
        final opened = state.eventById(e.id)!;
        final describing = state.describeEvent(e.id);
        // A second tap while the first is running starts nothing.
        await state.describeEvent(e.id);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await state.updateEventDetails(opened, notes: 'Edited while waiting');
        ai.gate!.complete();
        await describing;
        final saved = state.eventById(e.id)!;
        expect(saved.notes, 'Edited while waiting');
        expect(saved.description, 'The AI account.');
        expect(saved.status, EventStatus.described);
        expect(ai.bodies, hasLength(1));

        // Saving the edit sheet that was opened before the account arrived
        // doesn't wipe the account either.
        await state.updateEventDetails(opened, title: 'Evening swim');
        expect(state.eventById(e.id)!.description, 'The AI account.');
        expect(state.eventById(e.id)!.status, EventStatus.described);
      },
    );

    test('a new place clears the old map position and weather', () async {
      final state = await makeState();
      final e = await state.createEvent(
        title: 'Trip',
        notes: '',
        location: 'Paris',
        occurredAt: DateTime(2026, 7, 4, 12),
        photos: const [],
        latitude: 48.85,
        longitude: 2.35,
      );
      await state.events.update(
        state
            .eventById(e.id)!
            .copyWith(
              weather: EventWeather(
                temperatureC: 20,
                weatherCode: 0,
                precipitationMm: 0,
                windKmh: 5,
                fetchedAt: DateTime(2026, 7, 5),
              ),
            ),
      );
      await state.load();
      await state.updateEventDetails(state.eventById(e.id)!, title: 'Trip!');
      expect(state.eventById(e.id)!.weather, isNotNull);
      expect(state.eventById(e.id)!.hasCoordinates, isTrue);

      await state.updateEventDetails(state.eventById(e.id)!, location: 'Tokyo');
      final moved = state.eventById(e.id)!;
      expect(moved.hasCoordinates, isFalse);
      expect(moved.weather, isNull);
    });
  });

  test('the noon refresh stays at noon on daylight-saving days', () {
    // Calendar arithmetic gives 12:00 the day before, whatever the zone.
    expect(
      dailyWindowStart(DateTime(2026, 3, 8, 10)),
      DateTime(2026, 3, 7, 12),
    );
    expect(
      dailyWindowStart(DateTime(2026, 11, 1, 9)),
      DateTime(2026, 10, 31, 12),
    );
    expect(
      dailyWindowStart(DateTime(2026, 3, 1, 9)),
      DateTime(2026, 2, 28, 12),
    );
  });

  group('export files', () {
    test('notes differing only in capitals share one file; equal chapter '
        'titles get their own', () async {
      final state = await makeState();
      await state.events.save(
        _event('a', DateTime(2026, 6, 1), people: ['Sam'], tags: ['Beach']),
      );
      await state.events.save(
        _event('b', DateTime(2026, 6, 2), people: ['sam'], tags: ['beach']),
      );
      await state.load();
      final archive = await LibraryExporter(state.vault).build(
        events: state.allEvents,
        memories: const [],
        graph: GraphSnapshot(
          id: 'g',
          createdAt: DateTime(2026, 6, 3),
          eventCount: 2,
          model: 'm',
          overview: '',
          chapters: const [
            TimelineChapter(
              id: 'c1',
              title: 'June',
              summary: 'First.',
              eventIds: ['a'],
            ),
            TimelineChapter(
              id: 'c2',
              title: 'june',
              summary: 'Second.',
              eventIds: ['b'],
            ),
          ],
          links: const [],
          themes: const [],
        ),
      );
      final names = archive.files.map((f) => f.name.toLowerCase()).toList();
      expect(names.toSet(), hasLength(names.length));
      String text(String name) =>
          utf8.decode(archive.findFile(name)!.content as List<int>);
      final sam = text('EventLens/Vault/People/Sam.md');
      expect(sam, contains('2026-06-01 a'));
      expect(sam, contains('2026-06-02 b'));
      expect(text('EventLens/Vault/Chapters/June.md'), contains('First.'));
      expect(text('EventLens/Vault/Chapters/june (2).md'), contains('Second.'));
      expect(
        text('EventLens/Vault/Events/2026-06-02 b.md'),
        contains('[[Chapters/june (2)]]'),
      );
      expect(names, contains('eventlens/eventlens-basic.csv'));
      expect(names, contains('eventlens/eventlens-analysis.csv'));
      expect(names, contains('eventlens/eventlens-analysis-columns.txt'));
    });

    test('photos are streamed into the zip, off the main isolate', () async {
      final state = await makeState();
      final photo = File('${tmp.path}/p.jpg')
        ..writeAsBytesSync(img.encodeJpg(img.Image(width: 40, height: 30)));
      await state.createEvent(
        title: 'Pic',
        notes: '',
        location: '',
        occurredAt: DateTime(2026, 6, 1),
        photos: [photo],
      );
      final file = await LibraryExporter(state.vault).exportZip(
        events: state.allEvents,
        memories: state.memories,
        graph: null,
        directory: tmp,
      );
      final zip = ZipDecoder().decodeBytes(await file.readAsBytes());
      final name = state.allEvents.single.images.single.fileName;
      final stored = zip.findFile('EventLens/Vault/attachments/$name')!;
      expect(stored.content, await photo.readAsBytes());
    });
  });

  group('Web3 identities', () {
    test('the sign-in message follows EIP-4361', () {
      final message = signInMessage(
        domain: 'eventlens.app',
        address: '0x71C7656EC7ab88b098defB751B7401B5f6d8976F',
        uri: Uri.parse('https://eventlens.app/login'),
        nonce: 'abc12345',
        issuedAt: DateTime.utc(2026, 10, 3, 12),
      );
      expect(
        message,
        'eventlens.app wants you to sign in with your Ethereum account:\n'
        '0x71C7656EC7ab88b098defB751B7401B5f6d8976F\n'
        '\n'
        'Sign in to EventLens. This is free and is not a transaction.\n'
        '\n'
        'URI: https://eventlens.app/login\n'
        'Version: 1\n'
        'Chain ID: 1\n'
        'Nonce: abc12345\n'
        'Issued At: 2026-10-03T12:00:00.000Z',
      );
      final solana = signInMessage(
        domain: 'eventlens.app',
        address: 'So1ana',
        uri: Uri.parse('https://eventlens.app'),
        nonce: 'abc12345',
        issuedAt: DateTime.utc(2026),
        chain: Web3Chain.solana,
      );
      expect(
        solana,
        startsWith(
          'eventlens.app wants you to sign in with your Solana account:',
        ),
      );
      expect(solana, isNot(contains('Chain ID')));
      expect(
        () => signInMessage(
          domain: 'd',
          address: 'a',
          uri: Uri(),
          nonce: 'short',
          issuedAt: DateTime.utc(2026),
        ),
        throwsArgumentError,
      );
      expect(
        shortAddress('0x71C7656EC7ab88b098defB751B7401B5f6d8976F'),
        '0x71C7…976F',
      );
    });

    testWidgets('the account screen labels Web3 identities and explains them', (
      tester,
    ) async {
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        prefs = await SharedPreferences.getInstance();
      });
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthService>(
              create: (_) => LocalReviewAuthService(prefs),
            ),
            ChangeNotifierProvider(create: (_) => BiometricLock(prefs)),
          ],
          child: const MaterialApp(home: AuthScreen()),
        ),
      );
      await tester.scrollUntilVisible(
        find.text('These are Web3 identities'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Continue with Ethereum wallet'), findsOneWidget);
      expect(find.text('Continue with Solana wallet'), findsOneWidget);
      expect(find.text('Continue with Farcaster'), findsOneWidget);

      await tester.tap(find.text('What is this?'));
      await tester.pumpAndSettle();
      expect(find.text('What is a Web3 identity?'), findsOneWidget);
      expect(find.text('Does it cost anything?'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Got it'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.ensureVisible(find.text('Got it'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
      expect(find.text('What is a Web3 identity?'), findsNothing);

      await tester.ensureVisible(find.text('Continue with Ethereum wallet'));
      await tester.tap(find.text('Continue with Ethereum wallet'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('isn\'t connected in this build yet'),
        findsOneWidget,
      );
    });
  });

  group('screens', () {
    Future<AppState> setUpScreen(WidgetTester tester, {int events = 3}) async {
      final state = (await tester.runAsync(() async {
        final s = await makeState();
        for (var i = 0; i < events; i++) {
          await s.events.save(
            _event(
              'e$i',
              DateTime(2026, 1, 1).add(Duration(days: i)),
              people: ['Sam'],
              photos: 1,
            ),
          );
        }
        await s.load();
        return s;
      }))!;
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.reset);
      return state;
    }

    testWidgets('the real app: screens opened from Home reach the library, '
        'and the lock covers them without closing it', (tester) async {
      final state = await setUpScreen(tester);
      final auth = _SignedIn(prefs);
      final lock = BiometricLock(prefs);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthService>.value(value: auth),
            ChangeNotifierProvider.value(value: lock),
            Provider<LibraryOpener>.value(
              value: (uid) async => Library(
                state: state,
                unlocks: RingUnlocks(prefs, _NoVideos(), scope: uid),
                weather: WeatherPass(prefs, _NoVideos(), scope: uid),
                insights: InsightPass(prefs, _NoVideos(), scope: uid),
              ),
            ),
          ],
          child: const EventLensApp(),
        ),
      );
      await tester.pumpAndSettle();
      for (final (tooltip, screen) in [
        ('What the AI is learning', MemoryScreen),
        ('Your data', DataScreen),
      ]) {
        await tester.tap(find.byTooltip(tooltip));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(screen), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
      }

      await tester.runAsync(() => prefs.setBool('biometric_lock', true));
      lock.lockAgain();
      await tester.pumpAndSettle();
      expect(find.text('EventLens is locked'), findsOneWidget);
      // Home is still there underneath, with its library open.
      expect(find.byTooltip('Your data', skipOffstage: false), findsOneWidget);
      await tester.tap(find.text('Sign out instead'));
      await tester.pumpAndSettle();
      expect(find.text('Welcome to $appName'), findsOneWidget);
    });

    Widget app(AppState state, Widget home) => MultiProvider(
      providers: [ChangeNotifierProvider.value(value: state)],
      child: MaterialApp(home: home),
    );

    testWidgets('under 100 events: free CSV, a preview of the full export, '
        'and meters that can be hidden and brought back', (tester) async {
      final state = await setUpScreen(tester);
      await tester.pumpWidget(app(state, const DataScreen()));
      expect(find.text('Basic CSV'), findsOneWidget);
      expect(find.text('Preview: full export'), findsOneWidget);
      expect(find.text('3 of 100 events'), findsOneWidget);
      expect(find.text('Full export (zip)'), findsNothing);
      expect(find.text('Photos'), findsOneWidget);

      await tester.tap(find.byTooltip('Choose meters'));
      await tester.pumpAndSettle();
      await tester.runAsync(() => state.setMeterHidden('photos', true));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.text('Choose meters'))).pop();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('1 hidden meter: show it again'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Photos'), findsNothing);
    });

    testWidgets('at 100 events the full export and the guide appear', (
      tester,
    ) async {
      final state = await setUpScreen(tester, events: exportUnlockEvents);
      await tester.pumpWidget(app(state, const DataScreen()));
      expect(find.text('Full export unlocked'), findsOneWidget);
      expect(find.text('Full export (zip)'), findsOneWidget);
      expect(find.text('Basic CSV'), findsOneWidget);
      expect(find.text('Analysis CSV (for Python)'), findsOneWidget);
      expect(find.text('Preview: full export'), findsNothing);

      await tester.tap(find.text('How to explore your data with Python'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Python knowledge is recommended'),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.text('jupyter.org'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      // No API key in this test, so the most likely platform is shown.
      expect(find.text('pandas in a Jupyter notebook'), findsOneWidget);
    });
  });
}
