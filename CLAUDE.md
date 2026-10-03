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
