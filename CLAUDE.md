# Notes for Claude sessions on this repo

- Flutter app (Android). Run `flutter analyze` and `flutter test` before
  pushing; CI builds the APK and publishes the `latest-build` pre-release.
- AI-owned graph content (overview, chapters, themes, connections) must
  stay read-only for users. The user layer is
  Books and rings only (`GraphSnapshot.withUserLayer`).
- Owner preference: open source first, then non-Google services (except
  rewarded ads, where AdMob is acceptable).
- **Standing reminder**: at the end of every build stage, until both are
  active, remind the owner that **accounts** and **rewarded ads** are not
  connected, name the currently recommended platform for each (see
  `docs/LAUNCH_CHECKLIST.md`), add a line to its reminder log, and update
  the shared "EventLens Launch Checklist" page. Work on the checklist itself
  starts after build stage 3 closes (owner's target; slightly earlier is
  possible).
- **Build stage 1 has ended** (owner sign-off 4 Oct 2026, branch
  `build-stage-1`; deliverable: `docs/BUILD_STAGE_1.md`). **Build stage 2
  started 4 Oct 2026** on the owner's command; its living deliverable is
  `docs/BUILD_STAGE_2.md`. Later stages build from stage 1 and refer back to
  it only when its context is needed. Each stage starts only on the owner's
  command.
- **Stage plan** (owner, 4 Oct 2026): stage 2 is the neural-network event
  mapping (mind model first, then Obsidian functions); the owner's full-app
  review happens during stage 2, before it closes. Stage 3 (likely): the
  parts and features that run on the AI backbone. Stage 4: the final LLM
  build. Launch checklist work starts after stage 3 closes.
- **Project order** (owner, 4 Oct 2026): (1) the build phase, stages 1-4;
  the current focus is building the app only. (2) All checklists, completed
  between the build phase and UX/UI (launch checklist work may start after
  stage 3). (3) UX and UI brainstorming and implementation, including the
  design overhaul process in the README. (4) Confer with the owner on a beta
  launch that clears Google Play's requirements, for a first app launching
  with no existing audience.
- **Who does what** (owner rule, 4 Oct 2026; README "Who does what"): all
  UI and UX creations, changes and modifications are done only by the owner
  and their local Hermes model (Gemini API, `dream.md`); Hermes handles
  everything expressive, creative or artistic. Claude does all
  developer-side work and does not make UI/UX changes. A session opened for
  Hermes (or one of her agents) says so at its start.
- **Review handoff** (owner, 4 Oct 2026): after each manual review, a new
  Claude session starts from the session summary the owner adds to the repo
  as standard practice, written by Hermes as a handoff. Start from it.
- **Brand artwork** (owner-approved Option A, "Core memory Polaroid"): the
  app icon, store graphics and launch title screen come from
  `tool/brand/brand.html` via `tool/brand/render.mjs`. The Scaffold logo is
  always used exactly as supplied. Brand files are in `docs/brand/`.
- Export rules: basic CSV free for all; full export unlocks at 100 events
  (sticky); a higher paywall tier for export is added in the paywall stage.
  The Your data meters stay free with no ads. Before 100 events, a sneak
  peek at the full export's insights opens with 3 rewarded videos (2
  insights, 12 hours, once every 48 hours) or a $1 pass (all 5, 72 hours;
  purchase not connected until Play Billing): `lib/services/insight_pass.dart`.
- **AI server** (owner decision, 5 Oct 2026): the AI runs through the
  owner's server (`supabase/functions/ai/`, `docs/AI_SERVER.md`) when
  `AI_SERVER_URL` is set, so users need no Anthropic key. Every AI feature
  takes an `AIClient` (`lib/ai/ai_client.dart`). The server stores usage
  counts only, never content; memories stay on the phone. Its follow-up
  steps are scheduled in `docs/AI_SERVER.md`. Test it with
  `deno test logic_test.ts` from `supabase/functions/ai/`.
- **Memory is the AI's** (owner rule): people never add, edit or delete
  memories. They can fix name spellings only (`lib/models/name_spelling.dart`)
  and erase all of it at once from the button inside the privacy policy
  (`<!-- erase-ai-memory-button -->` in PRIVACY_POLICY.md, which the app
  bundles and shows). Keep that section and marker when editing the policy.
- `owner-dashboard/` is owner-only (Python stdlib, localhost). Run its
  tests with `python3 -m unittest discover -s tests` from that folder.
- **Dashboard follows the app** (owner rule, stage 2): whenever a change adds
  to or changes what the app does, update the owner dashboard to match in
  the same piece of work (activity kinds, feature use, demo data) and run its
  tests every time. The dashboard only ever receives counts, never what
  people wrote.
- Audience: everyday phone users (Android and Apple app stores); the app's
  data features are for fun and daily use. The owner dashboard is the only
  enterprise-level part and is issued by the owner personally. No enterprise
  version of the app is planned. The in-app data guide and Python platforms
  list stay.
- **Everyday data files never have blanks** (owner rule, stage 2): every
  cell in the in-app analysis file must work in a beginner's Jupyter
  notebook. Unknown text gets a word marker ("unknown", "none", "not looked
  up"), unknown numbers get `unknownNumber` (-999) so number columns stay
  numeric, and `has_` 0/1 columns say which rows have real values.
  Subjective writing never goes into the data files as text; it appears
  only as AI-made, AI-checked labels, one 1/0 column per label. Review this
  after three months of usage metrics.
- Stage 2 (in progress) network model: **mind maps first** (primary in
  function and data exploration), then **Obsidian** enterprise/user-level
  functions added for familiarity. "Mind map" means the **mind model**:
  subjective, psychological and sociological data about what an event
  meant and how it felt (emotions, meaning, mood, social closeness), ahead
  of objective or factual data. It does not mean the drawing. Neurological
  and biological data are out of scope. See `docs/BUILD_STAGE_2.md`. Experimental features ship in irregular
  updates with feedback rounds; a 90% "yes" vote earns a dedicated update;
  fully set-up accounts get a collectable linked to the feature that can
  never be bought or sold.
