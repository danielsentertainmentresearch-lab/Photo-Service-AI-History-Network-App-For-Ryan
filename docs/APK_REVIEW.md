# Owner phone review

Before a build stage is closed, the owner installs the latest test APK on a
phone and checks the stage's work by hand. This catches what tests and code
review can miss: wording, layout on a real screen, timing, and anything that
was never written down. A stage closes only after this review is done and
its findings are fixed or accepted.

The checklist below grows with every feature: each change that adds to or
changes what the app does adds its checks here in the same piece of work.

## Before you start

1. Install the latest build on an Android phone:
   <https://github.com/danielsentertainmentresearch-lab/Photo-Service-AI-History-Network-App-For-Ryan/releases/download/latest-build/eventlens-latest.apk>
   (allow installs from your browser if Android asks).
2. Sign in with **Continue as reviewer**.
3. In **Settings**, add your Anthropic API key (needed for AI accounts and
   free-write labels).
4. Note the build: the `latest-build` release page shows the commit it was
   built from.

## Stage 2 checklist

### New event
- [ ] The notes field is labelled **AI Notes**.
- [ ] A plain line separates AI Notes from the free-write box.
- [ ] The free-write box is blank: no label, hint or header. Only a **?**
      sits to its right.
- [ ] Tapping **?** explains the box is yours, that there is no right way to
      fill it, and that the AI only reads it to make labels.
- [ ] An event saves with only a free write (no photos, no AI Notes).

### The AI's account
- [ ] "Save and describe" writes an account that sticks to facts the
      photos, AI Notes, time and place confirm, and doesn't describe
      feelings or what the event meant.

### Event page
- [ ] The free-write box sits after the AI's account; the AI Notes heading
      shows what you wrote there.
- [ ] Text typed in the free-write box is still there after leaving the
      event and opening it again.
- [ ] No free-write labels appear on the event page.

### Free-write labels
- [ ] Within about 20 seconds of finishing a free write, **Your data** shows
      its labels in "Free-write labels" (note how long it took).
- [ ] The labels fit what you wrote; none are made up.
- [ ] Tapping a label lists its events with **Fits**, **Doesn't fit** and
      **Label again**.
- [ ] **Fits** shows "You said it fits".
- [ ] **Doesn't fit** removes the label; after **Label again** it does not
      come back on that event.
- [ ] Editing a free write makes its labels again.
- [ ] Your data shows "Events with a free write" and "Most common
      free-write label".

### Mind map (after 10 described photos unlock the graph)
- [ ] The graph screen opens on **Mind map**, with Your story in the centre.
- [ ] Tapping a branch opens and closes it; **Center here** moves the
      centre; the trail at the top leads back.
- [ ] **Open event** opens the event.

### Exports
- [ ] The basic CSV has an **AI Notes** column.
- [ ] (Full export, at 100 events) The analysis CSV has no blank cells,
      `has_location` and `has_weather` columns, and one 1/0 column per
      label. The Obsidian notes show **AI Notes** and **My free write**.

### Wording and privacy
- [ ] Tutorial, Settings privacy note and the home screen say "AI Notes".
- [ ] Settings says free writes are sent to Anthropic only to make labels.

### Everywhere
- [ ] No crashes, freezes, cut-off text or overlapping elements.
- [ ] Anything that looks wrong, unclear or missing, even if it's not on
      this list.
- [ ] The Anthropic console's usage for the session looks reasonable (free
      writes cost two small requests each).

## Review log

Add one entry per review: date, build commit, phone model and Android
version, what passed, and every issue found. Issues are fixed (or accepted
by the owner) before the stage closes.

| Date | Build | Phone | Result | Issues |
|---|---|---|---|---|
| | | | | |
