import 'dart:io';

import 'package:eventlens/app.dart';
import 'package:eventlens/data/app_database.dart';
import 'package:eventlens/data/event_repository.dart';
import 'package:eventlens/data/image_vault.dart';
import 'package:eventlens/data/memory_repository.dart';
import 'package:eventlens/services/settings_service.dart';
import 'package:eventlens/state/app_state.dart';
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
        factory: databaseFactoryFfi, path: '${tmp.path}/w.db');
    final state = AppState(
      events: EventRepository(db),
      memoryRepo: MemoryRepository(db),
      vault: ImageVault(Directory('${tmp.path}/vault')),
      settings: SettingsService(
          const FlutterSecureStorage(), await SharedPreferences.getInstance()),
    );
    await state.load();
    return state;
  }

  testWidgets('first run shows welcome, then the empty timeline',
      (tester) async {
    final tmp = Directory.systemTemp.createTempSync('eventlens_widget');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final state =
        (await tester.runAsync(() => makeState(tmp, onboarded: false)))!;

    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: state, child: const EventLensApp()));
    expect(find.text('Welcome to $appName'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Get started'), 200);
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    expect(find.text('No events yet'), findsOneWidget);
    expect(find.text('Add key'), findsOneWidget);
    expect(find.text('New event'), findsOneWidget);
  });
}
