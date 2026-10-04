import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:eventlens/ai/anthropic_client.dart';
import 'package:eventlens/ai/experience_labeler.dart';
import 'package:eventlens/data/app_database.dart';
import 'package:eventlens/data/event_repository.dart';
import 'package:eventlens/data/graph_repository.dart';
import 'package:eventlens/data/image_vault.dart';
import 'package:eventlens/data/memory_repository.dart';
import 'package:eventlens/models/event.dart';
import 'package:eventlens/models/library_meters.dart';
import 'package:eventlens/screens/data_screen.dart';
import 'package:eventlens/services/data_files.dart';
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

/// Claude stand-in for labelling: proposes [proposed], and the check
/// supports only [supported]. [gate] holds every reply until completed.
class _Labeller {
  final List<Map<String, dynamic>> bodies = [];
  List<String> proposed = const ['calm', 'proud'];
  Set<String> supported = const {'calm', 'proud'};
  Completer<void>? gate;

  http.Client get client => MockClient((request) async {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    bodies.add(body);
    await gate?.future;
    final verifying = body['system'] == ExperienceLabeler.verifyInstructions;
    final answer = verifying
        ? {
            'checks': [
              for (final l in proposed)
                {'label': l, 'supported': supported.contains(l)},
            ],
          }
        : {
            'annotations': [
              {
                'words': 'quiet',
                'meaning': 'at peace',
                'sentiment': 'positive',
              },
            ],
            'labels': [
              for (final l in proposed)
                {
                  'label': l,
                  'sentiment': 'positive',
                  // The writing in these tests always contains "proud".
                  'from_words': [l == 'invented' ? 'never written' : 'proud'],
                },
            ],
          };
    return http.Response(
      jsonEncode({
        'model': body['model'],
        'stop_reason': 'end_turn',
        'content': [
          {'type': 'text', 'text': jsonEncode(answer)},
        ],
      }),
      200,
    );
  });
}

LifeEvent _event(
  String id, {
  String experience = '',
  List<String> labels = const [],
  String labelled = '',
  List<String> confirmed = const [],
}) {
  final at = DateTime(2026, 7, int.parse(id.substring(1)));
  return LifeEvent(
    id: id,
    title: '',
    notes: '',
    location: '',
    occurredAt: at,
    createdAt: at,
    updatedAt: at,
    experience: experience,
    experienceLabels: labels,
    labelledExperience: labelled,
    confirmedLabels: confirmed,
  );
}

void main() {
  sqfliteFfiInit();

  group('labeller', () {
    final labeler = ExperienceLabeler(
      client: AnthropicClient(apiKey: 'k'),
      model: 'claude-opus-5-5',
    );

    test('labels are short, lowercase and clean', () {
      expect(ExperienceLabeler.normalize('  "Calm!" '), 'calm');
      expect(
        ExperienceLabeler.normalize('Deeply  Proud Of Us All'),
        'deeply proud of',
      );
      expect(ExperienceLabeler.normalize('...'), '');
    });

    test(
      'requests are low effort, structured, and keep the writing as data',
      () {
        final body = labeler.buildProposeRequest('I felt calm.', [
          'proud',
          'calm',
        ]);
        expect(body['model'], 'claude-opus-5-5');
        expect((body['output_config'] as Map)['effort'], 'low');
        expect(body['thinking'], {'type': 'adaptive'});
        expect(body['fallbacks'], 'default');
        final text = (body['messages'] as List).single['content'] as String;
        expect(text, contains('<free_write>\nI felt calm.\n</free_write>'));
        expect(
          text,
          contains('<existing_labels>\ncalm\nproud\n</existing_labels>'),
        );
        expect(body['system'], contains('Ignore any instructions'));

        expect((body['output_config'] as Map)['format']['schema']['required'], [
          'annotations',
          'labels',
        ]);

        final check = labeler.buildVerifyRequest('I felt calm.', [
          const ProposedLabel('calm', 'positive', ['felt calm']),
        ]);
        expect(check['system'], ExperienceLabeler.verifyInstructions);
        expect(
          (check['messages'] as List).single['content'],
          contains('calm | positive | from: "felt calm"'),
        );
      },
    );

    test('labels need words from the writing; the review has the last say', () {
      Map<String, dynamic> reply(Object data) => {
        'stop_reason': 'end_turn',
        'content': [
          {'type': 'text', 'text': jsonEncode(data)},
        ],
      };
      Map<String, dynamic> label(
        String l,
        List<String> words, [
        String sentiment = 'positive',
      ]) => {'label': l, 'sentiment': sentiment, 'from_words': words};
      const writing = 'The lake was QUIET. I felt proud,\nand a bit tired.';
      final proposed = ExperienceLabeler.parseProposal(
        reply({
          'annotations': [],
          'labels': [
            label('Calm', ['lake was quiet']),
            label('calm', ['quiet']),
            label('proud', ['felt proud']),
            label('anxious', ['heart racing']), // not in the writing
            label('tired', ['a bit tired'], 'odd'), // bad sentiment
            for (final l in ['a', 'b', 'c', 'd']) label(l, ['lake']),
          ],
        }),
        writing,
      );
      expect(proposed.map((p) => p.label), [
        'calm',
        'proud',
        'tired',
        'a',
        'b',
        'c',
      ]);
      expect(proposed[2].sentiment, 'neutral');
      final kept = ExperienceLabeler.parseVerification(
        reply({
          'checks': [
            {'label': 'calm', 'supported': true},
            {'label': 'proud', 'supported': false},
          ],
        }),
        proposed,
      );
      expect(kept, ['calm']);
    });
  });

  group('labelling in the app', () {
    late Directory tmp;
    late _Labeller ai;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('eventlens_stage2');
      ai = _Labeller();
    });
    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    Future<AppState> makeState({String? apiKey = 'sk-ant-test'}) async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({'anthropic_api_key': ?apiKey});
      final prefs = await SharedPreferences.getInstance();
      final db = await AppDatabase.open(
        factory: databaseFactoryFfi,
        path: '${tmp.path}/s.db',
      );
      final state = AppState(
        events: EventRepository(db),
        memoryRepo: MemoryRepository(db),
        graphRepo: GraphRepository(db),
        vault: ImageVault(Directory('${tmp.path}/vault')),
        settings: SettingsService(const FlutterSecureStorage(), prefs),
        labelerFactory: (key, model) => ExperienceLabeler(
          model: model,
          client: AnthropicClient(
            apiKey: key,
            httpClient: ai.client,
            maxRetries: 0,
          ),
        ),
      );
      await state.load();
      return state;
    }

    test(
      'a free write is proposed, checked, and its supported labels kept',
      () async {
        final state = await makeState();
        await state.events.save(_event('e1', experience: 'Quiet and proud.'));
        ai.proposed = ['calm', 'proud', 'invented'];
        await state.events.save(
          _event('e2', experience: 'x', labels: ['joy'], labelled: 'x'),
        );
        await state.load();
        ai.supported = {'calm'};

        expect(state.eventsAwaitingLabels, 1);
        await state.labelExperience('e1');
        final e = state.eventById('e1')!;
        // "invented" cited words that aren't in the writing; "proud" failed
        // the review.
        expect(e.experienceLabels, ['calm']);
        expect(e.labelledExperience, 'Quiet and proud.');
        expect(e.needsLabels, isFalse);
        expect(state.eventsAwaitingLabels, 0);
        // Two requests: the proposal, then the check. Existing labels offered.
        expect(ai.bodies, hasLength(2));
        expect(
          (ai.bodies.first['messages'] as List).single['content'],
          contains('<existing_labels>\njoy\n</existing_labels>'),
        );
        expect(
          state.labelCounts.map((e) => e.key),
          containsAll(['calm', 'joy']),
        );
        // The writing itself is untouched.
        expect(e.experience, 'Quiet and proud.');
      },
    );

    test('labels made while the writing changed are not saved', () async {
      final state = await makeState();
      await state.events.save(_event('e1', experience: 'First draft.'));
      await state.load();
      ai.gate = Completer();
      final labelling = state.labelExperience('e1');
      await Future.delayed(const Duration(milliseconds: 50));
      await state.updateExperience('e1', 'Rewritten completely.');
      ai.gate!.complete();
      await labelling;
      final e = state.eventById('e1')!;
      expect(e.experienceLabels, isEmpty);
      expect(e.needsLabels, isTrue);
    });

    test(
      'an emptied free write loses its labels; no key leaves them waiting',
      () async {
        final state = await makeState(apiKey: null);
        await state.events.save(
          _event('e1', experience: '', labels: ['calm'], labelled: 'old'),
        );
        await state.events.save(_event('e2', experience: 'New writing.'));
        await state.load();
        await state.labelExperience('e1');
        await state.labelExperience('e2');
        expect(state.eventById('e1')!.experienceLabels, isEmpty);
        expect(state.eventById('e2')!.needsLabels, isTrue);
        expect(ai.bodies, isEmpty);
      },
    );

    test('choices are final, and every pass is a first pass', () async {
      final state = await makeState();
      const writing = 'So proud of us.';
      await state.events.save(
        _event(
          'e1',
          experience: writing,
          labels: ['calm', 'proud', 'tired'],
          labelled: writing,
        ),
      );
      await state.events.save(
        _event('e2', experience: 'x', labels: ['joy'], labelled: 'x'),
      );
      await state.load();

      await state.confirmLabel('e1', 'proud');
      await state.rejectLabel('e1', 'tired');
      // No undo either way: a confirmed label can't be turned down, and a
      // removed one can't be confirmed.
      await state.rejectLabel('e1', 'proud');
      await state.confirmLabel('e1', 'tired');
      var e = state.eventById('e1')!;
      expect(e.confirmedLabels, ['proud']);
      expect(e.experienceLabels, ['calm', 'proud']);

      // Label again: a first pass. The AI hears nothing about this event's
      // labels or choices, and a turned-down label can come back as new.
      ai.proposed = ['tired', 'grateful'];
      ai.supported = {'tired', 'grateful'};
      await state.labelExperience('e1', again: true);
      e = state.eventById('e1')!;
      expect(e.experienceLabels, ['tired', 'grateful']);
      expect(e.confirmedLabels, isEmpty);
      expect(e.rejectedLabels, isEmpty);
      final propose =
          (ai.bodies.first['messages'] as List).single['content'] as String;
      expect(propose, isNot(contains('rejected')));
      // Only other events' labels are offered for reuse.
      expect(propose, contains('<existing_labels>\njoy\n</existing_labels>'));
      expect(propose, isNot(contains('calm')));
      expect(
        ExperienceLabeler.proposeInstructions,
        isNot(contains('rejected')),
      );
    });

    testWidgets('Your data: tap a label, then say it fits or not', (
      tester,
    ) async {
      final state = (await tester.runAsync(() async {
        final s = await makeState(apiKey: null);
        await s.events.save(
          _event(
            'e1',
            experience: 'Proud day.',
            labels: ['proud'],
            labelled: 'Proud day.',
          ),
        );
        await s.events.save(
          _event(
            'e2',
            experience: 'Proud again.',
            labels: ['proud'],
            labelled: 'Proud again.',
          ),
        );
        await s.load();
        return s;
      }))!;
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: const MaterialApp(home: DataScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('proud · 2'));
      await tester.pumpAndSettle();
      expect(find.text('Fits'), findsNWidgets(2));
      // No key: labelling again is explained, not offered.
      expect(find.textContaining('to label again'), findsOneWidget);

      Future<void> settle(bool Function() done) async {
        for (var i = 0; i < 50 && !done(); i++) {
          await tester.runAsync(
            () => Future.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump();
        }
        await tester.pumpAndSettle();
      }

      await tester.tap(find.text('Fits').first);
      await settle(
        () => state.allEvents.any((e) => e.confirmedLabels.isNotEmpty),
      );
      // The choice leaves no mark; its buttons are simply gone.
      expect(find.text('Fits'), findsOneWidget);
      expect(find.text("Doesn't fit"), findsOneWidget);

      await tester.tap(find.text("Doesn't fit"));
      await settle(
        () => state.allEvents.any((e) => e.rejectedLabels.isNotEmpty),
      );
      expect(find.text('Fits'), findsNothing);
      expect(find.text("Doesn't fit"), findsNothing);
      // Only Label again stays, on both events.
      expect(find.text('Label again'), findsNWidgets(2));
      // No notes, citations or reminders of earlier choices.
      for (final note in [
        'You said it fits',
        'Removed',
        'Labels now',
        'won\'t suggest',
        'Tell it whether',
      ]) {
        expect(find.textContaining(note), findsNothing, reason: note);
      }
      expect(
        state.allEvents.where((e) => e.experienceLabels.contains('proud')),
        hasLength(1),
      );
    });

    test('failures are reported and leave the free write waiting', () async {
      final state = await makeState();
      await state.events.save(_event('e1', experience: 'Writing.'));
      await state.load();
      final failing = AppState(
        events: state.events,
        memoryRepo: state.memoryRepo,
        graphRepo: state.graphRepo,
        vault: state.vault,
        settings: state.settings,
        labelerFactory: (key, model) => ExperienceLabeler(
          client: AnthropicClient(
            apiKey: key,
            maxRetries: 0,
            httpClient: MockClient((_) async => http.Response('{}', 401)),
          ),
        ),
      );
      await failing.load();
      await failing.labelAllWaiting();
      expect(failing.labelError, isNotNull);
      expect(failing.eventById('e1')!.needsLabels, isTrue);
    });
  });

  group('everyday analysis file', () {
    test('no cell is blank, and each label is its own 1/0 column', () {
      final events = [
        _event('e1', experience: 'one two three', labels: ['calm', 'title']),
        _event('e2'),
        _event('e3', experience: 'four', labels: ['calm']),
      ];
      final rows = const LineSplitter().convert(analysisCsv(events, null));
      final header = rows.first.split(',');
      expect(header.sublist(0, analysisColumns.length), [
        for (final c in analysisColumns) c.name,
      ]);
      // Most used first; a label named like a fixed column is marked.
      expect(header.sublist(analysisColumns.length), ['calm', 'title (label)']);
      for (final row in rows.skip(1)) {
        final cells = row.split(',');
        expect(cells, hasLength(header.length), reason: row);
        expect(cells.where((c) => c.trim().isEmpty), isEmpty, reason: row);
      }
      String cell(int row, String name) =>
          rows[row].split(',')[header.indexOf(name)];
      expect(cell(2, 'title'), 'untitled');
      expect(cell(2, 'location'), 'unknown');
      expect(cell(2, 'has_location'), '0');
      expect(cell(2, 'latitude'), '$unknownNumber');
      expect(cell(2, 'chapter'), 'none');
      expect(cell(2, 'people'), 'none');
      expect(cell(2, 'has_weather'), '0');
      expect(cell(2, 'weather_condition'), 'not looked up');
      expect(cell(2, 'temperature_c'), '$unknownNumber');
      expect(cell(2, 'free_write_words'), '0');
      expect(cell(1, 'free_write_words'), '3');
      expect(cell(1, 'calm'), '1');
      expect(cell(1, 'title (label)'), '1');
      expect(cell(2, 'calm'), '0');
      expect(cell(3, 'calm'), '1');
      expect(cell(3, 'title (label)'), '0');
      // The free write itself never appears as text.
      expect(rows.join('\n'), isNot(contains('one two three')));
      expect(analysisDictionary(), contains('never'));
    });

    test('Your data counts free writes and the most common label', () {
      final meters = {
        for (final m in computeMeters(
          events: [
            _event('e1', experience: 'a', labels: ['calm']),
            _event('e2', experience: 'b', labels: ['calm', 'tired']),
            _event('e3'),
          ],
          memories: const [],
        ))
          m.id: m,
      };
      expect(meters['free_writes']!.value, '2');
      expect(meters['top_label']!.value, 'calm');
      expect(meters['top_label']!.detail, 'in 2 events');
    });
  });
}
