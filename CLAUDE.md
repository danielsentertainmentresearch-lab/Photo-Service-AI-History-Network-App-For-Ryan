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
  the shared "EventLens Launch Checklist" page.
- **Build stage 1 has ended** (owner sign-off 4 Oct 2026, branch
  `build-stage-1`; deliverable: `docs/BUILD_STAGE_1.md`). **Build stage 2
  started 4 Oct 2026** on the owner's command; its living deliverable is
  `docs/BUILD_STAGE_2.md`. Later stages build from stage 1 and refer back to
  it only when its context is needed. Each stage starts only on the owner's
  command.
- Export rules: basic CSV free for all; full export unlocks at 100 events
  (sticky); a higher paywall tier for export is added in the paywall stage.
  The Your data meters stay free with no ads.
- `owner-dashboard/` is owner-only (Python stdlib, localhost). Run its
  tests with `python3 -m unittest discover -s tests` from that folder.
- Stage 2 (in progress) network model: **mind maps first** (primary in
  function and data exploration), then **Obsidian** enterprise/user-level
  functions added for familiarity. Experimental features ship in irregular
  updates with feedback rounds; a 90% "yes" vote earns a dedicated update;
  fully set-up accounts get a collectable linked to the feature that can
  never be bought or sold.
