import 'dart:io';

import 'package:eventlens/app.dart';
import 'package:eventlens/data/app_database.dart';
import 'package:eventlens/data/event_repository.dart';
import 'package:eventlens/data/graph_repository.dart';
import 'package:eventlens/data/image_vault.dart';
import 'package:eventlens/data/memory_repository.dart';
import 'package:eventlens/models/event.dart';
import 'package:eventlens/models/memory_graph.dart';
import 'package:eventlens/screens/graph_editor_screen.dart';
import 'package:eventlens/screens/graph_screen.dart';
import 'package:eventlens/services/settings_service.dart';
import 'package:eventlens/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  Future<AppState> makeState(Directory tmp, {required bool onboarded}) async {
    SharedPreferences.setMockInitialValues({'onboarded': onboarded});
    FlutterSecureStorage.setMockInitialValues({});
    final db = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: '${tmp.path}/w.db',
    );
    final state = AppState(
      events: EventRepository(db),
      memoryRepo: MemoryRepository(db),
      graphRepo: GraphRepository(db),
      vault: ImageVault(Directory('${tmp.path}/vault')),
      settings: SettingsService(
        const FlutterSecureStorage(),
        await SharedPreferences.getInstance(),
      ),
    );
    await state.load();
    return state;
  }

  testWidgets('first run shows welcome, then the empty timeline', (
    tester,
  ) async {
    final tmp = Directory.systemTemp.createTempSync('eventlens_widget');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final state = (await tester.runAsync(
      () => makeState(tmp, onboarded: false),
    ))!;

    await tester.pumpWidget(
      ChangeNotifierProvider.value(value: state, child: const EventLensApp()),
    );
    expect(find.text('Welcome to $appName'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Get started'), 200);
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    expect(find.text('No events yet'), findsOneWidget);
    expect(find.text('Add key'), findsOneWidget);
    expect(find.text('New event'), findsOneWidget);
  });

  testWidgets('graph screen shows the graph, chapters and AI links', (
    tester,
  ) async {
    final tmp = Directory.systemTemp.createTempSync('eventlens_graph');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final state = (await tester.runAsync(() async {
      final s = await makeState(tmp, onboarded: true);
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
          ),
        );
      }
      await s.graphRepo.replace(
        GraphSnapshot(
          id: 'g1',
          createdAt: DateTime(2026, 6, 4),
          eventCount: 3,
          model: 'claude-opus-5-5',
          overview: 'Early summer on the trails.',
          chapters: const [
            TimelineChapter(
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
      await s.load();
      return s;
    }))!;

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: GraphScreen()),
      ),
    );
    // Layout runs in a background isolate.
    await tester.runAsync(() => Future.delayed(const Duration(seconds: 2)));
    await tester.pump();

    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.text('Person'), findsOneWidget); // filter chip
    expect(
      find.textContaining('The AI rebuilds after 10 more described photos'),
      findsOneWidget,
    );

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

  Future<AppState> describedState(WidgetTester tester, Directory tmp) async =>
      (await tester.runAsync(() async {
        final s = await makeState(tmp, onboarded: true);
        for (var d = 1; d <= 3; d++) {
          final at = DateTime(2026, 6, d);
          await s.events.save(
            LifeEvent(
              id: 'e$d',
              title: 'Hike $d',
              notes: '',
              location: '',
              occurredAt: at,
              createdAt: at,
              updatedAt: at,
              summary: 'Day $d.',
              description: 'Account $d.',
              status: EventStatus.described,
            ),
          );
        }
        await s.load();
        return s;
      }))!;

  Future<void> pumpEditor(WidgetTester tester, AppState state) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
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

  testWidgets('editor builds a timeline by hand: group, chapter, colour, '
      'events, connection', (tester) async {
    final tmp = Directory.systemTemp.createTempSync('eventlens_editor');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final state = await describedState(tester, tmp);
    expect(state.graphSnapshot, isNull);
    await pumpEditor(tester, state);

    await tester.tap(find.text('Add group'));
    await tester.pumpAndSettle();
    expect(find.text(untitledGroupName), findsOneWidget);

    await tester.tap(find.text('Add chapter'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Title'),
      'Mountain month',
    );
    // Pick the fourth colour swatch (the "no colour" dot is labelled
    // differently, so index 3 is chapterColors[3]).
    await tester.tap(find.bySemanticsLabel('Colour').at(3));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(untitledGroupName).last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Choose events'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hike 1'));
    await tester.tap(find.text('Hike 3'));
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add connection'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'How they connect'),
      'same trail',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();

    final saved = state.graphSnapshot!;
    expect(saved.groups.single.name, untitledGroupName);
    final chapter = saved.chapters.single;
    expect(chapter.title, 'Mountain month');
    expect(chapter.color, chapterColors[3]);
    expect(chapter.groupId, saved.groups.single.id);
    expect(chapter.eventIds, ['e1', 'e3']);
    expect(saved.links.single.relation, 'same trail');
    expect(saved.links.single.manual, isTrue);
    expect(state.graph.node('event:e1')!.ringColor, chapterColors[3]);
    expect(state.graph.node('event:e2')!.ringColor, isNull);
    expect(find.text('open'), findsOneWidget); // editor closed
  });

  testWidgets('leaving the editor with unsaved changes asks first', (
    tester,
  ) async {
    final tmp = Directory.systemTemp.createTempSync('eventlens_discard');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final state = await describedState(tester, tmp);
    await pumpEditor(tester, state);

    await tester.tap(find.text('Add theme'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(state.graphSnapshot, isNull);
  });
}
