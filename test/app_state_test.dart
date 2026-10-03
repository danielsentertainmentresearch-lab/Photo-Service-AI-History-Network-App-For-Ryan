import 'dart:convert';
import 'dart:io';

import 'package:eventlens/ai/anthropic_client.dart';
import 'package:eventlens/ai/event_describer.dart';
import 'package:eventlens/data/app_database.dart';
import 'package:eventlens/data/event_repository.dart';
import 'package:eventlens/data/image_vault.dart';
import 'package:eventlens/data/memory_repository.dart';
import 'package:eventlens/models/event.dart';
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

  Future<AppState> build({required String? apiKey}) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues(
        apiKey == null ? {} : {'anthropic_api_key': apiKey});
    final db = await AppDatabase.open(
        factory: databaseFactoryFfi, path: '${tmp.path}/test.db');
    final settings = SettingsService(
        const FlutterSecureStorage(), await SharedPreferences.getInstance());
    final s = AppState(
      events: EventRepository(db),
      memoryRepo: MemoryRepository(db),
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
    expect(state.vault.fileFor(event.images.single.fileName).existsSync(),
        isTrue);

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
    expect((body['system'] as List).last['text'],
        contains('The lake is our spot'));
    expect((body['messages'][0]['content'] as List).last['text'],
        contains('Sam and I watched the sunset.'));
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
}
