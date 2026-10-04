# Handoff: Claude to Hermes, before the owner's manual review

_4 October 2026 · from Claude (development) to Hermes (UI, UX and
creative work) · priority: read before starting the review work_

## 1. Where the project is

- **App**: EventLens, a Flutter Android app. Repository:
  `danielsentertainmentresearch-lab/Photo-Service-AI-History-Network-App-For-Ryan`.
- **Build stage 2 is in progress**: the neural-network event mapping
  (the mind model first, then Obsidian-style functions). Its log is
  `docs/BUILD_STAGE_2.md`.
- **The app now opens on the owner's phone** (moto g 2025, Android 16).
  Builds up to #30 closed on opening; the cause was code shrinking, which
  is now off. Every build from **#33** on works. Install link:
  <https://github.com/danielsentertainmentresearch-lab/Photo-Service-AI-History-Network-App-For-Ryan/releases/download/latest-build/eventlens-latest.apk>
- **Checkpoint** (stage 2 log, step 11): the owner is now doing a full
  manual review of the app with pen and paper. The Claude session has
  paused. The next Claude session starts from your handoff.

## 2. The owner's plan (recorded 4 Oct 2026)

- **Stages**: 1 base app (closed) · 2 event mapping (now) · 3 (likely)
  parts and features on the AI backbone · 4 the final LLM build.
- **Project order**: build phase (stages 1 to 4) → all checklists → UX
  and UI brainstorming and implementation → beta launch planning that
  clears Google Play's requirements.
- So UX/UI findings from this review are **collected now and carried out
  in the UX/UI phase**, unless the owner says otherwise.

## 3. Who does what

- **You (Hermes)**: all UI and UX creations, changes and modifications,
  and everything expressive, creative or artistic, with the owner.
- **Claude**: all developer-side work: Dart code, the database, the AI
  pipeline, the owner dashboard, builds, releases and build settings.
- Please **don't push to `main`**: every push there publishes a new test
  APK to the owner's phone link. Work in your contained fork, and bring
  anything for the repository through a pull request or the owner.

## 4. Owner rules that affect UI and UX

Full list: `CLAUDE.md` in the repository. The ones that touch screens:

- The AI's content (overview, chapters, themes, connections, the AI's
  account of each event) is **read-only** for people. Their own layer is
  Books and rings only.
- The **free write** box has no label, hint or header, only a "?" beside it.
- **Free-write labels** show only in Your data and the analysis file,
  never on the event page.
- The **Scaffold logo** is always used exactly as supplied. Brand
  artwork follows the approved Option A, "Core memory Polaroid"
  (`docs/brand/`, `tool/brand/`).
- Everyday data files never have blank cells.
- The Your data meters stay free, with no ads.

## 5. Items already waiting for the owner's review

From Design Overhaul Cleanup run 1 (stage 2 log):

- the welcome line's "full story" wording;
- the store listing's marketing copy;
- the tutorial does not yet mention the mind map or the free write;
- a README architecture line still says database v3 (it is v5).

## 6. What Claude needs back (your handoff)

Add it to `docs/handoffs/` (or give it to the owner to add), named like
`YYYY-MM-DD-hermes-to-claude-review.md`. For each finding:

1. **Where**: the screen or feature.
2. **What happens now**, and **what should happen**.
3. **Type**: `build` (a bug, logic, data or a missing feature; Claude's)
   or `ux-ui` (wording, layout, visuals, flow; yours, for the UX/UI phase).
4. **Priority**, if the owner gave one.

Also include any owner decisions made during the review, and where your
own records of this work are kept.
