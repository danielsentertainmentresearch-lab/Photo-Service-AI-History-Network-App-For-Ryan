// Renders phone screenshots of the main screens using sample data.
//
// Run:  flutter test tool/screenshots_test.dart
// Output: store/screenshots/*.png (1080×1920, Play Store phone size)
//
// It lives outside test/ so it doesn't run with the normal suite.
//
// The sample photos are generated placeholders. Replace them with real
// screenshots from a device before publishing, if possible.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';
import 'dart:ui' as ui;

import 'package:eventlens/data/app_database.dart';
import 'package:eventlens/data/event_repository.dart';
import 'package:eventlens/data/graph_repository.dart';
import 'package:eventlens/data/image_vault.dart';
import 'package:eventlens/data/memory_repository.dart';
import 'package:eventlens/models/event.dart';
import 'package:eventlens/models/memory_graph.dart';
import 'package:eventlens/screens/event_detail_screen.dart';
import 'package:eventlens/screens/auth_screen.dart';
import 'package:eventlens/screens/graph_editor_screen.dart';
import 'package:eventlens/screens/graph_screen.dart';
import 'package:eventlens/screens/home_screen.dart';
import 'package:eventlens/screens/memory_screen.dart';
import 'package:eventlens/screens/tutorial_screen.dart';
import 'package:eventlens/services/auth_service.dart';
import 'package:eventlens/services/rewards_service.dart';
import 'package:eventlens/services/settings_service.dart';
import 'package:eventlens/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _size = Size(1080, 1920);
const _ratio = 2.625;

Future<void> _loadFonts() async {
  final fonts =
      '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final bytes = File('$fonts/$f').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  await load('Roboto', [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ]);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

/// A soft two-colour gradient standing in for a photo.
File _photo(Directory dir, String name, int c1, int c2) {
  final image = img.Image(width: 480, height: 360);
  for (var y = 0; y < image.height; y++) {
    final t = y / image.height;
    int mix(int shift) =>
        (((c1 >> shift) & 0xFF) * (1 - t) + ((c2 >> shift) & 0xFF) * t).round();
    for (var x = 0; x < image.width; x++) {
      image.setPixelRgb(x, y, mix(16), mix(8), mix(0));
    }
  }
  final file = File('${dir.path}/$name.jpg')
    ..writeAsBytesSync(img.encodeJpg(image));
  return file;
}

Future<AppState> _sampleState(Directory tmp) async {
  sqfliteFfiInit();
  // Two colours unlocked (the free one plus one), so rings show variety.
  SharedPreferences.setMockInitialValues({'ring_unlocked_count': 2});
  FlutterSecureStorage.setMockInitialValues({
    'anthropic_api_key': 'sk-ant-sample',
  });
  final db = await AppDatabase.open(
    factory: databaseFactoryFfi,
    path: '${tmp.path}/shots.db',
  );
  final vault = ImageVault(Directory('${tmp.path}/vault'));
  final state = AppState(
    events: EventRepository(db),
    memoryRepo: MemoryRepository(db),
    graphRepo: GraphRepository(db),
    vault: vault,
    settings: SettingsService(
      const FlutterSecureStorage(),
      await SharedPreferences.getInstance(),
    ),
  );

  final samples = [
    (
      'lake',
      DateTime(2026, 6, 6, 20, 10),
      'Sunset swim at Fallen Leaf Lake',
      'Sam talked me into one last swim before dark. Water freezing, both of us laughing too hard to swim properly.',
      'Sam and I swam at Fallen Leaf Lake as the sun went down, then dried off on the warm granite.',
      'The light was already going amber when Sam dared me in. The lake lay perfectly still, a sheet of hammered copper reflecting the ridge, and the granite slabs along the shore still held the day\'s heat under my palms. The first photo catches Sam mid-leap, arms flung wide, a blur of pale skin against the darkening water…',
      ['Sam'],
      ['Fallen Leaf Lake'],
      ['swimming', 'sunset', 'summer'],
      0xF4A261,
      0x264653,
    ),
    (
      'market',
      DateTime(2026, 6, 13, 10, 30),
      'Saturday market with Mum',
      'Mum bought far too many peaches. She told the story about her first job at the market again.',
      'Mum and I wandered the farmers market; she retold the story of her first job there.',
      'The market smelled of ripe stone fruit and coffee. Mum moved from stall to stall with the confidence of someone who had worked here once…',
      ['Mum'],
      ['Riverside Farmers Market'],
      ['family', 'food'],
      0xE9C46A,
      0xE76F51,
    ),
    (
      'gig',
      DateTime(2026, 6, 20, 22, 0),
      'Lowtide\'s first headline show',
      'Sam\'s band headlined for the first time! Packed room, he broke a drumstick in the encore.',
      'Sam\'s band Lowtide headlined for the first time to a packed room at The Anchor.',
      'Blue and magenta stage light washed over the crowd as Lowtide opened with their loudest song. From where I stood near the bar, I could see Sam behind the kit…',
      ['Sam'],
      ['The Anchor'],
      ['music', 'milestone'],
      0x6A4C93,
      0x1982C4,
    ),
    (
      'lake2',
      DateTime(2026, 7, 4, 19, 45),
      'Back at the lake for the Fourth',
      'Same spot as last month. Sam brought the band. Fireworks over the water.',
      'We returned to Fallen Leaf Lake with Sam and the band to watch fireworks over the water.',
      'A month after our sunset swim we were back on the same granite slab, this time with the whole band and a cooler of drinks…',
      ['Sam'],
      ['Fallen Leaf Lake'],
      ['summer', 'fireworks', 'friends'],
      0x2A9D8F,
      0x0B1D51,
    ),
  ];

  for (final s in samples) {
    final photos = [
      _photo(tmp, '${s.$1}-1', s.$10, s.$11),
      _photo(tmp, '${s.$1}-2', s.$11, s.$10),
    ];
    final e = await state.createEvent(
      title: s.$3,
      notes: s.$4,
      location: s.$8.first,
      occurredAt: s.$2,
      photos: photos,
    );
    await state.events.update(
      e.copyWith(
        summary: s.$5,
        description: s.$6,
        people: s.$7,
        places: s.$8,
        tags: s.$9,
        status: EventStatus.described,
        model: 'claude-opus-5-5',
        suggestions: s.$1 == 'gig'
            ? const [
                MemorySuggestion(
                  kind: 'ongoing',
                  content: 'Sam drums in a band called Lowtide',
                ),
              ]
            : const [],
      ),
    );
  }
  await state.load();
  await state.addMemory('person', 'Sam is my younger brother');
  await state.addMemory(
    'place',
    'Fallen Leaf Lake is where our family camped every summer',
  );
  await state.addMemory('preference', 'Describe light and colour in detail');
  final ids = [for (final e in state.allEvents.reversed) e.id];
  await state.graphRepo.replace(
    GraphSnapshot(
      id: 'sample',
      createdAt: DateTime(2026, 7, 5, 9),
      eventCount: 4,
      model: 'claude-opus-5-5',
      overview:
          'An early summer built around Sam: a dare at the lake, his band\'s '
          'breakthrough night, and a return to the same shore a month later, '
          'with a quiet morning with Mum in between.',
      books: const [Book(id: 'b1', title: 'Summer 2026')],
      rings: {ids[0]: 0, ids[3]: 1},
      chapters: [
        TimelineChapter(
          id: 'c1',
          bookId: 'b1',
          title: 'First weeks of summer',
          summary: 'The lake and the market: slow weekends with family.',
          eventIds: ids.sublist(0, 2),
        ),
        TimelineChapter(
          id: 'c2',
          bookId: 'b1',
          title: 'Lowtide\'s summer',
          summary: 'Sam\'s band takes off and the lake becomes a tradition.',
          eventIds: ids.sublist(2),
        ),
      ],
      links: [
        EventLink(
          fromEventId: ids[0],
          toEventId: ids[3],
          relation: 'same granite slab, one month later',
        ),
        EventLink(
          fromEventId: ids[2],
          toEventId: ids[3],
          relation: 'the band came along to celebrate',
        ),
      ],
      themes: [
        StoryTheme(
          name: 'Summers with Sam',
          description:
              'Dares, music and evenings on the water with my brother.',
          eventIds: [ids[0], ids[2], ids[3]],
        ),
        StoryTheme(
          name: 'Family roots',
          description: 'Places tied to how Mum and I grew up.',
          eventIds: [ids[0], ids[1]],
        ),
      ],
    ),
  );
  await state.load();
  return state;
}

late SharedPreferences prefs;

/// Signed-in stand-in for the screenshots.
class _ShotAuth extends LocalReviewAuthService {
  _ShotAuth() : super(prefs);

  @override
  AppUser? get user => const AppUser(uid: 'u', label: 'sam@example.com');

  @override
  bool get available => true;
}

class _NoVideos implements RewardedVideoProvider {
  @override
  Future<bool> showRewardedVideo() async => false;
}

void main() {
  final out = Directory('store/screenshots')..createSync(recursive: true);
  late Directory tmp;
  late AppState state;

  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('eventlens_shots');
  });
  tearDownAll(() => tmp.deleteSync(recursive: true));

  Future<void> shoot(
    WidgetTester tester,
    String name,
    Widget screen, {
    Future<void> Function()? before,
  }) async {
    tester.view.physicalSize = _size;
    tester.view.devicePixelRatio = _ratio;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: state),
            ChangeNotifierProvider<AuthService>.value(value: _ShotAuth()),
            ChangeNotifierProvider(create: (_) => BiometricLock(prefs)),
            ChangeNotifierProvider(
              create: (_) => RingUnlocks(prefs, _NoVideos()),
            ),
            ChangeNotifierProvider(
              create: (_) => WeatherPass(prefs, _NoVideos()),
            ),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF3F51B5),
              ),
              useMaterial3: true,
            ),
            home: screen,
          ),
        ),
      ),
    );
    // Decode photo thumbnails for real (the test clock doesn't do I/O).
    await tester.runAsync(() async {
      for (final element in find.byType(Image).evaluate()) {
        await precacheImage(
          (element.widget as Image).image,
          element,
        ).timeout(const Duration(seconds: 5), onTimeout: () {});
      }
    });
    // Let the graph layout isolate finish.
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future.delayed(const Duration(seconds: 1)));
      await tester.pump();
    }
    if (before != null) await before();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: _ratio);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('${out.path}/$name.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  testWidgets('screenshots', (tester) async {
    // Tests draw elevation as solid outlines by default; draw real shadows.
    debugDisableShadows = false;
    await tester.runAsync(_loadFonts);
    state = (await tester.runAsync(() => _sampleState(tmp)))!;
    prefs = (await tester.runAsync(SharedPreferences.getInstance))!;

    await shoot(tester, '0_tutorial', const TutorialScreen());
    await shoot(tester, '0_account', const AuthScreen());
    await shoot(tester, '1_timeline', const HomeScreen());
    final gig = state.allEvents.firstWhere((e) => e.title.contains('Lowtide'));
    await shoot(tester, '2_event', EventDetailScreen(eventId: gig.id));
    await shoot(tester, '3_graph', const GraphScreen());
    await shoot(
      tester,
      '4_chapters',
      const GraphScreen(),
      before: () async {
        await tester.tap(find.text('Chapters'));
      },
    );
    await shoot(tester, '5_memory', const MemoryScreen());
    await shoot(tester, '6_books_and_rings', const GraphEditorScreen());
    await shoot(
      tester,
      '7_unlock_colour',
      const GraphEditorScreen(),
      before: () async {
        final locked = find.bySemanticsLabel('Locked ring colour').first;
        await tester.ensureVisible(locked);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(locked);
      },
    );
    debugDisableShadows = true;
  });
}
