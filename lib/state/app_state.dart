import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../ai/anthropic_client.dart';
import '../ai/event_describer.dart';
import '../ai/graph_builder.dart';
import '../data/event_repository.dart';
import '../data/graph_repository.dart';
import '../data/image_vault.dart';
import '../data/memory_repository.dart';
import '../models/event.dart';
import '../models/memory_graph.dart';
import '../models/memory_item.dart';
import '../services/settings_service.dart';

typedef DescriberFactory = EventDescriber Function(
  String apiKey,
  String model,
  String effort,
);

typedef GraphBuilderFactory = GraphBuilder Function(
  String apiKey,
  String model,
  String effort,
);

GraphBuilder _defaultGraphBuilder(String apiKey, String model, String effort) =>
    GraphBuilder(
      client: AnthropicClient(apiKey: apiKey),
      model: model,
      effort: effort,
    );

EventDescriber _defaultDescriber(String apiKey, String model, String effort) =>
    EventDescriber(
      client: AnthropicClient(apiKey: apiKey),
      model: model,
      effort: effort,
    );

/// Single source of truth for the UI.
class AppState extends ChangeNotifier {
  final EventRepository events;
  final MemoryRepository memoryRepo;
  final GraphRepository graphRepo;
  final ImageVault vault;
  final SettingsService settings;
  final DescriberFactory describerFactory;
  final GraphBuilderFactory graphBuilderFactory;
  final Uuid _uuid = const Uuid();

  AppState({
    required this.events,
    required this.memoryRepo,
    required this.graphRepo,
    required this.vault,
    required this.settings,
    this.describerFactory = _defaultDescriber,
    this.graphBuilderFactory = _defaultGraphBuilder,
  });

  static const int maxPhotosPerEvent = 10;

  List<LifeEvent> _events = const [];
  List<MemoryItem> _memories = const [];
  bool _hasApiKey = false;
  bool _loaded = false;
  GraphSnapshot? _graph;
  bool _graphBuilding = false;
  String? _graphError;

  List<LifeEvent> get allEvents => _events;
  List<MemoryItem> get memories => _memories;
  bool get hasApiKey => _hasApiKey;
  bool get loaded => _loaded;
  String get model => settings.model;
  String get effort => settings.effort;

  GraphSnapshot? get graphSnapshot => _graph;
  bool get graphBuilding => _graphBuilding;
  String? get graphError => _graphError;
  int get graphEvery => settings.graphEvery;
  int get describedCount => _events.where((e) => e.hasAccount).length;

  /// The knowledge graph of everything recorded so far.
  GraphData get graph =>
      buildGraph(events: _events, memories: _memories, snapshot: _graph);

  int get describedPhotos => describedPhotoCount(_events);

  /// Photos in newly described events still needed before the AI next
  /// rebuilds the timeline automatically, or null when that's turned off.
  int? get photosUntilNextGraph {
    if (graphEvery == 0) return null;
    final since = describedPhotos - (_graph?.photoCount ?? 0);
    return max(graphEvery - since, 0);
  }

  LifeEvent? eventById(String id) {
    for (final e in _events) {
      if (e.id == id) return e;
    }
    return null;
  }

  Future<void> load() async {
    await events.recoverInterrupted();
    _hasApiKey = ((await settings.readApiKey()) ?? '').isNotEmpty;
    _graph = await graphRepo.latest();
    await _reload();
    _loaded = true;
    notifyListeners();
  }

  Future<void> _reload() async {
    _events = await events.all();
    _memories = await memoryRepo.all();
    notifyListeners();
  }

  // ---- Events ---------------------------------------------------------------

  /// Copies the picked photos into the vault and stores the event as a draft.
  Future<LifeEvent> createEvent({
    required String title,
    required String notes,
    required String location,
    required DateTime occurredAt,
    required List<File> photos,
  }) async {
    final id = _uuid.v4();
    final images = <EventImage>[];
    for (var i = 0; i < photos.length && i < maxPhotosPerEvent; i++) {
      final ext = p.extension(photos[i].path).toLowerCase();
      final fileName = '${_uuid.v4()}${ext.isEmpty ? '.jpg' : ext}';
      await vault.import(photos[i], fileName);
      images.add(
        EventImage(
          id: _uuid.v4(),
          eventId: id,
          fileName: fileName,
          position: i,
        ),
      );
    }
    final now = DateTime.now();
    final event = LifeEvent(
      id: id,
      title: title.trim(),
      notes: notes.trim(),
      location: location.trim(),
      occurredAt: occurredAt,
      createdAt: now,
      updatedAt: now,
      images: images,
    );
    await events.save(event);
    await _reload();
    return event;
  }

  Future<void> updateEventDetails(
    LifeEvent event, {
    String? title,
    String? notes,
    String? location,
    DateTime? occurredAt,
  }) async {
    await events.update(
      event.copyWith(
        title: title?.trim(),
        notes: notes?.trim(),
        location: location?.trim(),
        occurredAt: occurredAt,
        updatedAt: DateTime.now(),
      ),
    );
    await _reload();
  }

  Future<void> updateDescription(LifeEvent event, String description) async {
    await events.update(
      event.copyWith(
        description: description.trim(),
        updatedAt: DateTime.now(),
      ),
    );
    await _reload();
  }

  Future<void> deleteEvent(LifeEvent event) async {
    await events.delete(event.id);
    for (final image in event.images) {
      await vault.remove(image.fileName);
    }
    await _reload();
  }

  /// Asks the AI for the event's account. Progress and failures are stored
  /// on the event itself, so the UI just watches its status.
  Future<void> describeEvent(String eventId) async {
    final event = await events.byId(eventId);
    if (event == null || event.status == EventStatus.describing) return;

    final apiKey = await settings.readApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      await events.update(
        event.copyWith(
          status: EventStatus.failed,
          error: 'Add your Anthropic API key in Settings first.',
        ),
      );
      await _reload();
      return;
    }

    await events.update(
      event.copyWith(status: EventStatus.describing, clearError: true),
    );
    await _reload();

    try {
      final jpegs = <Uint8List>[];
      for (final image in event.images) {
        jpegs.add(await vault.jpegForAi(image.fileName));
      }
      final describer = describerFactory(
        apiKey,
        settings.model,
        settings.effort,
      );
      final account = await describer.describe(
        event: event,
        jpegs: jpegs,
        memories: _memories,
        history: _events,
      );
      await events.update(
        event.copyWith(
          title: event.title.isEmpty ? account.title : event.title,
          summary: account.summary,
          description: account.description,
          people: account.people,
          places: account.places,
          tags: account.tags,
          suggestions: _withoutKnown(account.memorySuggestions),
          status: EventStatus.described,
          clearError: true,
          model: account.model,
          updatedAt: DateTime.now(),
        ),
      );
    } catch (e) {
      final message = e is AnthropicException || e is FormatException
          ? e.toString()
          : 'Something went wrong: $e';
      await events.update(
        event.copyWith(status: EventStatus.failed, error: message),
      );
    }
    await _reload();
    if (eventById(eventId)?.status == EventStatus.described &&
        photosUntilNextGraph == 0 &&
        describedCount >= 2) {
      await buildGraphNow();
    }
  }

  /// Asks the AI to organise all described events into chapters, links and
  /// themes. Runs automatically every [graphEvery] described photos, or on
  /// demand from the graph screen.
  Future<void> buildGraphNow() async {
    if (_graphBuilding) return;
    if (describedCount < 2) {
      _graphError = 'Describe at least two events first.';
      notifyListeners();
      return;
    }
    final apiKey = await settings.readApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      _graphError = 'Add your Anthropic API key in Settings first.';
      notifyListeners();
      return;
    }
    _graphBuilding = true;
    _graphError = null;
    notifyListeners();
    try {
      final builder = graphBuilderFactory(
        apiKey,
        settings.model,
        settings.effort,
      );
      final fresh = await builder.build(_events, _memories);
      // Keep the user's groups, colours, edited wording and own links/themes.
      final merged = GraphSnapshot.mergeRebuild(
        _graph,
        fresh,
      ).sanitized(_events.map((e) => e.id).toSet());
      await graphRepo.replace(merged);
      _graph = merged;
    } catch (e) {
      _graphError = e is AnthropicException
          ? e.toString()
          : 'Could not build the timeline: $e';
    } finally {
      _graphBuilding = false;
      notifyListeners();
    }
  }

  List<MemorySuggestion> _withoutKnown(List<MemorySuggestion> suggestions) {
    final known = _memories.map((m) => m.content.toLowerCase().trim()).toSet();
    return suggestions
        .where((s) => !known.contains(s.content.toLowerCase().trim()))
        .toList();
  }

  // ---- Memory ---------------------------------------------------------------

  Future<void> addMemory(
    String kind,
    String content, {
    String source = 'user',
    String? eventId,
  }) async {
    if (content.trim().isEmpty) return;
    await memoryRepo.save(
      MemoryItem(
        id: _uuid.v4(),
        kind: kind,
        content: content.trim(),
        source: source,
        eventId: eventId,
        createdAt: DateTime.now(),
      ),
    );
    await _reload();
  }

  Future<void> updateMemory(
    MemoryItem item,
    String kind,
    String content,
  ) async {
    await memoryRepo.save(item.copyWith(kind: kind, content: content.trim()));
    await _reload();
  }

  Future<void> deleteMemory(MemoryItem item) async {
    await memoryRepo.delete(item.id);
    await _reload();
  }

  /// Promotes an AI suggestion into long-term memory.
  Future<void> acceptSuggestion(LifeEvent event, MemorySuggestion s) async {
    await addMemory(s.kind, s.content, source: 'ai', eventId: event.id);
    await dismissSuggestion(event, s);
  }

  Future<void> dismissSuggestion(LifeEvent event, MemorySuggestion s) async {
    final current = await events.byId(event.id);
    if (current == null) return;
    await events.update(
      current.copyWith(
        suggestions: current.suggestions
            .where((x) => x.content != s.content)
            .toList(),
      ),
    );
    await _reload();
  }

  // ---- Settings -------------------------------------------------------------

  Future<void> setApiKey(String? key) async {
    await settings.writeApiKey(key);
    _hasApiKey = ((await settings.readApiKey()) ?? '').isNotEmpty;
    notifyListeners();
  }

  Future<void> setModel(String value) async {
    await settings.setModel(value);
    notifyListeners();
  }

  /// Saves the user's hand edits to the timeline graph. The snapshot is
  /// repaired first (see [GraphSnapshot.sanitized]) so a bad edit can never
  /// leave data the app can't display.
  Future<void> saveGraph(GraphSnapshot edited) async {
    final clean = edited.sanitized(_events.map((e) => e.id).toSet());
    await graphRepo.replace(clean);
    _graph = clean;
    _graphError = null;
    notifyListeners();
  }

  Future<void> setGraphEvery(int value) async {
    await settings.setGraphEvery(value);
    notifyListeners();
  }

  Future<void> setEffort(String value) async {
    await settings.setEffort(value);
    notifyListeners();
  }
}
