# Build stage 1: debrief

_EventLens · 2–3 October 2026 · status: complete, waiting for the owner's
review_

This document closes build stage 1. It describes every mechanism, part and
feature built in stage 1, and every notable change, addition and correction.
Later stages refer back to it only when stage 1 context is needed.

---

## 1. What EventLens is

A self-hosted photo library at its base. Photos are uploaded to record
events, and the AI (Claude, by Anthropic) writes an extremely detailed
account of each event on the person's behalf, using two kinds of memory:

- **Working memory**: the notes written at the moment, plus time and place.
- **Contextual memory**: saved long-term facts (people, places, ongoing
  situations) and summaries of recent events.

Platform: Android, built with Flutter (Dart). Repository:
`danielsentertainmentresearch-lab/Photo-Service-AI-History-Network-App-For-Ryan`
(public for now).

## 2. How stage 1 unfolded

| Step | What was done | Commit |
|---|---|---|
| 1 | Repository created; base Flutter app: events, photos, AI accounts, memory, settings | `9c19c6a` |
| 2 | Android SDK not usable in the build container (Google's download host blocked), so builds moved to GitHub Actions, whose runners include the official SDK | `6820853` |
| 3 | Release guide, privacy policy, Play listing, architecture README; app icon and store graphic | `522c00b` |
| 4 | AI timeline graph (first version: rebuilt every N described events) | `c760a5f` |
| 5 | Every build on `main` published as the `latest-build` test APK | `85c2a44` |
| 6 | Graph triggered by photo count; first take on user editing and colours (later replaced, see step 7) | `ebf8228` |
| 7 | Owner corrections: graph unlocks **once** at 10 photos and then only builds on itself; AI-owned content read-only; user layer is Books and rings only; rings unlocked by rewarded videos; accounts required after the tutorial | `e37405d`, `1a758c5` |
| 8 | Screen-by-screen tests; launch checklist and standing reminder | `68f92ab`, `ea989d3` |
| 9 | Per-account libraries, photo dates and places, On this day, export, optional weather, recent-apps privacy | `3c2a748` |
| 10 | Full debug (6 confirmed bugs fixed, see §5), Your data dashboard, export unlock at 100 events, analysis CSV and data guide, Web3 identities, owner metrics dashboard demo | this commit |

## 3. Mechanisms, parts and features

### 3.1 Recording an event
- **New event screen**: up to 10 photos from the gallery or camera, date
  and time, place, title, notes. Notes can be saved without photos.
- **Image vault** (`lib/data/image_vault.dart`): originals are copied into
  app-private storage under random file names; the AI receives downscaled
  JPEGs (longest side 1568 px), made in a background isolate.
- **Photo dates and places** (`lib/services/photo_metadata.dart`): the
  capture time (EXIF DateTimeOriginal) fills the date unless the person
  picked one; GPS coordinates are read (degrees/minutes/seconds, 0,0 treated
  as "no fix"). No location permission is ever requested.
- **Place names** (`lib/services/places_service.dart`): OpenStreetMap
  Nominatim turns coordinates into a short name ("Fallen Leaf Lake,
  California").
- **Database** (`lib/data/app_database.dart`): SQLite, version 3. v2 added
  graph snapshots; v3 added latitude, longitude and weather to events.
  Fresh installs and upgrades both migrate.

### 3.2 The AI account
- **Claude API client** (`lib/ai/anthropic_client.dart`): raw HTTPS (there
  is no official Dart SDK), retries on rate limits and server errors with
  backoff, readable errors for every failure.
- **Request** (`lib/ai/event_describer.dart`): Claude Opus 5.5 by default
  (Sonnet 5.5 optional), adaptive thinking, effort high by default (low to
  xhigh in Settings), JSON-schema structured output (title, summary,
  description, people, places, tags, memory suggestions), server-side
  fallback for false-positive refusals. The instructions and long-term
  memory form a cached system prompt.
- **Context**: the event's photos and notes, the 15 most recent event
  summaries, and all saved memories.
- **Writing rules**: first person, warm but precise; exhaustive about what
  the photos show; separates what is visible from what is inferred; never
  identifies a person from their face, only from notes or memories.
- **Reliability**: progress and errors are stored on the event (Retry
  button); an event interrupted by closing the app is marked and can be
  retried; a double tap can't start two paid requests; the result is
  written onto the latest copy of the event, so edits made meanwhile are
  kept.
- **Memory suggestions**: after each account the AI proposes durable facts;
  the person saves or dismisses each one. Facts already saved aren't
  suggested again.

### 3.3 Memory
- Memory screen: add, edit and delete long-term memories (person, place,
  fact, preference, ongoing situation).

### 3.4 Timeline graph
- **Unlock**: once, when 10 described photos exist. It never re-triggers.
- **Building on itself** (`lib/ai/graph_builder.dart`): after the unlock,
  each newly described event is placed into the existing graph. The AI
  adds chapters, connections and themes; what it already wrote is kept
  (modelled on cumulative memory, without a full "dream" rewrite). There is
  no rebuild button.
- **AI-owned and read-only**: overview, chapter wording and membership,
  themes and connections.
- **Layout** (`lib/graph/force_layout.dart`): force-directed, with events
  pinned left to right in time, positions clamped and fitted to view.
  Nodes: events, people, places, tags, themes, memories; filters per kind.
- **Screen**: locked view with progress, status bar with Retry, chapters
  tab grouped by Books, graph tab. Only the newest layout is shown if
  several run at once.

### 3.5 The person's layer: Books and rings
- **Books**: titled collections of chapters, created and named by the
  person (`GraphSnapshot.withUserLayer`).
- **Rings**: a colour ring on any event. Palette of 8 placeholder colours
  (`lib/models/ring_palette.dart`), replaced by the brand palette before the
  UI/UX phase.
- **Unlocks**: 1 colour free; the next costs 5 rewarded videos, then 6, 7,
  and so on (1 video counts as 1).
- Leaving the editor with unsaved changes asks first.

### 3.6 Rewarded videos
- AdMob behind a swappable interface (`RewardedVideoProvider`), Google test
  ad ids until real ids are set. Only fully watched videos count, including
  networks that report the reward just after the ad closes.
- Used by ring unlocks and the daily weather pass.

### 3.7 Accounts and sign-in
- Required after the tutorial. Methods: email + password; phone + password
  (SMS code confirms the number); Google; **Web3 identity** (Ethereum
  wallets such as MetaMask, Coinbase Wallet, Rainbow, Trust Wallet; Solana
  wallets such as Phantom, Solflare, Backpack; Farcaster).
- **Web3 section**: labelled "These are Web3 identities", with a **What is
  this?** sheet in plain language (what it is, how signing in works, that
  it is free and not a payment, names like sam.eth, and the recovery-phrase
  warning). The sign-in message follows EIP-4361 (Sign-In with Ethereum;
  Solana uses the same format). It connects once the accounts backend and
  WalletConnect are set up.
- **Firebase Authentication** is wired today; the backend switch waits on
  the owner's choice (Supabase recommended).
- **Review builds** offer "Continue as reviewer".
- **Fingerprint/face lock** (optional): asks when the app opens and again
  after 30 seconds away. The lock covers the screens without closing the
  library, so work in progress continues.
- **Delete account** in Settings (Google Play requirement).

### 3.8 Separate libraries per account
- Each account on a shared phone gets its own database file, photo folder,
  API key, settings, ring unlocks, weather pass, hidden meters and export
  unlock (`lib/state/library_scope.dart`).
- The library from before accounts existed is handed to the first account
  that signs in.
- The library is provided above the app's navigator, so every screen can
  reach it; signing in as someone else starts from a clean screen stack.

### 3.9 Your data and export
- **Your data screen** (`lib/screens/data_screen.dart`): 19 meters for the
  whole library (events, photos, AI accounts and their share, people,
  places, tags, memories, time covered, busiest month, most recorded person,
  most recorded place, photos per event, words by the AI, words in notes,
  graph status, chapters, books, rings, events with weather). Any meter can
  be hidden and brought back. Free, with no ads.
- **Basic CSV**: free for everyone at any size of library.
- **Full export**, unlocked at **100 events** (kept unlocked afterwards):
  - a zip with the original photos;
  - an Obsidian vault: one note per event, linked to people, places, tags,
    chapters, books and themes;
  - `data.json` with everything;
  - the basic CSV;
  - the analysis CSV and its column guide.

  Photos are streamed from disk on a background isolate, so large libraries
  don't run out of memory.
- **Preview banner** below 100 events: what the full export holds, with a
  progress bar.
- **Analysis CSV** (`lib/services/data_files.dart`): 30 typed, snake_case
  columns (dates in ISO 8601, numbers, 0/1 flags, `|`-separated lists),
  ready for pandas.
- **Explore your data guide**: five plain steps (Anaconda, send the file,
  open a notebook, load, try an idea), with a note that it is for fun and
  that Python knowledge is recommended, plus a link to jupyter.org.
- **Python platforms list**: generated by the app's AI from the column
  names only, marked "Fits" or "Likely". It says "None determinable" when
  the AI can't name one. Without a key or a connection it shows the most
  likely platform. The answer is cached until the columns change.

### 3.10 Optional weather
- A per-event weather section (Open-Meteo): condition, temperature,
  precipitation and wind for the event's place and hour. Uses photo
  coordinates or looks up the typed place. Never sent to the AI and not
  part of the account. Changing the place or time clears stale weather.
- **Daily pass**: 3 rewarded videos unlock lookups until the next 12:00
  noon, calculated correctly on daylight-saving days.

### 3.11 Timeline, search and On this day
- Home timeline grouped by month, with status chips.
- Full-text search across titles, notes, accounts, people, places and tags.
- **On this day** card: up to 3 events from today's date in earlier years.

### 3.12 Privacy and security
- Photos, notes, accounts and memories stay on the phone; Android cloud
  backup is off.
- API key in Keystore-backed encrypted storage, per account.
- Hidden from the recent-apps screen by default (`FLAG_SECURE`), which also
  blocks screenshots; a toggle in Settings.
- Outbound data limited to the services listed in the README and privacy
  policy. The policy and the Play data-safety answers are kept in step
  with the code.

### 3.13 Settings
- API key, model, effort; account (sign out, biometric lock, delete
  account); "Your data and export" link; hide in recent apps.

### 3.14 Owner metrics dashboard (demo)
- `owner-dashboard/`: owner-only, runs on the owner's computer at
  `http://127.0.0.1:8787/`, unreachable from other machines. Uses only
  Python's standard library.
- Measures: accounts created, active accounts, utilization rate,
  DAU/WAU/MAU and stickiness, sessions, median session length, crash-free
  sessions; reach vs utilization (install → tutorial → account → first
  event → first AI account → graph → 100 events); the sign-up funnel and
  method mix (including Web3); weekly retention; utilization depth;
  feature use; crashes by version and top crashes; lifetime totals. 7, 30
  and 90 days or all time. Panels can be hidden and restored.
- Commands: `setup`, `start` (in a window or `--background`), `status`,
  `stop`, `demo`, `export-demo`, `reset`. Double-click launchers for
  Windows, macOS and Linux. Ingest API with a token, all-or-nothing
  batches.
- Shows labelled demo data until the app sends real metrics (final stage).

### 3.15 Build, release and store
- **CI** (`.github/workflows/android.yml`): analyze, Flutter tests, owner
  dashboard tests on Python 3.9 and 3.13, then release APK and app bundle.
  Newer pushes cancel superseded runs.
- **Test APK**: the `latest-build` pre-release, updated on every push.
- **Signing**: debug-signed until the upload key and secrets are added
  (RELEASE.md).
- **Store**: listing text, data-safety answers, icon, feature graphic, and
  generated review screenshots (`tool/screenshots_test.dart`).

## 4. Owner decisions on record

- AI-owned graph content stays read-only; the person's layer is Books and
  rings only.
- The graph unlocks once at 10 described photos and builds on itself; there
  is no rebuild.
- Rings: 1 free, then 5, 6, 7… rewarded videos.
- Weather only (no mood), optional, separate from the AI journal, 3 videos
  per day, refreshing at 12:00 noon.
- Export: free CSV; the full export unlocks at 100 events; the paywall stage
  adds a higher ("+1") tier for export.
- The Your data meters are free for everyone, with no ads.
- Platform preference: open source first, then non-Google; AdMob is
  acceptable for rewarded ads.
- Crash reporting platform: not chosen yet (options in the checklist).
- The owner dashboard is the final stage; UX ranks above UI; distribution is
  by direct message or email only.
- Standing reminder at the end of every stage until accounts and rewarded
  ads are active.

## 5. Corrections and fixes in stage 1

Found while building:
- `lib/` was ignored by a parent `.gitignore`; copied in explicitly.
- Graph nodes drifted off-screen: positions clamped, fit-to-view added.
- Events lost their time order in the graph: x position pinned to time.
- A text controller was disposed too early in the Book title dialog.
- The unlock sheet's button row overflowed on small screens.
- Timing-dependent tests made to wait for real conditions.
- A blank AdMob app id from an empty secret: falls back to the test id.
- A `TextDirection` name clash with the intl package.

Found by the full debug at the end of stage 1 (all fixed, with tests):
1. **Critical**: in the previous demo APK (build #10), screens opened from
   Home (Memory, Settings, Graph, an event) couldn't reach the account's
   library and would crash. The library now sits above the navigator.
2. With the fingerprint lock on, leaving the app closed the library, which
   could lose an AI result. The lock is now an overlay, with a 30-second
   grace period.
3. Editing an event while the AI was describing it could wipe the account,
   or the account could overwrite the edit. Both now write onto the latest
   copy.
4. Changing an event's place kept the old place's coordinates and weather.
   They are now cleared.
5. The noon weather reset drifted by an hour on daylight-saving days. It now
   uses calendar dates.
6. Exported notes differing only in capital letters could overwrite each
   other when unzipped, and chapters with the same title merged. Names are
   now unique regardless of case.

Also hardened: export streams photos instead of loading them all into
memory, late reward callbacks from ad networks are counted, a double tap
can't start two AI requests, and only the newest graph layout is shown.
A layout overflow on the Your data screen was caught by the new tests and
fixed.

## 6. Verification

- `flutter analyze`: no issues.
- `flutter test`: 74 tests passing on two consecutive runs. They cover
  every screen, the database, AI requests (mocked), graph building, export,
  CSV files, meters, Web3 messages, rewarded unlocks, per-account libraries,
  and the regressions above.
- Owner dashboard: 11 tests passing on two consecutive runs (measures on
  exact data, demo sanity, ingest validation, server routes and tokens,
  background start/status/stop, the self-contained demo page).
- CI builds the APK on GitHub's Android SDK and publishes it.
- Not testable in the build environment (check on a phone): camera and
  gallery, fingerprint/face, live AI with a real key, real ads, the live
  map and weather services, and recent-apps hiding.

## 7. Not connected yet

From `docs/LAUNCH_CHECKLIST.md`:
- **Accounts backend**: recommended Supabase. It also verifies Web3 sign-in.
- **Rewarded ads**: recommended AdMob.
- Reown (WalletConnect) project id for Web3; SMS provider; Google OAuth
  client; ad consent; app-ads.txt; Play Console; upload key; privacy policy
  URL; support email; crash reporting (not chosen); payments for the
  paywall; Nominatim and Open-Meteo plans before a commercial launch; brand
  palette; metrics source for the owner dashboard.

## 8. Handover to stage 2

Stage 2 designs how the AI maps events as a neural network, modelled on
Obsidian's linked graph and on mind maps, for events added on an irregular
schedule at the person's own pace. Stage 2 starts only on the owner's
command.
