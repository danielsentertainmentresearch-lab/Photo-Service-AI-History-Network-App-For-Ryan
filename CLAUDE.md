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
- **Brand artwork** (owner-approved Option A, "Core memory Polaroid"): the
  app icon, store graphics and launch title screen come from
  `tool/brand/brand.html` via `tool/brand/render.mjs`. The Scaffold logo is
  always used exactly as supplied. Brand files are in `docs/brand/`.
- Export rules: basic CSV free for all; full export unlocks at 100 events
  (sticky); a higher paywall tier for export is added in the paywall stage.
  The Your data meters stay free with no ads.
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
