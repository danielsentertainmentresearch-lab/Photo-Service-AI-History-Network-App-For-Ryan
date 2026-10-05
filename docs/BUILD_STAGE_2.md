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
- **No blanks in everyday data files** (4 Oct 2026). Blank cells cause
  too many problems for beginners in Jupyter and other Python tools, so
  every unknown in the in-app analysis file is marked: words for text
  ("unknown", "none", "not looked up") and -999 for numbers, with
  `has_location` and `has_weather` 0/1 columns for filtering. A basic
  marking is enough for everyday users; to be reviewed after three months
  of usage metrics.
- **Audience** (4 Oct 2026): everyday phone users on the Android and Apple
  app stores. The owner dashboard is the only enterprise-level part, issued
  by the owner personally. An enterprise version of the app may come later;
  none is planned.
- **Stage plan** (4 Oct 2026). Stage 2 is the neural-network event
  mapping described above, and the owner's full-app review happens during
  stage 2, before it closes (checkpoint `710e751`). The stages after it, as
  planned now: **stage 3** (likely) builds the parts and features that run
  on the AI backbone; **stage 4** is the final LLM build. Each still starts
  only on the owner's command.
- **Project order** (4 Oct 2026). 1. The build phase (stages 1 to 4);
  for now the work is building the app only. 2. All checklists, completed
  between the build phase and UX/UI. 3. UX and UI brainstorming and
  implementation (the design overhaul process in the README). 4. Planning a
  beta launch with the owner that clears Google Play's requirements, for a
  first app with no existing audience.
- **Launch checklist timing** (4 Oct 2026): work on the launch checklist
  (accounts, rewarded ads and the rest of `docs/LAUNCH_CHECKLIST.md`) begins
  after build stage 3 closes; slightly earlier is possible, but that is the
  target.
- **The dashboard follows the app** (4 Oct 2026): every change to what the
  app does updates the owner dashboard in the same piece of work, and its
  tests run each time.

## How stage 2 has unfolded so far

| Step | What was done | Commit |
|---|---|---|
| 1 | Stage 2 opened on the owner's command | `211f0d9` |
| 2 | Mind map view: a branching, explorable view of the existing graph, first tab on the graph screen | `f312968` |
| 3 | Two parts to every event: the AI's account made factual and objective; the person's free write (database v4) | `28bf427` |
| 4 | Owner dashboard follows the app: mind map and free-write use counted in Feature use and the demo data | `98f6c89` |
| 5 | Free-write labels (annotated, checked by the app, reviewed by a second AI pass), confirm / reject / label again, no blanks in the analysis file, label quality on the dashboard | `3a1737e` |
| 6 | Labels: no undo in any form, no notes in the flow, every pass a first pass | `086c9b6` |
| 7 | Your data: the Free-write labels card above Export (owner's choice B) | `a041d90` |
| 8 | Design Overhaul Cleanup, run 1 (see below) | `9c424bd`, `7be82a7` |
| 9 | Brand artwork: app icon, store graphics and an opening title screen from the owner's approved logo option (see below) | `4a9be3c` |
| 10 | Launch crash on the owner's phone (moto g 2025, Android 16): the app closed on opening in build #30. Code shrinking (R8) turned off; build #33 opens. Shrinking stays off until keep rules are written and tested on the phone | `845b905` |
| 11 | Checkpoint: the app opens on the owner's phone; the owner's manual review (pen and paper) starts. The session pauses here. A new session means the review is done, and it starts from the owner's session summary, written by Hermes as a handoff and added to the repo | (this commit) |
| 12 | Post-review fix 1, step 1 (Hermes's proposal, adopted with Claude's changes): every AI feature talks to an `AIClient` interface (`lib/ai/ai_client.dart`) instead of Anthropic directly. `AnthropicClient` is now `AnthropicAIClient`, one backend behind it; errors are `AIException`. No behaviour change. Next: a client for the owner's own AI server, so users no longer need an Anthropic API key | (this commit) |
| 13 | Post-review fix 1, step 2 (owner's executive decision): the owner's AI server, so users need no Anthropic key. Supabase Edge Function (`supabase/functions/ai/`) checks the sign-in, applies a daily allowance (20 credits; describe 4, graph 3, label 1, advice 1), picks the model and caps cost, refunds failed requests, and accepts signed AdMob reward callbacks once ads are on. Stores usage counts only, never content. App: `ProxyAIClient` (`lib/ai/ai_server.dart`), used when `AI_SERVER_URL` is set; Settings shows the allowance instead of the key and model choices. Dashboard: `ai_allowance_reached` and `ai_topup` counts. Setup and the schedule of follow-up steps: `docs/AI_SERVER.md` | (this commit) |
| 14 | Post-review fix 2 (owner's review): on New event, the old "What's happening?" notes box is now a read-only area marked "AI writing generates here": the account is the AI's alone, factual and objective, and nobody types there. The cursor starts in the person's free write. New events carry no notes; the AI writes from the photos, time, place and memory. The free write's "?" no longer mentions an API key; the tutorial matches | (this commit) |
| 15 | Post-review fix 3 (owner's review): the AI asks who or where instead of the person typing notes. When it writes an account it may ask up to 3 short questions about people or places it could only describe neutrally ("Who is the friend in the red jacket?"), shown on the event as "The AI asks". Optional: an answer is saved as a memory (source `answer`, a temporary home until the app's own memory file exists, `docs/AI_SERVER.md` step 8) and added to the event's notes for "Rewrite with AI"; Skip removes the question. Edit details no longer has a notes box. Database v6 (`questions`). Dashboard: `ai_question_answered` and `ai_question_skipped`. To show at the end of the tour once it exists | (this commit) |
| 16 | Post-review improvement 1 (owner's review): a sneak peek at the full export's insights before 100 events, from "Preview: full export" on Your data. 3 rewarded videos open 2 insights (Your rhythm, Feelings by person) for 12 hours, once every 48 hours. The $1 pass opens all 5 (adds Who goes together, Weather and your days, A label on the rise) for 72 hours; buying again adds 72 hours. Worked out on the phone from the person's own events; feelings use only confirmed labels. The $1 purchase is built in but not connected until Play Billing (paywall stage). Dashboard: `insight_peek_opened`, `insight_pass_bought` | (this commit) |
| 17 | Post-review fix 4 (owner's rule, stated twice): memory is the AI's, so the Memory page no longer lets people add, edit or delete memories. It is now "What the AI is learning": read-only counts of people, places and facts it knows, connections and threads from the timeline graph, and some of what it remembers, a few at a time, rotating at three unplanned times a day so it keeps changing between visits. Interim until the app's own memory file and dream state (`docs/AI_SERVER.md` step 8) | (this commit) |
| 18 | Post-review fix 5 (owner decision): people can't edit memory, but two safe controls replace it. **Name spellings** (Settings): fix how a person or place is spelled everywhere it appears (events, accounts, memories, timeline graph); only spelling fixes are accepted (a few letters or capitals, same number of words), and likely typos are suggested (a rare near-twin of a common name). **Erase what the AI remembers**: an all-or-nothing button inside the privacy policy, which the app now shows (Settings → Privacy policy, bundled PRIVACY_POLICY.md), directly under the promise and the list of consequences; it needs ERASE typed and leaves events, photos, accounts and free writes. Policy and Play data-safety answers updated. Dashboard: `name_spelling_fixed`, `ai_memory_erased` | (this commit) |

## First in the next session: a crisis intervention route

Owner, 5 Oct 2026: the app is built around emotional writing and must have
a crisis intervention route before anything else. **This is the first item
of the next work session**, ahead of the memory file and dream state.

Points to settle with the owner before building:

- **What triggers it**: signs of acute distress or risk of harm to self or
  others in a free write, an answer or a label (for example a label pass
  that also flags risk), and a way to reach help at any time without a
  trigger (an always-available "Need help now?" entry).
- **What it shows**: crisis lines for the person's country (for example 988
  in the US, 116 123 Samaritans in the UK and Ireland, 000 / Lifeline 13 11
  14 in Australia; a findahelpline.com link elsewhere), emergency number,
  and a short, warm message. Never a diagnosis, never blocking the app.
- **Privacy**: whether any signal is kept, counted or sent anywhere. The
  dashboard would receive counts only, never content, if at all.
- **Tone and review**: wording reviewed by the owner (and ideally someone
  with crisis-support experience) before release; tested so it shows when
  it should and stays quiet otherwise.
- **Store requirements**: Google Play policies for apps handling sensitive
  topics.

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

### Free-write labels (step 5)
- **How labels are made** (`lib/ai/experience_labeler.dart`), in the
  background after someone finishes a free write, with their own API key:
  1. Claude annotates the writing: the groups of words that carry the
     experience, what each means and its sentiment (positive, negative,
     mixed or neutral), then combines the annotations into 1 to 6 short
     labels, each with its sentiment and the words it came from.
  2. The app's own check drops any label whose words aren't in the
     writing.
  3. A second Claude request reviews each remaining label against the
     writing, its words and its sentiment, and only supported labels are
     kept.
  The writing is treated as data, never as instructions, and is never
  changed. Effort is low (a classification task); the model is the one
  chosen in Settings.
- **Where labels show**: only in Your data and the analysis file, never on
  the event page, so they don't steer what someone writes next. In Your
  data, the "Free-write labels" card comes first, above Export (owner's
  choice, 4 Oct 2026), and two meters show "Events with a free write" and
  "Most common free-write label".
- **Fits / Doesn't fit / Label again**: tapping a label in Your data lists
  its events, each with its free write. "Fits" confirms the label;
  "Doesn't fit" removes it. Both are final: there is no undo in any form,
  and once a choice is made only "Label again" remains. The sheet shows no
  notes, badges or reminders of earlier choices, so nothing nudges the
  next decision.
- **Every pass is a first pass** (owner decision, 4 Oct 2026): "Label
  again", and labelling after the writing changes, run exactly like the
  first time. The AI is told nothing about the event's earlier labels or
  the person's choices, so any label, including one turned down before,
  can come back and is shown as new. The result replaces the event's labels
  and choices. Labels stay AI-made and AI-checked; people don't type their
  own.
- **Storage**: database v5 adds `experience_labels`, `labelled_experience`,
  `confirmed_labels` and `rejected_labels` to events, on the phone.
- **Analysis file**: never a blank cell. Unknown text is a word ("untitled",
  "unknown", "none", "not looked up"), unknown numbers are -999, and
  `has_location`, `has_weather` and `free_write_words` columns were added.
  After the fixed columns comes one 1/0 column per label, titled with the
  label itself. The free write never appears as text.
- **Privacy**: the "?" text, privacy policy, Settings, tutorial, README and
  Play data-safety answers say the free write is sent to Anthropic only to
  make its labels.
- **Owner dashboard**: `free_write_labelled`, `label_confirmed`,
  `label_rejected` and `label_relabelled` counts, and a "Free-write labels"
  panel with the share marked not right (Healthy up to 10%, Watch up to
  20%, Needs attention above), the signal to change the labelling
  instructions. Counts only, never content.

## Brand artwork (step 9)

- **Chosen** (owner, 4 Oct 2026): Option A, "Core memory Polaroid", of three
  options made from the Scaffold brand kit (first priority) and the
  Scaffold logo (second). The logo is used exactly as supplied, with only
  its plain background removed. The pink heart after the name became the
  brand kit's healing heart, and the "CORE MEMORY · 2010" banner is the
  lilac tape on the icon.
- **Where it is used**: the Android launcher icon (adaptive: a deep-teal
  background with the torn edge, the Polaroid in the safe zone), the Play
  Store icon and feature graphic, and a title screen at every launch (the
  stacked lockup with the banner, about two seconds, a tap skips it, the
  same off-white as the Android launch background).
- **Sources**: `tool/brand/brand.html`, rendered by `tool/brand/render.mjs`
  with the fonts in `tool/brand/fonts`. Brand reference files, including a
  one-page brand sheet, are in `docs/brand/`.
- The owner dashboard is unchanged: a title screen adds nothing to count.

## Design Overhaul Cleanup

_Further runs wait until the build phase and the checklists are done
(project order, 4 Oct 2026)._

The cleanup of old UX and UI items before the design overhaul (process in
the README). It removes what is stale; it does not restyle or restructure
the app. Runs repeat ("Design Overhaul Cleanup 2" and so on) until the
owner's manual review finds the cleanest version, or two full runs in a row
come back with nothing to clean.

### Run 1 (4 Oct 2026)

In the order done:

1. **Owner dashboard exports made analysis-ready** (`9c424bd`). Every
   export (archive, feature, analysis kit) and the built-in notebook now
   pass through `features.analysis_ready`: unknown numbers become -999 with
   a `_known` 0/1 column, categories gain one 1/0 column per value, dates
   gain `_known`, `_weekday` and `_hour` columns, and empty text becomes
   "none". No exported cell is blank (new test). Free text such as review
   comments stays as text for the owner to read.
2. **Tutorial**: two stale lines removed: notes covering how it feels, and
   the AI writing a narrative (it writes a factual account) (`7be82a7`).
3. **Data guide**: the people example skips the "none" marker, so it no
   longer counts "none" as a person (`7be82a7`).
4. **Mind map**: the open/close badge on chapter and story pills sat over
   the title; it now sits on the pill's corner (`7be82a7`).
5. **Store screenshots** regenerated; the graph shot now shows the mind
   map, the first tab (`7be82a7`).
6. **README intro**: notes no longer said to cover how it feels
   (`7be82a7`).

Checked and clean: no TODO, placeholder or test text in the app; both icon
assets are used.

Seen but left for the owner's review (outside a cleanup of old items):
the welcome line's "full story" wording, the store listing's marketing
copy, the tutorial not yet mentioning the mind map or the free write, and
the README architecture line that still says database v3 (it is v5).

## Not connected yet

Unchanged from stage 1 — see `docs/LAUNCH_CHECKLIST.md`: accounts backend
(Supabase recommended) and rewarded ads (AdMob recommended) are still not
connected.
