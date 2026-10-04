import 'dart:convert';
import 'dart:io';

import 'package:eventlens/data/app_database.dart';
import 'package:eventlens/data/event_repository.dart';
import 'package:eventlens/data/graph_repository.dart';
import 'package:eventlens/data/image_vault.dart';
import 'package:eventlens/data/memory_repository.dart';
import 'package:eventlens/models/event.dart';
import 'package:eventlens/screens/event_detail_screen.dart';
import 'package:eventlens/screens/home_screen.dart';
import 'package:eventlens/screens/memory_screen.dart';
import 'package:eventlens/screens/new_event_screen.dart';
import 'package:eventlens/screens/settings_screen.dart';
import 'package:eventlens/services/auth_service.dart';
import 'package:eventlens/services/places_service.dart';
import 'package:eventlens/services/rewards_service.dart';
import 'package:eventlens/services/settings_service.dart';
import 'package:eventlens/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Smoke tests for every main screen: each renders with real data and its
/// main actions work end to end against a real (FFI) database.
class _SignedIn extends LocalReviewAuthService {
  _SignedIn(super.prefs);

  bool signedOut = false;

  @override
  AppUser? get user =>
      signedOut ? null : const AppUser(uid: 'u', label: 'me@example.com');

  @override
  Future<void> signOut() async {
    signedOut = true;
    notifyListeners();
  }
}

class _NoVideos implements RewardedVideoProvider {
  @override
  Future<bool> showRewardedVideo() async => false;
}

class _FinishedVideos implements RewardedVideoProvider {
  @override
  Future<bool> showRewardedVideo() async => true;
}

/// Open-Meteo stand-in: one clear evening at 21 °C.
final _weatherServer = MockClient((request) async {
  final day = request.url.queryParameters['start_date'];
  return http.Response(
    jsonEncode({
      'results': [
        {'latitude': 38.9, 'longitude': -120.05},
      ],
      'hourly': {
        'time': ['${day}T20:00'],
        'temperature_2m': [21.0],
        'weather_code': [0],
        'precipitation': [0.0],
        'wind_speed_10m': [5.0],
      },
    }),
    200,
  );
});

void main() {
  sqfliteFfiInit();

  late Directory tmp;
  late AppState state;
  late SharedPreferences prefs;
  late _SignedIn auth;

  Future<void> setUpState(WidgetTester tester) async {
    tmp = Directory.systemTemp.createTempSync('eventlens_screens');
    addTearDown(() => tmp.deleteSync(recursive: true));
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      final db = await AppDatabase.open(
        factory: databaseFactoryFfi,
        path: '${tmp.path}/s.db',
      );
      state = AppState(
        events: EventRepository(db),
        memoryRepo: MemoryRepository(db),
        graphRepo: GraphRepository(db),
        vault: ImageVault(Directory('${tmp.path}/vault')),
        settings: SettingsService(const FlutterSecureStorage(), prefs),
        places: PlacesService(httpClient: _weatherServer),
      );
      final at = DateTime(2026, 6, 6, 20);
      await state.events.save(
        LifeEvent(
          id: 'lake',
          title: 'Sunset swim',
          notes: 'Sam dared me in',
          location: 'Fallen Leaf Lake',
          occurredAt: at,
          createdAt: at,
          updatedAt: at,
          summary: 'Swimming at sunset with Sam.',
          description: 'The water was copper in the last light.',
          people: const ['Sam'],
          places: const ['Fallen Leaf Lake'],
          tags: const ['summer'],
          status: EventStatus.described,
          suggestions: const [
            MemorySuggestion(kind: 'person', content: 'Sam is my brother'),
          ],
        ),
      );
      await state.events.save(
        LifeEvent(
          id: 'market',
          title: 'Market with Mum',
          notes: 'Peaches',
          location: '',
          occurredAt: DateTime(2026, 7, 1, 10),
          createdAt: at,
          updatedAt: at,
          status: EventStatus.failed,
          error: 'No internet connection. Check your network and try again.',
        ),
      );
      await state.load();
      auth = _SignedIn(prefs);
    });
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
  }

  Widget app(Widget home, {RewardedVideoProvider? videos}) => MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: state),
      ChangeNotifierProvider<AuthService>.value(value: auth),
      ChangeNotifierProvider(create: (_) => BiometricLock(prefs)),
      ChangeNotifierProvider(create: (_) => RingUnlocks(prefs, _NoVideos())),
      ChangeNotifierProvider(
        create: (_) => WeatherPass(prefs, videos ?? _NoVideos()),
      ),
    ],
    child: MaterialApp(home: home),
  );

  /// Pumps until [done] holds (or ~5 s pass). Saves are real database I/O,
  /// so they need real time, and CI machines can be slow.
  Future<void> settle(WidgetTester tester, [bool Function()? done]) async {
    for (var i = 0; i < 50; i++) {
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      if (i >= 2 && (done == null || done())) break;
    }
    await tester.pumpAndSettle();
  }

  testWidgets('home lists events by month, asks for a key, and searches', (
    tester,
  ) async {
    await setUpState(tester);
    await tester.pumpWidget(app(const HomeScreen()));
    expect(find.text('July 2026'), findsOneWidget);
    expect(find.text('June 2026'), findsOneWidget);
    expect(find.text('Sunset swim'), findsOneWidget);
    expect(find.text('Described'), findsOneWidget);
    expect(find.text('Needs retry'), findsOneWidget);
    expect(find.text('Add key'), findsOneWidget);

    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'copper');
    await tester.pumpAndSettle();
    expect(find.text('Sunset swim'), findsOneWidget);
    expect(find.text('Market with Mum'), findsNothing);
  });

  testWidgets('event detail shows the account, labels, notes and saves a '
      'suggested memory', (tester) async {
    await setUpState(tester);
    await tester.pumpWidget(app(const EventDetailScreen(eventId: 'lake')));
    expect(
      find.text('The water was copper in the last light.'),
      findsOneWidget,
    );
    expect(find.text('Sam'), findsOneWidget);
    expect(find.text('Fallen Leaf Lake'), findsWidgets);
    expect(find.text('AI Notes'), findsOneWidget);
    expect(find.text('Remember for next time?'), findsOneWidget);

    await tester.tap(find.byTooltip('Save to memory'));
    await settle(
      tester,
      () =>
          state.memories.isNotEmpty &&
          state.eventById('lake')!.suggestions.isEmpty,
    );
    expect(state.memories.single.content, 'Sam is my brother');
    expect(find.text('Remember for next time?'), findsNothing);
  });

  testWidgets('a failed event shows the reason and Retry explains the key', (
    tester,
  ) async {
    await setUpState(tester);
    await tester.pumpWidget(app(const EventDetailScreen(eventId: 'market')));
    expect(find.textContaining('No internet connection'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await settle(
      tester,
      () => state.eventById('market')!.error!.contains('API key'),
    );
    expect(find.textContaining('Add your Anthropic API key'), findsOneWidget);
  });

  testWidgets('event details can be edited', (tester) async {
    await setUpState(tester);
    await tester.pumpWidget(app(const EventDetailScreen(eventId: 'lake')));
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit details'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Dare');
    await tester.tap(find.text('Save'));
    await settle(tester, () => state.eventById('lake')!.title == 'Dare');
    expect(state.eventById('lake')!.title, 'Dare');
  });

  testWidgets('memory screen adds and lists a memory', (tester) async {
    await setUpState(tester);
    await tester.pumpWidget(app(const MemoryScreen()));
    expect(find.textContaining('No memories yet'), findsOneWidget);
    await tester.tap(find.text('Add memory'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Place'));
    await tester.enterText(
      find.byType(TextField).last,
      'The lake is where we camped as kids',
    );
    await tester.tap(find.text('Save'));
    await settle(tester, () => state.memories.isNotEmpty);
    expect(state.memories.single.kind, 'place');
    expect(find.text('The lake is where we camped as kids'), findsOneWidget);
  });

  testWidgets('new event saves notes without photos and opens the event', (
    tester,
  ) async {
    await setUpState(tester);
    await tester.pumpWidget(app(const NewEventScreen()));
    expect(find.text('Photos (0/10)'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      find.text('Add at least one photo, some AI Notes or a free write.'),
      findsOneWidget,
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'AI Notes'),
      'First day at the new studio',
    );
    await tester.tap(find.text('Save'));
    await settle(tester, () => state.allEvents.length == 3);
    expect(state.allEvents, hasLength(3));
    expect(find.text('First day at the new studio'), findsOneWidget);
  });

  testWidgets('the free write is a blank box with no prompt; ? explains it', (
    tester,
  ) async {
    await setUpState(tester);
    await tester.pumpWidget(app(const NewEventScreen()));
    final box = find.byKey(const ValueKey('free-write'));
    final field = tester.widget<TextField>(box);
    expect(field.decoration?.labelText, isNull);
    expect(field.decoration?.hintText, isNull);
    expect(field.decoration?.helperText, isNull);

    await tester.tap(find.byTooltip('What is this box for?'));
    await tester.pumpAndSettle();
    expect(find.textContaining('This box is yours'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    // Writing only in the free write is enough to save an event.
    await tester.enterText(box, 'In my own words.');
    await tester.tap(find.text('Save'));
    await settle(tester, () => state.allEvents.length == 3);
    expect(
      state.allEvents.where((e) => e.experience == 'In my own words.'),
      hasLength(1),
    );
  });

  testWidgets('the free write on an event saves as it is typed', (
    tester,
  ) async {
    await setUpState(tester);
    await tester.pumpWidget(app(const EventDetailScreen(eventId: 'lake')));
    final box = find.byKey(const ValueKey('free-write'));
    await tester.ensureVisible(box);
    await tester.enterText(box, 'The cold took my breath.');
    // Saved shortly after typing stops.
    await tester.pump(const Duration(seconds: 1));
    await settle(
      tester,
      () => state.eventById('lake')!.experience == 'The cold took my breath.',
    );
    expect(state.eventById('lake')!.experience, 'The cold took my breath.');
    // The AI's account is untouched.
    expect(
      state.eventById('lake')!.description,
      'The water was copper in the last light.',
    );
  });

  testWidgets('settings: save a key, pick a model, see the account, sign out', (
    tester,
  ) async {
    await setUpState(tester);
    await tester.pumpWidget(app(const SettingsScreen()));
    expect(find.text('me@example.com'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'not-a-key');
    await tester.tap(find.text('Save key'));
    await tester.pumpAndSettle();
    expect(find.textContaining('does not look like'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'sk-ant-test-key');
    await tester.tap(find.text('Save key'));
    await settle(tester, () => state.hasApiKey);
    expect(state.hasApiKey, isTrue);
    expect(find.text('API key saved'), findsWidgets);

    await tester.tap(find.textContaining('Sonnet'));
    await settle(tester, () => state.model == 'claude-sonnet-5-5');
    expect(state.model, 'claude-sonnet-5-5');

    await tester.scrollUntilVisible(find.text('Sign out'), 200);
    await tester.tap(find.text('Sign out'));
    await settle(tester, () => auth.signedOut);
    expect(auth.signedOut, isTrue);
  });

  testWidgets('weather: three videos unlock the lookup, then it shows', (
    tester,
  ) async {
    await setUpState(tester);
    await tester.pumpWidget(
      app(const EventDetailScreen(eventId: 'lake'), videos: _FinishedVideos()),
    );
    await tester.ensureVisible(find.text('Weather (optional)'));
    await tester.pumpAndSettle();
    expect(find.text('0 of 3 watched today'), findsOneWidget);
    for (var i = 1; i <= 3; i++) {
      await tester.ensureVisible(find.text('Watch a video'));
      await tester.tap(find.text('Watch a video'));
      await settle(
        tester,
        () =>
            find.text('Watch a video').evaluate().isEmpty ||
            find.text('$i of 3 watched today').evaluate().isNotEmpty,
      );
    }
    await tester.ensureVisible(find.text('Look up the weather'));
    await tester.tap(find.text('Look up the weather'));
    await settle(tester, () => state.eventById('lake')!.weather != null);
    expect(find.text('Clear sky, 21°C'), findsOneWidget);
    expect(find.text('Weather data by Open-Meteo.com'), findsOneWidget);
  });

  testWidgets('home shows events from this day in earlier years', (
    tester,
  ) async {
    await setUpState(tester);
    final now = DateTime.now();
    final then = DateTime(now.year - 2, now.month, now.day, 9);
    await tester.runAsync(() async {
      await state.events.save(
        LifeEvent(
          id: 'old',
          title: 'First day at the cabin',
          notes: '',
          location: '',
          occurredAt: then,
          createdAt: then,
          updatedAt: then,
        ),
      );
      await state.load();
    });
    await tester.pumpWidget(app(const HomeScreen()));
    await tester.pump();
    expect(find.text('On this day'), findsOneWidget);
    expect(find.text('2 years ago today'), findsOneWidget);
    await tester.tap(find.text('2 years ago today'));
    await tester.pumpAndSettle();
    expect(find.byType(EventDetailScreen), findsOneWidget);
  });
}
