import '../ai/ai_client.dart';
import '../ai/dream_pass.dart';
import '../ai/dream_reply.dart';
import '../data/memory_repository.dart';
import '../models/event.dart';
import '../models/learned_point.dart';
import '../services/settings_service.dart';

/// What a call to [DreamCoordinator.runIfDue] did.
enum DreamOutcome {
  /// Nothing was due (or a pass already ran today).
  notDue,

  /// A pass ran and its checked changes were saved.
  ran,

  /// A pass is due but the day's allowance is used up; it waits for the
  /// next reset (owner, 11 Oct 2026).
  waiting,

  /// The pass failed; it is tried again later.
  failed,

  /// Another pass is already running.
  busy,

  /// No AI is set up yet (no server and no key).
  noAi,
}

/// Decides when the AI dreams and saves what it learned
/// (docs/MEMORY_ARCHITECTURE.md build note 5, docs/MEMORY_WORKFLOW.md 2.5).
///
/// A pass is due after every [everyEvents] newly described events, or when a
/// milestone asked for one. At most one pass runs a day, and only one at a
/// time. A pass due while the allowance is used up waits for the next reset;
/// any other failure waits [retryDelay] before the next try. Nothing is
/// lost either way: the unread events stay unread until a pass reads them.
class DreamCoordinator {
  final MemoryRepository memory;
  final SettingsService book;

  /// Builds a pass, or returns null when no AI is set up.
  final Future<DreamPass?> Function() makePass;
  final DateTime Function() clock;

  static const everyEvents = 5;
  static const retryDelay = Duration(hours: 1);

  /// How many archived points a pass sees (settled 12 Oct 2026, point 4).
  static const archivedShown = 30;

  DreamCoordinator({
    required this.memory,
    required this.book,
    required this.makePass,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  bool _running = false;
  bool get running => _running;

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Described events no pass has read yet, oldest first.
  List<LifeEvent> unread(List<LifeEvent> events) {
    final read = book.dreamedEvents;
    return [
      for (final e in events)
        if (e.hasAccount && !read.contains(e.id)) e,
    ]..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
  }

  /// True when a pass should run now.
  bool isDue(List<LifeEvent> events) {
    final now = clock();
    if (book.lastDreamDay == _day(now)) return false;
    if (book.dreamRetryAfter case final at? when now.isBefore(at)) {
      return false;
    }
    final waiting = unread(events).length;
    return waiting >= everyEvents || (book.dreamMilestone && waiting > 0);
  }

  /// Asks for a pass at the next chance, for a milestone.
  Future<void> milestone() => book.setDreamMilestone(true);

  /// Marks every described event as read, so a pass learns only from what
  /// comes next. Used after "Erase what the AI remembers", so erased memory
  /// isn't rebuilt from the same events.
  Future<void> markAllRead(List<LifeEvent> events) async {
    await book.setDreamedEvents({
      ...book.dreamedEvents,
      for (final e in events)
        if (e.hasAccount) e.id,
    });
    await book.setDreamMilestone(false);
  }

  /// Runs a pass when one is due. [events] is the whole library; [quiet]
  /// and [honored] are the lowercase names the person keeps that way.
  Future<DreamOutcome> runIfDue({
    required List<LifeEvent> events,
    Set<String> quiet = const {},
    Set<String> honored = const {},
  }) async {
    if (_running) return DreamOutcome.busy;
    final now = clock();
    if (book.dreamWaitUntil case final at? when now.isBefore(at)) {
      return isDue(events) ? DreamOutcome.waiting : DreamOutcome.notDue;
    }
    if (!isDue(events)) return DreamOutcome.notDue;
    // Claimed before the first await, so a second call can't start too.
    _running = true;
    try {
      final pass = await makePass();
      if (pass == null) return DreamOutcome.noAi;
      final input = await _input(events, quiet, honored, now);
      final request = pass.buildRequest(input);
      final response = await pass.send(request);
      final changes = DreamChanges.parse(
        response,
        request: request,
        input: input,
        freeWrites: [
          for (final e in events)
            if (e.experience.trim().isNotEmpty) e.experience,
        ],
      );
      if (!changes.isEmpty) await memory.applyDream(changes, now: now);
      await book.setDreamedEvents({
        ...book.dreamedEvents,
        for (final e in input.newEvents) e.id,
      });
      await book.setLastDreamDay(_day(now));
      await book.setDreamMilestone(false);
      await book.setDreamWaitUntil(null);
      await book.setDreamRetryAfter(null);
      return DreamOutcome.ran;
    } on AIException catch (e) {
      if (e.statusCode == 402) {
        // The allowance resets at midnight UTC (docs/AI_SERVER.md).
        final utc = now.toUtc();
        await book.setDreamWaitUntil(
          DateTime.utc(utc.year, utc.month, utc.day + 1).toLocal(),
        );
        return DreamOutcome.waiting;
      }
      await book.setDreamRetryAfter(now.add(retryDelay));
      return DreamOutcome.failed;
    } catch (_) {
      await book.setDreamRetryAfter(now.add(retryDelay));
      return DreamOutcome.failed;
    } finally {
      _running = false;
    }
  }

  Future<DreamInput> _input(
    List<LifeEvent> events,
    Set<String> quiet,
    Set<String> honored,
    DateTime now,
  ) async {
    final newEvents = unread(events).take(DreamPass.maxEvents).toList();
    final current = await memory.current();
    final active = [
      for (final p in current)
        if (p.isActive) p,
    ];
    final archived = [
      for (final p in current)
        if (p.status == pointArchived) p,
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final shownArchived = archived.take(archivedShown).toList();
    final newIds = {for (final e in newEvents) e.id};
    final cited = {
      for (final p in [...active, ...shownArchived]) ...p.eventIds,
    }.difference(newIds);
    return DreamInput(
      today: now,
      newEvents: newEvents.map(DreamEvent.from).toList(),
      earlierEvents: [
        for (final e in events)
          if (cited.contains(e.id)) DreamEvent.from(e),
      ],
      active: active,
      archived: shownArchived,
      dream: await memory.dream(),
      quietNames: quiet,
      honoredNames: honored,
    );
  }
}
