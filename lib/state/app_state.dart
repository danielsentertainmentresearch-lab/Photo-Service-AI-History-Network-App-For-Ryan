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
import '../services/places_service.dart';
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
  final PlacesService places;
  final Uuid _uuid = const Uuid();

  AppState({
    required this.events,
    required this.memoryRepo,
    required this.graphRepo,
    required this.vault,
    required this.settings,
    this.describerFactory = _defaultDescriber,
    this.graphBuilderFactory = _defaultGraphBuilder,
    PlacesService? places,
  }) : places = places ?? PlacesService();

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
  int get describedCount => _events.where((e) => e.hasAccount).length;

  /// The knowledge graph of everything recorded so far.
  GraphData get graph =>
      buildGraph(events: _events, memories: _memories, snapshot: _graph);

  int get describedPhotos => describedPhotoCount(_events);

  /// True once the first [graphUnlockPhotos] described photos have turned
  /// the timeline into a graph. It stays a graph from then on.
  bool get graphUnlocked => _graph != null;

  /// Described photos still needed to unlock the graph (0 once unlocked).
  int get photosUntilUnlock =>
      graphUnlocked ? 0 : max(graphUnlockPhotos - describedPhotos, 0);

  /// Described events the AI hasn't added to the graph yet.
  int get eventsAwaitingGraph =>
      _graph == null ? 0 : GraphBuilder.pending(_events, _graph!).length;

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
    double? latitude,
    double? longitude,
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
      latitude: latitude,
      longitude: longitude,
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
    if (eventById(eventId)?.status == EventStatus.described) {
      await advanceGraph();
    }
  }

  List<MemorySuggestion> _withoutKnown(List<MemorySuggestion> suggestions) {
    final known = _memories.map((m) => m.content.toLowerCase().trim()).toSet();
    return suggestions
        .where((s) => !known.contains(s.content.toLowerCase().trim()))
        .toList();
  }

  /// Moves the graph forward. The first time enough photos are described,
  /// the AI turns the timeline into a graph; after that it adds any newly
  /// described events to it, building on what it already wrote. Also used
  /// to retry after a failure. Never rewrites the existing graph.
  Future<void> advanceGraph() async {
    if (_graphBuilding) return;
    final current = _graph;
    if (current == null && describedPhotos < graphUnlockPhotos) return;
    if (current != null && eventsAwaitingGraph == 0) return;
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
      final next = current == null
          ? await builder.build(_events, _memories)
          : await builder.update(current, _events, _memories);
      // The user's books and rings may have changed while the AI worked.
      final latest = _graph;
      final merged = latest == null
          ? next
          : next.withUserLayer(
              books: latest.books,
              chapterBooks: {for (final c in latest.chapters) c.id: c.bookId},
              rings: latest.rings,
            );
      final clean = merged.sanitized(_events.map((e) => e.id).toSet());
      await graphRepo.replace(clean);
      _graph = clean;
    } catch (e) {
      _graphError = e is AnthropicException
          ? e.toString()
          : 'Could not update the timeline graph: $e';
    } finally {
      _graphBuilding = false;
      notifyListeners();
    }
  }

  /// Saves the user's own layer of the graph: books, which book each
  /// chapter sits in, and rings on events. Everything the AI wrote is
  /// taken from the stored graph, so it can't be changed from here.
  Future<void> updateUserLayer({
    required List<Book> books,
    required Map<String, String?> chapterBooks,
    required Map<String, int> rings,
  }) async {
    final current = _graph;
    if (current == null) return;
    final next = current
        .withUserLayer(books: books, chapterBooks: chapterBooks, rings: rings)
        .sanitized(_events.map((e) => e.id).toSet());
    await graphRepo.replace(next);
    _graph = next;
    notifyListeners();
  }

  /// Events from this calendar day in earlier years, most recent first.
  List<LifeEvent> onThisDay([DateTime? today]) {
    final day = today ?? DateTime.now();
    return _events
        .where(
          (e) =>
              e.occurredAt.month == day.month &&
              e.occurredAt.day == day.day &&
              e.occurredAt.year < day.year,
        )
        .toList()
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
  }

  /// Looks up the weather for an event and stores it with the event. Uses
  /// the event's coordinates, or finds them from its place name. The
  /// weather is never sent to the AI. Throws [PlacesException] with a
  /// readable message when it can't be found.
  Future<void> lookUpWeather(String eventId) async {
    final event = await events.byId(eventId);
    if (event == null) return;
    var lat = event.latitude, lon = event.longitude;
    if (lat == null || lon == null) {
      if (event.location.trim().isEmpty) {
        throw const PlacesException(
          'Add a place to this event first (Edit details → Where).',
        );
      }
      final found = await places.findPlace(event.location);
      if (found == null) {
        throw PlacesException('Couldn\'t find "${event.location}" on the map.');
      }
      (lat, lon) = found;
    }
    final weather = await places.weatherAt(lat, lon, event.occurredAt);
    final current = await events.byId(eventId);
    if (current == null) return;
    await events.update(
      current.copyWith(latitude: lat, longitude: lon, weather: weather),
    );
    await _reload();
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

  Future<void> setEffort(String value) async {
    await settings.setEffort(value);
    notifyListeners();
  }
}
