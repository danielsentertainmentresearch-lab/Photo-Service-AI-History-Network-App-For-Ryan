# EventLens

Record the events of your life with photos and quick notes. EventLens keeps
the photos in a private library on the phone, and Claude (Anthropic's AI)
writes a richly detailed account of each event on your behalf. Claude draws on:

- **Working memory**: what you jot down in the moment (who's there, what's
  happening, how it feels), plus the time and place.
- **Contextual memory**: durable facts you've saved (people, places, ongoing
  situations, preferences) and summaries of your recent events, so each new
  account connects to the ones before it.

After each account, Claude suggests new facts worth remembering. You approve
or dismiss each one, and approved facts go into long-term memory.

This is **stage 1**: an Android app built with Flutter, ready for Google Play.

## Features

- New event: up to 10 photos (gallery or camera), date/time, place, title, notes.
- AI account: a detailed first-person narrative, a short summary, and labels
  for people, places and tags. You can edit it, copy it or rewrite it.
- Memory screen: add, edit and delete what the AI should always know.
- Timeline graph: after every 10 photos in newly described events (Off, 5,
  10, 20 or 50 in Settings), the AI organises the whole timeline into
  chapters, links between related events, and recurring themes. A graph
  view shows events left to right in time, connected to their people,
  places, tags, themes and memories.
- Edit timeline: every part of the organised timeline can be edited by
  hand: overview, chapters (title, summary, order, events, colour),
  larger groupings of chapters (working name "Group", set by
  `groupingLabel` in `lib/models/memory_graph.dart`), themes, and
  connections. Chapter colours are chosen by the user and ring that
  chapter's events in the graph. Edits are repaired before saving so bad
  input can't break the app, and AI rebuilds keep the user's groups,
  colours, renamed chapters and own themes/connections.
- Timeline grouped by month, plus full-text search across everything.
- Settings: your own Anthropic API key (stored encrypted), the model
  (Claude Opus 5.5 by default, or Sonnet 5.5) and the thinking effort.
- Light and dark themes, and recovery when the app is closed mid-description.

## Where the data lives

| Data | Location |
|---|---|
| Original photos | App-private storage on the device (`files/vault/`) |
| Events, memories | SQLite database on the device |
| API key | Android Keystore-backed encrypted storage |

Data leaves the phone only when an event is described. That request sends the
event's photos (downscaled to 1568 px), its notes, summaries of the 15 most
recent events and the saved memories to `api.anthropic.com` over HTTPS. Cloud
backup is disabled for app data. See [PRIVACY_POLICY.md](PRIVACY_POLICY.md).

## Architecture

```
lib/
  main.dart      Opens the database, vault and settings; starts the app
  app.dart       Theme, first-run routing
  ai/            Claude API client (raw HTTP), event descriptions, timeline graph
  graph/         Force-directed layout with events pinned to a time axis
  data/          SQLite schema, repositories, on-device image vault
  models/        LifeEvent, EventImage, MemoryItem
  services/      Settings (secure API key, preferences)
  state/         AppState: the single ChangeNotifier the UI watches
  screens/       Welcome, Home/timeline, New event, Event detail, Memory, Settings
  widgets/       Shared image and status widgets
test/            Unit, integration (real SQLite via FFI) and widget tests
tool/            Icon and store-graphic generator
store/           Play Store listing text and graphics
.github/workflows/android.yml   CI: analyze, test, build APK + app bundle
```

Describing an event goes: `AppState.describeEvent` marks the event as
describing, then downscales its photos in a background isolate.
`EventDescriber` builds one Messages API request containing the instructions
and long-term memory (cached system prompt), the photos, the notes and the
recent-event summaries. The response is a JSON object constrained by a schema
(`title`, `summary`, `description`, `people`, `places`, `tags`,
`memory_suggestions`), and it is stored on the event. Failures are stored on
the event with a readable message and a Retry button.

## Development

Requires Flutter 3.47+ (stable) and Android Studio or the Android SDK.

```bash
flutter pub get
flutter analyze
flutter test
flutter run            # on a connected device or emulator
```

On first launch, open Settings and paste an Anthropic API key from
<https://console.anthropic.com/settings/keys>. Usage is billed to that
Anthropic account. A typical event costs roughly 5–30 US cents on Opus 5.5
at high effort, depending on photo count and length, and about half that on
Sonnet 5.5.

To regenerate review screenshots with sample data (`store/screenshots/`):

```bash
flutter test tool/screenshots_test.dart
```

Photo thumbnails don't render in this test renderer, and the sample
photos are placeholders, so take real device screenshots for the Play
Store listing.

To regenerate the icon or store graphics after changing `tool/generate_icon.dart`:

```bash
dart run tool/generate_icon.dart && dart run flutter_launcher_icons
```

## Builds

Every push to `main` runs the **Android** workflow on GitHub's runners, which
come with the official Android SDK. Each run's page under the Actions tab has
an `eventlens-N` artifact containing:

- `app-release.apk`: install directly on a phone for testing.
- `app-release.aab`: the bundle Google Play takes.

Without signing secrets these builds are signed with a debug key, which is
fine for testing but not accepted by Play. See [RELEASE.md](RELEASE.md).

## Roadmap ideas (stage 2+)

- Optional sync to a self-hosted server (e.g. a Docker container on a home
  NAS), with the AI call moved server-side so the key never sits on the phone.
- Export/import of the whole library (zip of photos + JSON).
- Ask questions across all events ("when did I last see Sam?").
- Read EXIF time and location from photos automatically.
