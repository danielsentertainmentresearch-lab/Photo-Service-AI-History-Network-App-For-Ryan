# Build stage 2: in progress

_EventLens · started 4 October 2026 on the owner's command · status:
**in progress**_

This is stage 2's living document, the same way `docs/BUILD_STAGE_1.md` is
stage 1's closed one. It starts from stage 1's handover (§8 there) and will
be filled in — and eventually closed the same way — as stage 2's work lands.

## Scope, carried from the stage 1 handover

Stage 2 designs how the AI maps events as a neural network, for events added
on an irregular schedule at the person's own pace. Two models, in order of
importance:

- **Mind maps** (primary): the network works first as a mind map, both in
  how it functions and in how people explore their data — ideas branch out
  from events, people, places and themes, and exploring means following and
  opening branches.
- **Obsidian** (added on top): Obsidian's enterprise- and user-level
  functions, so the features feel familiar in some way the first time a
  person uses them.

### Experimental features and feedback programme
- Some updates will include features to test: edge-case, fringe or frontier,
  expert or advanced, experimental, unique, or new in some or all ways.
  They arrive in updates at irregular times.
- Each test feature asks people for feedback, over as many rounds as the
  ongoing review needs.
- A tested feature may ship in the next major version, or during a holiday
  or promotional event.
- A feature rated **90% "yes"** ships in its own dedicated update.
- Everyone with a fully set-up account gets recognition on their account,
  linked to that feature, as a collectable reward. Collectables can't be
  bought or sold, with real money or inside the app.

## Carried over from stage 1 (unchanged)

- AI-owned graph content (overview, chapter wording and membership, themes,
  connections) stays read-only; the person's layer is Books and rings only.
- Open source first, then non-Google services; AdMob stays acceptable for
  rewarded ads.
- **Standing reminder**: accounts backend and rewarded ads are still not
  connected — see `docs/LAUNCH_CHECKLIST.md`.

## Owner decisions on record

- **"Mind map first" means the mind model, not the drawing** (4 Oct 2026).
  The primary model is the data of the mind: what an event meant to the
  person, how it felt, and their emotional and mental state around it.
  That covers psychological and sociological data (feelings, meaning,
  mood, how they related to the people there). Subjective data points
  come before objective ones, and the event as it happened comes second
  to the event as it was experienced. Neurological, biological and purely
  factual data are out of scope for this model. The branching mind-map
  view is only one way of showing it.
- **Two parts to every event** (4 Oct 2026). The AI's account is read-only
  and primarily factual and objective: only what the photos, notes, date,
  place and memory confirm. The person's free write is theirs: a blank box
  with no prompt, label or header, and a "?" beside it explaining that it is
  for them to write freely about their experience at the event.
- **Two data areas** (4 Oct 2026). The app's data features are the
  everyday area, for fun and daily use: no raw subjective text, and no
  empty, "N/A" or unusable values. Subjective writing is represented
  through AI-made labels, each verified by a second AI pass, which become
  1/0 columns. The owner dashboard is the enterprise area. All its data is
  transformed automatically so every value is usable for analysis in its
  built-in notebook. The in-app data guide and Python platforms list stay.
- **Audience** (4 Oct 2026): everyday phone users on the Android and Apple
  app stores. The owner dashboard is the only enterprise-level part, issued
  by the owner personally. An enterprise version of the app may come later;
  none is planned.
- **The dashboard follows the app** (4 Oct 2026): every change to what the
  app does updates the owner dashboard in the same piece of work, and its
  tests run each time.

## How stage 2 has unfolded so far

| Step | What was done | Commit |
|---|---|---|
| 1 | Stage 2 opened on the owner's command | `211f0d9` |
| 2 | Mind map view: a branching, explorable view of the existing graph, first tab on the graph screen | `f312968` |
| 3 | Two parts to every event: the AI's account made factual and objective; the person's free write (database v4) | `28bf427` |
| 4 | Owner dashboard follows the app: mind map and free-write use counted in Feature use and the demo data | _this commit_ |

## Mechanisms, parts and features

### Mind map view (step 2)
- **Model** (`lib/mindmap/mind_map.dart`): builds a branching tree around
  any centre (your story, a chapter, an event, a person, a place, a theme,
  a tag or a memory) from the existing graph. Branches are grouped
  (Chapters, Events, Themes, People, Places, Tags, Memories), most
  connected first, at most 8 per group with an "N more" branch. An idea
  never branches back into one already on its path.
- **Layout**: radial. The centre sits in the middle and each ring of
  branches is further out. Rings widen when there are many leaves so
  labels keep apart.
- **Screen** (`lib/screens/mind_map_view.dart`): the first tab of the
  graph screen. Tap a branch to open or close it. **Center here** makes
  any idea the new centre, and the trail at the top leads back. **Open
  event** goes to the event. Each limb keeps one colour, taken from what
  it holds.
- Read-only, like the graph it draws on. The user layer (rings) shows on
  event branches.

### Two parts to every event (step 3)
- **The AI's account** (`lib/ai/event_describer.dart`): written in a plain,
  precise, objective voice, keeping to what the photos, notes, date, place
  and memory confirm. It leaves feelings and meaning to the person.
  Read-only, as before.
- **The free write** (`lib/widgets/free_write_box.dart`): an outlined box
  with no label, hint or header, on the New event screen and on every
  event, with a "?" on its right that explains it. On an event it saves as
  the person types and is never replaced while they are writing.
- **Storage**: `experience` on each event (database v4, migrated on
  upgrade). Included in search, in `data.json` and in the Obsidian note
  ("My free write"). Not sent to the AI yet.
- The notes field's hint no longer suggests writing how it feels; the notes
  feed the AI's factual account.

### Owner dashboard (step 4)
- New activity kinds `free_write_saved`, `mind_map_opened` and
  `mind_map_centered`, shown in Feature use. Counts only, never content.
- Demo data includes them, drawn from a separate random stream so every
  earlier demo number is unchanged.

## Next: free-write labels and the enterprise transform

- **Labels (everyday area)**: the AI reads a saved free write and proposes
  short labels for it; a second AI pass keeps only the labels the text
  supports. Each label becomes a 1/0 column in the analysis spreadsheet
  and shows in Your data. Labels don't show on the event page. The "?"
  text, privacy policy and Play data-safety answers are updated to say the
  AI reads the free write to make labels and never changes it. `data.json`
  and the Obsidian notes keep the free write as written.
- **Transform (enterprise area)**: before any owner-dashboard export or
  notebook, missing values become explicit 1/0 flags, categories become
  1/0 columns, dates gain day, weekday and hour columns, and free text
  becomes word counts and presence flags, so no cell is blank or unusable.

## Not connected yet

Unchanged from stage 1 — see `docs/LAUNCH_CHECKLIST.md`: accounts backend
(Supabase recommended) and rewarded ads (AdMob recommended) are still not
connected.
