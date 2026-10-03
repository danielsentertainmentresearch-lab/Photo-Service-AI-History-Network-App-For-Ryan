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
- Accounts: an account is required after the tutorial. Sign up with
  email + password, phone + password (number confirmed by SMS), or Google;
  optional fingerprint/face unlock each time the app opens. Accounts run on
  Firebase Authentication. Test builds also offer "Continue as reviewer".
- Timeline graph: the first 10 described photos turn the timeline into a
  graph, once. From then on the AI builds on it as each event is described
  (new chapters, connections and themes are added; what it already wrote
  stays). The graph shows events left to right in time, connected to their
  people, places, tags, themes and memories.
- AI-owned content: chapter wording and membership, themes, connections and
  the overview are written only by the AI and can't be edited.
- Books & rings (the user's layer): gather chapters into titled Books, and
  put coloured rings on events. One ring colour is free; the rest unlock in
  order with rewarded videos (5, then 6, 7, …). The ring palette in
  `lib/models/ring_palette.dart` is a placeholder until the brand palette
  arrives.
- Photo dates and places: picking or taking a photo fills in the event's
  date from its EXIF capture time, and its place from the photo's GPS
  (named via OpenStreetMap Nominatim). The phone's location permission is
  never requested.
- On this day: events from today's date in earlier years, at the top of
  the timeline.
- Weather (optional, per event): the weather at the event's place and hour
  from Open-Meteo. Never sent to the AI and never part of the account.
  Unlocked for the day by 3 rewarded videos; the day refreshes at 12:00
  noon.
- Separate libraries per account: everyone signed in on a shared phone has
  their own database, photos, API key, settings, rings and weather pass.
  The library from before accounts goes to the first account to sign in.
- Export: Settings → Export makes a zip with an Obsidian vault (one note per
  event, linked to people, places, tags, chapters, books and themes, with
  photos embedded) and a full `data.json`.
- Hidden from recent apps by default (Android `FLAG_SECURE`; toggle in
  Settings), which also blocks screenshots of the app.
- Timeline grouped by month, plus full-text search across everything.
- Settings: your own Anthropic API key (stored encrypted), the model
  (Claude Opus 5.5 by default, or Sonnet 5.5) and the thinking effort.
- Light and dark themes, and recovery when the app is closed mid-description.

## Where the data lives

| Data | Location |
|---|---|
| Original photos | App-private storage on the device (`files/vaults/<account>/`) |
| Events, memories, weather | SQLite database on the device, one per account |
| API key | Android Keystore-backed encrypted storage |
| Account | Firebase Authentication (email or phone, sign-in method) |
| Ring unlock progress | On the device |

Data leaves the phone only when an event is described. That request sends the
event's photos (downscaled to 1568 px), its notes, summaries of the 15 most
recent events and the saved memories to `api.anthropic.com` over HTTPS. Cloud
backup is disabled for app data. Signing in contacts Firebase (Google), and
unlocking ring colours or weather plays AdMob (Google) rewarded videos.
Place names send a photo's coordinates to OpenStreetMap Nominatim, and
weather lookups send coordinates or the place text plus the date to
Open-Meteo. See
[PRIVACY_POLICY.md](PRIVACY_POLICY.md).

## Architecture

```
lib/
  main.dart      Opens the database, vault and settings; starts the app
  app.dart       Theme, first-run routing
  ai/            Claude API client (raw HTTP), event descriptions, timeline graph
  graph/         Force-directed layout with events pinned to a time axis
  data/          SQLite schema, repositories, on-device image vault
  models/        LifeEvent, EventImage, MemoryItem
  services/      Settings, accounts (Firebase Auth + biometric lock),
                 rewarded videos (AdMob behind a swappable interface),
                 photo EXIF, places and weather, export, recents privacy
  state/         AppState: the ChangeNotifier the UI watches; LibraryScope
                 opens the signed-in account's own library
  screens/       Tutorial, Account, Home/timeline, New event, Event detail,
                 Memory, Timeline graph, Books & rings, Settings
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

- Paywall tier for editing AI-owned nodes (people, places, tags, themes,
  memories) and adding your own connections and themes.
- Store ring unlocks and the library with the account, so they survive a
  reinstall or a new phone.
- Passkeys (FIDO2) in addition to biometric unlock.
- Optional sync to a self-hosted server (e.g. a Docker container on a home
  NAS), with the AI call moved server-side so the key never sits on the phone.
- Import of an exported library.
- Ask questions across all events ("when did I last see Sam?").
- Owner metrics dashboard, self-hosted on the owner's computer (final
  stage; see docs/LAUNCH_CHECKLIST.md).
