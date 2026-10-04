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

## How stage 2 has unfolded so far

| Step | What was done | Commit |
|---|---|---|
| 1 | Stage 2 opened on the owner's command | _this commit_ |

## Mechanisms, parts and features

Nothing has shipped in this stage yet. This section fills in, mirroring
`docs/BUILD_STAGE_1.md`'s structure, as stage 2 work lands.

## Not connected yet

Unchanged from stage 1 — see `docs/LAUNCH_CHECKLIST.md`: accounts backend
(Supabase recommended) and rewarded ads (AdMob recommended) are still not
connected.
