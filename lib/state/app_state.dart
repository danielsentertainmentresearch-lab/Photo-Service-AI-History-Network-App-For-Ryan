import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../ai/ai_server.dart';
import '../ai/anthropic_ai_client.dart';
import '../ai/experience_labeler.dart';
import '../ai/data_platform_advisor.dart';
import '../ai/event_describer.dart';
import '../ai/graph_builder.dart';
import '../data/event_repository.dart';
import '../data/graph_repository.dart';
import '../data/image_vault.dart';
import '../data/memory_repository.dart';
import '../models/event.dart';
import '../models/memory_graph.dart';
import '../models/memory_item.dart';
import '../models/name_spelling.dart';
import '../models/name_state.dart';
import '../data/name_state_repository.dart';
import '../services/data_files.dart';
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

/// The owner's AI server when [credential] is [aiServerCredential],
/// otherwise Anthropic directly with the person's own key.
AIClient aiClientFor(String credential, String task) =>
    credential == aiServerCredential
    ? ProxyAIClient.fromEnvironment(task)
    : AnthropicAIClient(apiKey: credential);

GraphBuilder _defaultGraphBuilder(String apiKey, String model, String effort) =>
    GraphBuilder(
      client: aiClientFor(apiKey, AiTask.graph),
      model: model,
      effort: effort,
    );

EventDescriber _defaultDescriber(String apiKey, String model, String effort) =>
    EventDescriber(
      client: aiClientFor(apiKey, AiTask.describe),
      model: model,
      effort: effort,
    );

typedef PlatformAdvisorFactory = DataPlatformAdvisor Function(
  String apiKey,
  String model,
);

DataPlatformAdvisor _defaultAdvisor(String apiKey, String model) =>
    DataPlatformAdvisor(
      client: aiClientFor(apiKey, AiTask.advise),
      model: model,
    );

typedef LabelerFactory = ExperienceLabeler Function(
  String apiKey,
  String model,
);

ExperienceLabeler _defaultLabeler(String apiKey, String model) =>
    ExperienceLabeler(client: aiClientFor(apiKey, AiTask.label), model: model);

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
  final PlatformAdvisorFactory advisorFactory;
  final LabelerFactory labelerFactory;
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
    this.advisorFactory = _defaultAdvisor,
    this.labelerFactory = _defaultLabeler,
    bool? useAiServer,
    this.nameStateRepo,
  }) : places = places ?? PlacesService(),
       usesAiServer = useAiServer ?? aiServerUrl.isNotEmpty;

  /// How the person keeps each name (as usual, quiet, honored). Null in
  /// tests that don't need it: choices then last only while the app runs.
  final NameStateRepository? nameStateRepo;
  List<NameState> _nameStates = const [];

  /// True when the AI runs through the owner's server (see `AI_SERVER_URL`),
  /// so nobody needs their own Anthropic API key.
  final bool usesAiServer;

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

  /// True when the AI features can run: through the owner's server, or with
  /// the person's own key.
  bool get aiReady => usesAiServer || _hasApiKey;

  /// What the AI factories are given: [aiServerCredential] on the owner's
  /// server, otherwise the saved API key (null when there is none).
  Future<String?> _aiCredential() async =>
      usesAiServer ? aiServerCredential : settings.readApiKey();

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
    _nameStates = await nameStateRepo?.all() ?? const [];
    await _reload();
    _loaded = true;
    notifyListeners();
  }

  Future<void> _reload() async {
    _events = await events.all();
    _memories = await memoryRepo.all();
    if (_events.length >= exportUnlockEvents && !settings.exportUnlocked) {
      await settings.setExportUnlocked();
    }
    notifyListeners();
  }

  // ---- Your data --------------------------------------------------------------

  /// The full export (zip and analysis file) unlocks once the library
  /// reaches [exportUnlockEvents] events and stays unlocked after that.
  bool get exportUnlocked =>
      settings.exportUnlocked || _events.length >= exportUnlockEvents;

  int get eventsUntilExport =>
      exportUnlocked ? 0 : exportUnlockEvents - _events.length;

  Set<String> get hiddenMeters => settings.hiddenMeters;

  Future<void> setMeterHidden(String id, bool hidden) async {
    final next = {...settings.hiddenMeters};
    hidden ? next.add(id) : next.remove(id);
    await settings.setHiddenMeters(next);
    notifyListeners();
  }

  /// Python data platforms that suit the analysis file. Asks the AI once
  /// (only column names are sent) and keeps the answer; without a key or a
  /// connection it returns [PlatformAdvice.fallback], which isn't kept.
  Future<PlatformAdvice> dataPlatforms({bool refresh = false}) async {
    if (!refresh) {
      final cached = PlatformAdvice.fromJsonString(settings.platformAdvice);
      if (cached != null) return cached;
    }
    final apiKey = await _aiCredential();
    if (apiKey == null || apiKey.isEmpty) return PlatformAdvice.fallback;
    try {
      final advice = await advisorFactory(apiKey, settings.model).suggest();
      await settings.setPlatformAdvice(advice.toJsonString());
      return advice;
    } catch (_) {
      return PlatformAdvice.fallback;
    }
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
    String experience = '',
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
      experience: experience,
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
    // Re-read so an AI account or weather saved while the edit sheet was
    // open isn't overwritten with the older copy.
    final current = await events.byId(event.id);
    if (current == null) return;
    final place = location?.trim();
    final placeChanged = place != null && place != current.location;
    final timeChanged = occurredAt != null && occurredAt != current.occurredAt;
    await events.update(
      current.copyWith(
        title: title?.trim(),
        notes: notes?.trim(),
        location: place,
        occurredAt: occurredAt,
        updatedAt: DateTime.now(),
        // A new place or time means the old map position and weather no
        // longer belong to this event.
        clearCoordinates: placeChanged,
        clearWeather: placeChanged || timeChanged,
      ),
    );
    await _reload();
  }

  /// Saves the person's free write exactly as typed, onto the latest copy
  /// of the event so an AI account arriving meanwhile is kept.
  Future<void> updateExperience(String eventId, String text) async {
    final current = await events.byId(eventId);
    if (current == null || current.experience == text) return;
    await events.update(
      current.copyWith(experience: text, updatedAt: DateTime.now()),
    );
    await _reload();
  }

  // ---- Free-write labels ------------------------------------------------------

  final Set<String> _labelling = {};
  String? _labelError;

  /// Why the last labelling attempt failed, if it did.
  String? get labelError => _labelError;
  bool get labelling => _labelling.isNotEmpty;

  /// Events with a free write whose labels haven't been made yet.
  int get eventsAwaitingLabels => _events.where((e) => e.needsLabels).length;

  /// Every label in the library with the number of events that carry it,
  /// most used first.
  List<MapEntry<String, int>> get labelCounts {
    final counts = <String, int>{};
    for (final e in _events) {
      for (final label in e.experienceLabels) {
        counts[label] = (counts[label] ?? 0) + 1;
      }
    }
    return counts.entries.toList()..sort(
      (a, b) => b.value != a.value ? b.value - a.value : a.key.compareTo(b.key),
    );
  }

  /// Makes labels for an event's free write when they are due, or anew when
  /// [again] is set (the person asked to label it again). Every run is a
  /// first pass: the AI is told nothing about this event's earlier labels or
  /// the person's choices, so any label, including one they turned down, can
  /// come back as new. The result replaces the event's labels and choices.
  /// Clears labels when the free write is emptied. Without a key it leaves
  /// them waiting. A free write edited while labelling is labelled again
  /// next time.
  Future<void> labelExperience(String eventId, {bool again = false}) async {
    final current = await events.byId(eventId);
    if (current == null) return;
    if (current.experience.trim().isEmpty) {
      if (current.experienceLabels.isNotEmpty ||
          current.labelledExperience.isNotEmpty) {
        await events.update(
          current.copyWith(experienceLabels: const [], labelledExperience: ''),
        );
        await _reload();
      }
      return;
    }
    if (!current.needsLabels && !again) return;
    final apiKey = await _aiCredential();
    if (apiKey == null || apiKey.isEmpty) return;
    if (!_labelling.add(eventId)) return;
    notifyListeners();
    try {
      final writing = current.experience;
      final result = await labelerFactory(apiKey, settings.model)
          .labelWithSupport(
            writing,
            existing: {
              for (final e in _events)
                if (e.id != eventId) ...e.experienceLabels,
            },
          );
      final labels = result.labels;
      final latest = await events.byId(eventId);
      if (latest != null && latest.experience.trim() == writing.trim()) {
        await events.update(
          latest.copyWith(
            supportLevel: result.supportLevel,
            supportDismissed: result.supportLevel == latest.supportLevel
                ? latest.supportDismissed
                : false,
            experienceLabels: labels,
            confirmedLabels: const [],
            rejectedLabels: const [],
            labelledExperience: writing,
          ),
        );
      }
      _labelError = null;
    } on AIException catch (e) {
      _labelError = e.message;
    } catch (e) {
      _labelError = 'Labelling failed: $e';
    } finally {
      _labelling.remove(eventId);
      await _reload();
    }
  }

  /// The person says [label] fits this event's free write. Final: it can't
  /// be turned into "doesn't fit" afterwards.
  Future<void> confirmLabel(String eventId, String label) async {
    final current = await events.byId(eventId);
    if (current == null || !current.experienceLabels.contains(label)) return;
    if (current.confirmedLabels.contains(label)) return;
    await events.update(
      current.copyWith(confirmedLabels: [...current.confirmedLabels, label]),
    );
    await _reload();
  }

  /// The person says [label] doesn't fit (unsuitable, or made up by the
  /// AI). It is removed from the event. Final: a label already confirmed
  /// can't be turned down, and nothing brings a removed label back except
  /// a new labelling pass.
  Future<void> rejectLabel(String eventId, String label) async {
    final current = await events.byId(eventId);
    if (current == null || !current.experienceLabels.contains(label)) return;
    if (current.confirmedLabels.contains(label)) return;
    await events.update(
      current.copyWith(
        experienceLabels: [
          for (final l in current.experienceLabels)
            if (l != label) l,
        ],
        rejectedLabels: {...current.rejectedLabels, label}.toList(),
      ),
    );
    await _reload();
  }

  /// Labels every free write that is waiting, one at a time.
  Future<void> labelAllWaiting() async {
    for (final e in _events.where((e) => e.needsLabels).toList()) {
      await labelExperience(e.id);
      if (_labelError != null) return;
    }
  }

  Future<void> updateDescription(LifeEvent event, String description) async {
    final current = await events.byId(event.id);
    if (current == null) return;
    await events.update(
      current.copyWith(
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
    // Guards against a double tap starting two paid requests.
    if (!_describing.add(eventId)) return;
    try {
      await _describe(eventId);
    } finally {
      _describing.remove(eventId);
    }
  }

  final Set<String> _describing = {};

  Future<void> _describe(String eventId) async {
    final event = await events.byId(eventId);
    if (event == null || event.status == EventStatus.describing) return;

    final apiKey = await _aiCredential();
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
        honored: [
          for (final n in _nameStates)
            if (n.state == nameHonored) n.name,
        ],
      );
      // Write onto the latest copy, keeping edits and weather saved while
      // the AI was working.
      final latest = await events.byId(eventId);
      if (latest == null) return;
      await events.update(
        latest.copyWith(
          title: latest.title.isEmpty ? account.title : latest.title,
          summary: account.summary,
          description: account.description,
          people: account.people,
          places: account.places,
          tags: account.tags,
          suggestions: _withoutKnown(account.memorySuggestions),
          questions: account.questions,
          status: EventStatus.described,
          clearError: true,
          model: account.model,
          updatedAt: DateTime.now(),
        ),
      );
    } catch (e) {
      final message = e is AIException || e is FormatException
          ? e.toString()
          : 'Something went wrong: $e';
      final latest = await events.byId(eventId);
      if (latest != null) {
        await events.update(
          latest.copyWith(status: EventStatus.failed, error: message),
        );
      }
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
    final apiKey = await _aiCredential();
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
      _graphError = e is AIException
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
    final quiet = quietNames;
    return _events
        .where(
          (e) =>
              e.occurredAt.month == day.month &&
              e.occurredAt.day == day.day &&
              e.occurredAt.year < day.year &&
              !_featuresAny(e, quiet),
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

  /// Answers one of the AI's who/where questions. The answer is saved as a
  /// memory (so later events can name them too) and kept with the event's
  /// notes, where "Rewrite with AI" picks it up.
  Future<void> answerQuestion(
    LifeEvent event,
    AiQuestion q,
    String answer,
  ) async {
    final text = answer.trim();
    if (text.isEmpty) return;
    final current = await events.byId(event.id);
    if (current == null) return;
    final where = current.title.trim().isEmpty
        ? DateFormat.yMMMd().format(current.occurredAt)
        : current.title.trim();
    await addMemory(
      q.kind,
      '$text: ${q.about} in "$where"',
      source: answerSource,
      eventId: event.id,
    );
    final line = '${q.question} $text';
    await events.update(
      current.copyWith(
        notes: current.notes.trim().isEmpty
            ? line
            : '${current.notes.trim()}\n$line',
        questions: current.questions
            .where((x) => x.question != q.question)
            .toList(),
        updatedAt: DateTime.now(),
      ),
    );
    await _reload();
  }

  /// Leaves one of the AI's questions unanswered for good.
  Future<void> skipQuestion(LifeEvent event, AiQuestion q) async {
    final current = await events.byId(event.id);
    if (current == null) return;
    await events.update(
      current.copyWith(
        questions: current.questions
            .where((x) => x.question != q.question)
            .toList(),
      ),
    );
    await _reload();
  }

  // ---- Quiet and honored names ---------------------------------------------

  List<NameState> get nameStates => _nameStates;

  /// Lowercase names the person keeps quiet: they don't come up on their own.
  Set<String> get quietNames => namesIn(_nameStates, nameQuiet);

  /// Lowercase names the person honors.
  Set<String> get honoredNames => namesIn(_nameStates, nameHonored);

  /// How [name] is kept, and since when (null when as usual).
  NameState? nameStateOf(String name, String kind) {
    for (final n in _nameStates) {
      if (n.kind == kind && n.name.toLowerCase() == name.trim().toLowerCase()) {
        return n;
      }
    }
    return null;
  }

  /// Keeps [name] as usual, quiet or honored. Changeable any time; nothing
  /// about the person or their events is deleted.
  Future<void> setNameState(String name, String kind, String state) async {
    final now = DateTime.now();
    await nameStateRepo?.set(name.trim(), kind, state, now);
    _nameStates = [
      for (final n in _nameStates)
        if (!(n.kind == kind &&
            n.name.toLowerCase() == name.trim().toLowerCase()))
          n,
      if (state != nameAsUsual)
        NameState(name: name.trim(), kind: kind, state: state, since: now),
    ];
    notifyListeners();
  }

  static bool _featuresAny(LifeEvent e, Set<String> names) =>
      names.isNotEmpty &&
      [...e.people, ...e.places].any((n) => names.contains(n.trim().toLowerCase()));

  /// The person put the support line on this event away.
  Future<void> dismissSupport(String eventId) async {
    final current = await events.byId(eventId);
    if (current == null) return;
    await events.update(current.copyWith(supportDismissed: true));
    await _reload();
  }

  // ---- Name spellings and erasing what the AI remembers ---------------------

  /// Corrects the spelling of a person or place the AI knows, everywhere it
  /// appears: events, accounts, memories and the timeline graph. Only
  /// spelling fixes are allowed (see [isSpellingFix]); anything else throws
  /// an [ArgumentError]. Returns how many events changed.
  Future<int> fixNameSpelling(String from, String to) async {
    if (!isSpellingFix(from, to)) {
      throw ArgumentError('Only spelling fixes are allowed.');
    }
    final a = from.trim();
    final b = to.trim();
    String fix(String text) => replaceName(text, a, b);
    List<String> fixList(List<String> names) => [
      for (final n in names) n.trim() == a ? b : n,
    ];

    var changed = 0;
    for (final e in await events.all()) {
      final next = e.copyWith(
        title: fix(e.title),
        notes: fix(e.notes),
        location: fix(e.location),
        summary: fix(e.summary),
        description: fix(e.description),
        people: fixList(e.people),
        places: fixList(e.places),
      );
      if (next.toRow().toString() != e.toRow().toString()) {
        await events.update(next);
        changed++;
      }
    }
    for (final m in await memoryRepo.all()) {
      final content = fix(m.content);
      if (content != m.content) {
        await memoryRepo.save(m.copyWith(content: content));
      }
    }
    final graph = _graph;
    if (graph != null) {
      final next = graph.copyWith(
        overview: fix(graph.overview),
        chapters: [
          for (final c in graph.chapters)
            TimelineChapter(
              id: c.id,
              title: fix(c.title),
              summary: fix(c.summary),
              eventIds: c.eventIds,
              bookId: c.bookId,
            ),
        ],
        links: [
          for (final l in graph.links)
            EventLink(
              fromEventId: l.fromEventId,
              toEventId: l.toEventId,
              relation: fix(l.relation),
            ),
        ],
        themes: [
          for (final t in graph.themes)
            StoryTheme(
              name: fix(t.name),
              description: fix(t.description),
              eventIds: t.eventIds,
            ),
        ],
      );
      await graphRepo.replace(next);
      _graph = next;
    }
    await _reload();
    return changed;
  }

  /// Erases everything the AI remembers, all at once. Events, their
  /// accounts, photos and free writes stay as they are.
  Future<void> eraseAiMemory() async {
    await memoryRepo.deleteAll();
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
