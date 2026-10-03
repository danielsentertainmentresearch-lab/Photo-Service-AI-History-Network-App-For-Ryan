import 'dart:io';

import 'package:eventlens/ai/graph_builder.dart';
import 'package:eventlens/app.dart';
import 'package:eventlens/data/app_database.dart';
import 'package:eventlens/data/event_repository.dart';
import 'package:eventlens/data/graph_repository.dart';
import 'package:eventlens/data/image_vault.dart';
import 'package:eventlens/data/memory_repository.dart';
import 'package:eventlens/models/event.dart';
import 'package:eventlens/models/memory_graph.dart';
import 'package:eventlens/models/ring_palette.dart';
import 'package:eventlens/screens/graph_editor_screen.dart';
import 'package:eventlens/screens/graph_screen.dart';
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

/// Accepts any email sign-up, like a working account backend.
class _FakeAuth extends AuthService {
  AppUser? _user;

  @override
  AppUser? get user => _user;
  @override
  bool get available => true;

  @override
  Future<void> signUpWithEmail(String email, String password) async {
    _user = AppUser(uid: 'u1', label: email);
    notifyListeners();
  }

  @override
  Future<void> signInWithEmail(String email, String password) =>
      signUpWithEmail(email, password);
  @override
  Future<String> sendPhoneCode(String phone) async => 'verification';
  @override
  Future<void> signUpWithPhone({
    required String phone,
    required String verificationId,
    required String smsCode,
    required String password,
  }) => signUpWithEmail(phone, password);
  @override
  Future<void> signInWithPhone(String phone, String password) =>
      signUpWithEmail(phone, password);
  @override
  Future<void> signInWithGoogle() => signUpWithEmail('g@example.com', '');
  @override
  Future<void> sendPasswordReset(String email) async {}
  @override
  Future<void> signOut() async {
    _user = null;
    notifyListeners();
  }

  @override
  Future<void> deleteAccount() => signOut();
}

class _FakeVideos implements RewardedVideoProvider {
  int shown = 0;

  @override
  Future<bool> showRewardedVideo() async {
    shown++;
    return true;
  }
}

void main() {
  sqfliteFfiInit();

  late _FakeVideos videos;

  Future<(AppState, SharedPreferences)> makeState(Directory tmp) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: '${tmp.path}/w.db',
    );
    final state = AppState(
      events: EventRepository(db),
      memoryRepo: MemoryRepository(db),
      graphRepo: GraphRepository(db),
      vault: ImageVault(Directory('${tmp.path}/vault')),
      settings: SettingsService(const FlutterSecureStorage(), prefs),
    );
    await state.load();
    return (state, prefs);
  }

  /// Three described events and, unless [unlocked] is false, an AI graph.
  Future<(AppState, SharedPreferences)> graphState(
    WidgetTester tester,
    Directory tmp, {
    bool unlocked = true,
  }) async => (await tester.runAsync(() async {
    final (s, prefs) = await makeState(tmp);
    for (var d = 1; d <= 3; d++) {
      final at = DateTime(2026, 6, d);
      await s.events.save(
        LifeEvent(
          id: 'e$d',
          title: 'Hike $d',
          notes: 'with Sam',
          location: '',
          occurredAt: at,
          createdAt: at,
          updatedAt: at,
          summary: 'Hiking day $d.',
          description: 'A long account of hike $d.',
          people: const ['Sam'],
          status: EventStatus.described,
          images: [
            EventImage(
              id: 'i$d',
              eventId: 'e$d',
              fileName: 'p$d.jpg',
              position: 0,
            ),
          ],
        ),
      );
    }
    if (unlocked) {
      await s.graphRepo.replace(
        GraphSnapshot(
          id: 'g1',
          createdAt: DateTime(2026, 6, 4),
          eventCount: 3,
          photoCount: 3,
          model: 'claude-opus-5-5',
          overview: 'Early summer on the trails.',
          chapters: const [
            TimelineChapter(
              id: 'c1',
              title: 'Trail weeks',
              summary: 'Three hikes.',
              eventIds: ['e1', 'e2', 'e3'],
            ),
          ],
          links: const [
            EventLink(
              fromEventId: 'e1',
              toEventId: 'e3',
              relation: 'same summit',
            ),
          ],
          themes: const [
            StoryTheme(
              name: 'Hiking with Sam',
              description: 'Weekend climbs.',
              eventIds: ['e1', 'e2', 'e3'],
            ),
          ],
        ),
      );
    }
    await s.load();
    return (s, prefs);
  }))!;

  Widget wrap(
    AppState state,
    SharedPreferences prefs,
    Widget child, {
    AuthService? auth,
  }) => MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: state),
      ChangeNotifierProvider<AuthService>.value(value: auth ?? _FakeAuth()),
      ChangeNotifierProvider(create: (_) => BiometricLock(prefs)),
      ChangeNotifierProvider(create: (_) => RingUnlocks(prefs, videos)),
    ],
    child: child,
  );

  setUp(() => videos = _FakeVideos());

  testWidgets('without an account only the tutorial is available', (
    tester,
  ) async {
    final tmp = Directory.systemTemp.createTempSync('eventlens_tutorial');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final (state, prefs) = (await tester.runAsync(() => makeState(tmp)))!;
    final auth = _FakeAuth();
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      wrap(state, prefs, const EventLensApp(), auth: auth),
    );
    expect(find.text('Welcome to $appName'), findsOneWidget);
    expect(find.text('New event'), findsNothing);

    // Walk through every tutorial step to the account requirement.
    while (find.text('Next').evaluate().isNotEmpty) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }
    expect(find.textContaining('account is needed'), findsOneWidget);
    await tester.tap(find.text('Create your account'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'me@example.com',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Password'), 'short');
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();
    expect(find.textContaining('at least 8 characters'), findsWidgets);
    expect(auth.user, isNull);

    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      'long enough',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    // Sign-up checks for biometrics through a platform call: let it finish.
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(auth.user!.label, 'me@example.com');
    expect(find.text('No events yet'), findsOneWidget);
    expect(find.text('New event'), findsOneWidget);
  });

  testWidgets('the graph stays locked until 10 photos are described', (
    tester,
  ) async {
    final tmp = Directory.systemTemp.createTempSync('eventlens_locked');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final (state, prefs) = await graphState(tester, tmp, unlocked: false);

    await tester.pumpWidget(
      wrap(state, prefs, const MaterialApp(home: GraphScreen())),
    );
    expect(find.text('Your graph is on its way'), findsOneWidget);
    expect(
      find.text('3 of $graphUnlockPhotos photos described'),
      findsOneWidget,
    );
    // Nothing to edit or rebuild before the graph exists.
    expect(find.byTooltip('Books & rings'), findsNothing);
    expect(find.textContaining('Rebuild'), findsNothing);
  });

  testWidgets('graph screen shows the graph and the AI chapters read-only', (
    tester,
  ) async {
    final tmp = Directory.systemTemp.createTempSync('eventlens_graph');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final (state, prefs) = await graphState(tester, tmp);

    await tester.pumpWidget(
      wrap(state, prefs, const MaterialApp(home: GraphScreen())),
    );
    // Layout runs in a background isolate.
    await tester.runAsync(() => Future.delayed(const Duration(seconds: 2)));
    await tester.pump();

    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.text('Person'), findsOneWidget); // filter chip
    expect(
      find.textContaining('adds new events as you describe'),
      findsOneWidget,
    );
    expect(find.textContaining('Rebuild'), findsNothing);

    await tester.tap(find.text('Chapters'));
    await tester.pumpAndSettle();
    expect(find.text('Trail weeks'), findsOneWidget);
    expect(find.text('Early summer on the trails.'), findsOneWidget);
    expect(find.text('Hiking with Sam'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('same summit'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('same summit'), findsOneWidget);
  });

  Future<void> pumpEditor(
    WidgetTester tester,
    AppState state,
    SharedPreferences prefs,
  ) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      wrap(
        state,
        prefs,
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const GraphEditorScreen()),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('books & rings: title a book, place a chapter, ring an event, '
      'unlock a colour', (tester) async {
    final tmp = Directory.systemTemp.createTempSync('eventlens_editor');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final (state, prefs) = await graphState(tester, tmp);
    await pumpEditor(tester, state, prefs);

    // The AI's chapter is shown but can't be edited.
    expect(find.text('Written by the AI'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Trail weeks'), findsNothing);

    await tester.tap(find.text('Add book'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Summer of hikes');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Summer of hikes'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Summer of hikes').last);
    await tester.pumpAndSettle();

    // Free colour on the first event.
    await tester.tap(find.bySemanticsLabel('Ring colour').first);
    await tester.pumpAndSettle();

    // A locked colour opens the unlock sheet; 5 videos unlock it.
    await tester.tap(find.bySemanticsLabel('Locked ring colour').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Watch 5 short videos'), findsOneWidget);
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.text('Watch a video'));
      await tester.pumpAndSettle();
    }
    expect(videos.shown, 5);
    expect(find.textContaining('Unlocked!'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10)); // close the sheet
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Ring colour'), findsNWidgets(2 * 3));

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();

    final graph = state.graphSnapshot!;
    expect(graph.books.single.title, 'Summer of hikes');
    expect(graph.chapters.single.bookId, graph.books.single.id);
    expect(graph.rings, {'e1': 0});
    expect(graph.chapters.single.title, 'Trail weeks');
    expect(state.graph.node('event:e1')!.ringColor, ringPalette[0]);
    expect(find.text('open'), findsOneWidget); // editor closed
  });

  testWidgets('leaving with unsaved changes asks first', (tester) async {
    final tmp = Directory.systemTemp.createTempSync('eventlens_discard');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final (state, prefs) = await graphState(tester, tmp);
    await pumpEditor(tester, state, prefs);

    await tester.tap(find.bySemanticsLabel('Ring colour').first);
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(state.graphSnapshot!.rings, isEmpty);
  });
}
