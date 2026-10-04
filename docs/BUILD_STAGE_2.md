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

## How stage 2 has unfolded so far

| Step | What was done | Commit |
|---|---|---|
| 1 | Stage 2 opened on the owner's command | `211f0d9` |
| 2 | Mind map view: a branching, explorable view of the existing graph, first tab on the graph screen | _pending_ |

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

## Next: the inner layer (proposed, awaiting owner confirmation)

Following the decision above, the next step gives each event a
subjective layer and makes it what the mind map branches on:
- **Feelings**: named emotions with how strong they were and whether they
  were pleasant or not.
- **Meaning**: what the event meant to the person, in their own terms.
- **State**: mood, energy and stress around the event.
- **Social**: who they felt close to or distant from, and the roles and
  belonging the event touched.

Each point records whether the person said it or the AI inferred it from
their notes. Nothing is inferred from faces or photos. The mind map gains
Feelings, Meanings and Social branches, so a feeling such as "calm" can be
the centre and branch out to every event that felt that way. This data is
sensitive, stays on the phone like the rest of the library, and needs the
privacy policy and Play data-safety answers updated before release.

## Not connected yet

Unchanged from stage 1 — see `docs/LAUNCH_CHECKLIST.md`: accounts backend
(Supabase recommended) and rewarded ads (AdMob recommended) are still not
connected.
