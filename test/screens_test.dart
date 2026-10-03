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
import 'package:eventlens/services/rewards_service.dart';
import 'package:eventlens/services/settings_service.dart';
import 'package:eventlens/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
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

  Widget app(Widget home) => MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: state),
      ChangeNotifierProvider<AuthService>.value(value: auth),
      ChangeNotifierProvider(create: (_) => BiometricLock(prefs)),
      ChangeNotifierProvider(create: (_) => RingUnlocks(prefs, _NoVideos())),
    ],
    child: MaterialApp(home: home),
  );

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
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
    expect(find.text('Your notes at the time'), findsOneWidget);
    expect(find.text('Remember for next time?'), findsOneWidget);

    await tester.tap(find.byTooltip('Save to memory'));
    await settle(tester);
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
    await settle(tester);
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
    await settle(tester);
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
    await settle(tester);
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
    expect(find.text('Add at least one photo or some notes.'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'What\'s happening?'),
      'First day at the new studio',
    );
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(state.allEvents, hasLength(3));
    expect(find.text('First day at the new studio'), findsOneWidget);
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
    await settle(tester);
    expect(state.hasApiKey, isTrue);
    expect(find.text('API key saved'), findsWidgets);

    await tester.tap(find.textContaining('Sonnet'));
    await settle(tester);
    expect(state.model, 'claude-sonnet-5-5');

    await tester.scrollUntilVisible(find.text('Sign out'), 200);
    await tester.tap(find.text('Sign out'));
    await settle(tester);
    expect(auth.signedOut, isTrue);
  });
}
