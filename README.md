# EventLens

Record the events of your life with photos and quick notes. EventLens keeps
the photos in a private library on the phone, and Claude (Anthropic's AI)
writes a richly detailed account of each event on your behalf. Claude draws on:

- **Working memory**: what you jot down in the moment (who's there and
  what's happening), plus the time and place.
- **Contextual memory**: durable facts you've saved (people, places, ongoing
  situations, preferences) and summaries of your recent events, so each new
  account connects to the ones before it.

After each account, Claude suggests new facts worth remembering. You approve
or dismiss each one, and approved facts go into long-term memory.

Android app built with Flutter, set up for Google Play.

## Status

**Build stage 1 has ended** (signed off by the owner on 4 October 2026;
frozen branch `build-stage-1`). Everything built in stage 1 is described in
[docs/BUILD_STAGE_1.md](docs/BUILD_STAGE_1.md).

**Build stage 2 started on 4 October 2026**, on the owner's command. Its
living deliverable is [docs/BUILD_STAGE_2.md](docs/BUILD_STAGE_2.md).

**Who it's for:** everyday phone users on the Android and Apple app stores.
Its data features (Your data, the spreadsheets, the data guide) are for
fun and daily use. The owner dashboard is the only enterprise-level part of
EventLens; the owner issues it personally to those who need it, or who need
to host or fork this architecture. An enterprise version of the app may be
developed further down the line, but there is no intention to do so at
this point.

Outside accounts and platforms still to connect are in
[docs/LAUNCH_CHECKLIST.md](docs/LAUNCH_CHECKLIST.md).

**Try it:** every push to `main` publishes a test APK at
<https://github.com/danielsentertainmentresearch-lab/Photo-Service-AI-History-Network-App-For-Ryan/releases/download/latest-build/eventlens-latest.apk>.
Test builds sign in with **Continue as reviewer** (real accounts and real ads
switch on once their platforms are connected).

## Features

### Recording events
- New event: up to 10 photos (gallery or camera), date and time, place,
  title and notes.
- Dates and places fill in from the photo itself: the capture time from its
  EXIF data, and a place name from its GPS position (named by OpenStreetMap
  Nominatim). The phone's location permission is never requested, and a
  date you pick yourself is never overwritten.
- A free write on every event: a blank box with no prompt, for writing
  about the experience in your own way. The "?" beside it explains it.
  The AI never changes it; it reads it only to make a few short labels,
  checked against the writing, that show in Your data.
- Every launch opens on a short title screen: the Scaffold logo, the
  EventLens name and the "CORE MEMORY · 2010" banner. A tap skips it.
- Timeline grouped by month, full-text search across everything, and
  **On this day** (events from today's date in earlier years) at the top.

### The AI
- Each event gets a detailed, factual first-person account (what the
  photos, notes, time and place confirm), a short summary, and
  labels for people, places and tags. You can edit, copy or rewrite it.
- Memory screen: add, edit and delete what the AI should always know; the
  AI suggests new memories after each event, and you choose what to keep.
- The AI never identifies people from faces; it names them only from your
  notes and saved memories.
- Your own Anthropic API key (stored encrypted), Claude Opus 5.5 by default
  or Sonnet 5.5, and the thinking effort, in Settings.

### Timeline graph
- The first 10 described photos turn the timeline into a connected graph,
  once. From then on the AI builds on it as events are described, adding
  chapters, connections and themes without rewriting what it already wrote.
- **Mind map** (first tab): your story in the centre, branching into
  chapters, themes, people and places. Tap a branch to open it, centre on
  any idea to explore from there, and follow the trail back.
- Events sit left to right in time, linked to their people, places, tags,
  themes and memories.
- AI-owned content (chapter wording and membership, themes, connections,
  the overview) is read-only.

### Your layer: Books and rings
- Gather chapters into titled **Books**.
- Put coloured **rings** on events. One colour is free; the rest unlock in
  order with rewarded videos (5, then 6, 7, …). The palette in
  `lib/models/ring_palette.dart` is a placeholder until the brand palette.

### Your data and export
- **Your data** (chart icon on the timeline): meters for the whole library
  (events, photos, AI accounts, people, places, tags, memories, time
  covered, busiest month, most recorded person and place, words written,
  graph status, chapters, books, rings, weather). Hide any meter and bring
  it back later. Free for everyone.
- **Basic CSV**: every event as a spreadsheet file, free at any time.
- **Full export**, unlocked once a library reaches **100 events** (and kept
  after that): a zip with the original photos, an Obsidian vault (one note
  per event, linked to people, places, tags, chapters, books and themes),
  `data.json`, the basic CSV, and an **analysis CSV** with typed columns
  for Python (pandas, Jupyter) plus its column guide.
- Below 100 events, a preview banner shows what the full export holds and
  how many events are left.
- **Free-write labels**: the AI reads each free write and suggests a few
  short labels (such as "calm" or "proud"), drawn from its words, meaning
  and sentiment, then checks them in a second pass. They show only in
  Your data, where you can say once whether each one fits (no undo), or have
  the AI label the event again. In the analysis CSV each label is its own
  1/0 column, and no cell is ever blank (unknowns are words or -999).
- **Explore your data**: a plain-language guide to opening the analysis CSV
  in a Jupyter notebook (for fun, not professional work; some Python
  knowledge recommended), with a link to jupyter.org. The list of Python
  platforms that suit the file is chosen by the AI from the column names
  only; without a key or a connection it shows the most likely platform.

### Accounts and privacy
- An account is required after the tutorial: email + password, phone +
  password (number confirmed by SMS), Google, or a **Web3 identity**
  (Ethereum wallets such as MetaMask, Solana wallets such as Phantom, or
  Farcaster). The Web3 section is labelled "These are Web3 identities" and
  has a plain-language **What is this?** explanation.
- Optional fingerprint or face unlock; it asks again after 30 seconds away.
- Each account on a shared phone has its own separate library (database,
  photos, API key, settings, rings, weather pass, meters). The library
  from before accounts goes to the first account that signs in.
- Hidden from the recent-apps screen by default (Android `FLAG_SECURE`, with
  a toggle in Settings), which also blocks screenshots of the app.
- Delete account in Settings, as Google Play requires.

### Optional extras
- **Weather** for any event, from Open-Meteo, for the event's place and
  hour. Never sent to the AI and never part of the account. Unlocked for the
  day by 3 rewarded videos; the day refreshes at 12:00 noon.

## Where the data lives

| Data | Location |
|---|---|
| Original photos | App-private storage on the device (`files/vaults/<account>/`) |
| Events, memories, weather | SQLite database on the device, one per account |
| API key | Android Keystore-backed encrypted storage, per account |
| Settings, rings, weather pass, meters, export unlock | On the device, per account |
| Account | The accounts service (Firebase Authentication until the chosen backend is connected) |

Data leaves the phone only for these:

- **Describing an event or building the graph** sends that event's photos
  (downscaled to 1568 px), notes, summaries of recent events and saved
  memories to `api.anthropic.com`.
- **Free-write labels** send that event's free write, and the labels
  already used in your library, to `api.anthropic.com` (after you finish
  writing). Only the labels come back; the writing is never changed.
- **The data platforms list** sends only the analysis file's column names.
- **Place names** send a photo's coordinates to OpenStreetMap Nominatim.
- **Weather** sends coordinates or the place text, plus the date, to
  Open-Meteo.
- **Signing in** contacts the accounts service; **rewarded videos** play
  through AdMob (Google).

Cloud backup is disabled for app data. See [PRIVACY_POLICY.md](PRIVACY_POLICY.md).

## Architecture

```
lib/
  main.dart      Opens preferences and folders, picks the auth service, starts the app
  app.dart       Theme and routing; opens the signed-in account's library above
                 the navigator and shows the fingerprint lock as an overlay
  ai/            Claude API client (raw HTTP), event descriptions, timeline
                 graph builder, data platform advisor
  graph/         Force-directed layout with events pinned to a time axis
  data/          SQLite schema (v3), repositories, on-device image vault
  models/        LifeEvent, EventImage, MemoryItem, graph, ring palette, meters
  services/      Settings, accounts (+ Web3 identities, biometric lock),
                 rewarded videos (AdMob behind an interface), photo EXIF,
                 places and weather, CSV files, export, recents privacy
  state/         AppState (what the UI watches) and LibraryScope (per account)
  screens/       Tutorial, Account, Home, New event, Event detail, Memory,
                 Timeline graph, Books & rings, Your data, Data guide, Settings
  widgets/       Shared image and status widgets
test/            Unit, integration (real SQLite via FFI) and widget tests
tool/            Brand artwork (icon, store graphics, title screen) and
                 the screenshot generator
store/           Play Store listing text and graphics
owner-dashboard/ Owner-only metrics dashboard (Python, runs on localhost)
docs/            Build stage debriefs, launch checklist, brand files
.github/workflows/android.yml   CI: analyze, test, dashboard tests, build APK + AAB
```

Describing an event: `AppState.describeEvent` marks the event as describing
(a second tap is ignored), downscales its photos in a background isolate, and
`EventDescriber` sends one Messages API request with the instructions and
long-term memory (cached system prompt), the photos, the notes and recent
summaries. The JSON answer (constrained by a schema) is written onto the
latest copy of the event, so an edit made meanwhile is kept. Failures are
stored on the event with a readable message and a Retry button.

## Owner dashboard

`owner-dashboard/` is a separate, owner-only program that runs on the
owner's computer at `http://127.0.0.1:8787/` and shows account utilization,
reach vs utilization, the sign-up funnel, retention, feature use, crashes,
and the feature-test archive (review stages, the complete review catalog,
simple/complete/custom exports, and a built-in Jupyter notebook that opens
on the page).
It uses only Python's standard library. Setup, launch, and starting and
ending each hosting are in [owner-dashboard/README.md](owner-dashboard/README.md).
Until the app sends real metrics (final stage) it shows labelled demo data.

## Design Overhaul Cleanup

Before the design overhaul, each **Design Overhaul Cleanup** run removes old
UX and UI items (stale text, outdated screens and graphics, leftovers)
without restyling or restructuring the app. Each run is logged in
[docs/BUILD_STAGE_2.md](docs/BUILD_STAGE_2.md). The owner's manual review
decides whether another run is needed ("Design Overhaul Cleanup 2", then
3, and so on). Runs continue until the owner's review reaches the cleanest
version they can see, or until two full runs come back with nothing to
clean.

The UX edit itself is then done in this order:

1. Claude creates **three unique UX overhauls**.
2. The human reviewer transfers them to a **local configuration of the
   Hermes agentic model**, which creates the UI addition from the sample
   photos and the brand kit, using the dream files' specialized
   expression. This is passed through three times, the same way each time.
3. The full UI and UX combination is produced, using exactly the
   brand-kit aspects needed.
4. A final manual edit is made step by step with the **Cowork in-browser
   extension**, using its cursor ability to dictate the final changes.
5. Full alignment with the brand kit is ensured through the specialized
   skill of **Dan's Hermes model**, run locally.

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

Owner dashboard tests:

```bash
cd owner-dashboard && python3 -m unittest discover -s tests -v
```

To regenerate review screenshots with sample data (`store/screenshots/`):

```bash
flutter test tool/screenshots_test.dart
```

The app icon, store icon, feature graphic, title screen lockup and the brand
reference files in `docs/brand/` are drawn in `tool/brand/brand.html` (the
owner's approved Option A, "Core memory Polaroid"). To regenerate them after
a change (needs Node.js with Playwright):

```bash
NODE_PATH=$(npm root -g) node tool/brand/render.mjs && dart run flutter_launcher_icons
```

## Builds

Every push to `main` runs the **Android** workflow on GitHub's runners:
analyze, Flutter tests, owner dashboard tests (Python 3.9 and 3.13), then the
release APK and app bundle. The APK is published as the `latest-build`
pre-release (link above), and each run's page has an `eventlens-N` artifact
with `app-release.apk` and `app-release.aab`.

Without signing secrets these builds are signed with a debug key, which is
fine for testing but not accepted by Play. See [RELEASE.md](RELEASE.md).

## Roadmap

- **Stage 2** (in progress, started 4 October 2026): the AI maps events as a neural network, primarily a mind map
  (in function and in data exploration), with Obsidian's enterprise and
  user-level functions added for familiarity, for events added on an
  irregular schedule at the person's own pace.
- Experimental features in irregular updates, with feedback rounds; features
  voted 90% "yes" ship in their own update, and fully set-up accounts get a
  non-tradeable collectable linked to that feature.
- Paywall tiers: editing AI-owned nodes and custom connections/themes; a
  higher tier for export and backup/sync.
- Connect the chosen accounts backend (Supabase recommended), including Web3
  sign-in, and real rewarded ads.
- Brand palette before the UI/UX phase (see Design Overhaul Cleanup).
- Owner dashboard connected to real metrics: the final stage.
