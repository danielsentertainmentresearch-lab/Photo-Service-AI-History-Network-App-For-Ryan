# Memory architecture: workflow

Owner-approved plan, 6 October 2026. Builds the app's own memory file and
dream state (`docs/AI_SERVER.md` step 8), on the design decisions in the
"Memory and Dream State Brief".

## Rules for every sitting

- **Hermes never pushes to GitHub.** She writes documents and code as
  handoffs; the owner pastes them to Claude, and Claude commits them.
- **Each feature has its own branch** (owner, 12 Oct 2026). Sections 0
  and 1 (the memory storage) were built on `memory-architecture`. Section
  2, the dream pass, is a separate feature and is built on its own branch,
  `claude/quirky-wozniak-zfe9g6`, which starts from `main` with Section 1
  already in it. Every pause
  point (⏸) pushes the branch with tests passing. `main`, and the APK built
  from it, change only when a whole section is finished, so stopping at any
  pause never leaves the app half-built.
- **A section finishes in one sitting** before it merges to `main`. A
  subsection ends at a ⏸ safe pause, where the owner can check usage.

## Getting Hermes the current code

The owner downloads a fresh zip from GitHub at the start of each sitting
and gives it to Hermes, who unzips it into a new folder each time (no
login, no way to push):

- The app as it is now: `.../archive/refs/heads/main.zip`
- Work in progress: `.../archive/refs/heads/<the section's branch>.zip`
  (Section 2: `claude/quirky-wozniak-zfe9g6`; GitHub writes the `/` in a
  branch name as `-` in the zip's folder name)

(both under
`https://github.com/danielsentertainmentresearch-lab/Photo-Service-AI-History-Network-App-For-Ryan`).

## Schedule (4 to 5 days)

| Day | Sitting | Who |
|---|---|---|
| 1 | Sections 0 and 1 | Hermes drafts 0.1; Claude builds 1 |
| 2 | Section 2 | Claude, Hermes consulting |
| 3 | Section 3 | Claude, Hermes consulting |
| 4 (5) | Section 4: debugging and testing | Owner, Hermes and Claude |

## Section 0: design (docs only)

- **0.1** Hermes drafts `docs/MEMORY_ARCHITECTURE.md`: the schema (record
  types and fields, evidence event ids, versions), the compact text
  rendering for prompts, the dream pass's reply (what changes between
  versions), and the trigger rules. Owner hands it to Claude, who commits
  it. ⏸
- **0.2** Claude checks it against the code and lists anything that
  conflicts with the fixed decisions or the app; owner decides the open
  questions. ⏸
- **0.3** Hermes revises once if needed (single pass). ⏸

### Owner decisions from the review (11 October 2026)

- **A dream pass is paid from the person's daily 20 credits**, like every
  other AI feature (Section 0.2, open question on cost). Credits are ample
  even for heavy users. When the allowance is used up, the pass waits and
  runs after the next reset; nothing is lost.
- **The same hold applies to the other AI features.** Work that can't run
  because the allowance is used up waits for the next reset instead of
  failing.
- **To watch after release.** If metrics show that the limit becomes a real
  pain point, the owner may fund a group of AI-backed features from ad
  revenue. This is decided later, from the metrics.

## Section 1: storage foundation

- **1.1** Records and version history: model, database v8, repository,
  upgrade tests. ⏸
- **1.2** Keeping promises true: "Erase what the AI remembers" also erases
  the new memory and all versions; name spelling fixes reach it; the export
  includes a readable `memory.md`; memories with source `answer` migrate
  in. ⏸
- **End:** merge to `main` (nothing visible changes yet).
- **Done 11 October 2026.** Database v8, learned points and dream states
  with versions, the migration, erase, spelling fixes, and `memory.md` in
  the full export (`test/memory_v8_test.dart`).

## Section 2: the dream pass

Data starts flowing to the AI on its own here, so the privacy text ships in
the same merge. This is the longest section, so it has six pause points.
Every one is safe to stop at overnight: the work is pushed to the
section's branch with tests passing, and `main` is untouched
until 2.6.

| Step | Work | Ends at pause | Next sitting starts with |
|---|---|---|---|
| 2.1 | Dream pass prompt and structured reply schema, from Hermes's design | ⏸ P1: request builds, schema tests pass | 2.2 |
| 2.2 | Reply parser: points added, revised, retired; rejects anything outside the rules (raw free writes, support readings, Quiet names surfacing); tests with a fake AI | ⏸ P2: parser tests pass | 2.3 |
| 2.3 | Compact rendering of the memory for prompts, with its size limit; tests | ⏸ P3: rendering tests pass | 2.4 |
| 2.4 | AI server: `dream` task and its credit cost; server tests (Deno) | ⏸ P4: server tests pass | 2.5 |
| 2.5 | Coordinator: when to dream (every N events, on app open when due), one at a time, failure and retry, saving a new version; tests | ⏸ P5: whole app test suite passes | 2.6 |
| 2.6 | Privacy policy, Play data-safety answers, SUPPORT_AND_SAFETY.md; Hermes reviews the prompt wording; merge to `main` | ⏸ P6: merged, APK builds | Section 3 |

**Progress (12 Oct 2026):** 2.6 in progress: privacy policy, data-safety
answers and SUPPORT_AND_SAFETY.md updated; Hermes's wording review handed
off (`docs/handoffs/2026-10-12-claude-to-hermes-section-2-wording.md`);
merge to `main` after her reply and Dan's word. P5 reached: the coordinator
(`lib/state/dream_coordinator.dart`, `test/dream_coordinator_test.dart`). A
pass runs after every 5 newly described events, or on a milestone, at most
once a day and one at a time, on opening the app and after an event is
described. When the allowance is used up it waits for the next reset;
other failures retry after an hour; unread events stay unread until a pass
reads them. A pass is saved in one transaction. After "Erase what the AI
remembers", the next pass reads only events described afterwards. The
timeline graph unlocking is wired as a milestone; "account fully set up"
is wired when accounts are connected (`dreams.milestone()`). Dashboard:
`dream_pass_run`. P4: the server's `dream` task, 2 credits,
up to 16000 output tokens (`supabase/functions/ai/logic.ts`). P3: memory for prompts
(`lib/models/memory_prompt.dart`, `test/memory_prompt_test.dart`). P2: the reply checker
(`lib/ai/dream_reply.dart`, `test/dream_reply_test.dart`). P1: the request and reply format
(`lib/ai/dream_pass.dart`, `test/dream_pass_test.dart`). Prompts name
events `e1, e2, ...` and points `p1, p2, ...`; the checker maps them back.

### Settled with Hermes (12 October 2026)

Proposals in `docs/handoffs/2026-10-12-claude-to-hermes-section-2.md`,
all agreed by Hermes (`2026-10-12-hermes-to-claude-section-2.md`):

1. Point kinds stay the app's five: person, place, fact, preference,
   ongoing.
2. Sentiment: polarity negative, mixed, neutral or positive; intensity low,
   medium or high. A data point, never tone.
3. The reply gains `retire_active` ("no longer true"); `archive_active`
   means "true, but no longer current". Both cite `event_ids` and a
   `reason`.
4. The pass sees a short list of archived points and may revive one through
   `revise_active` with new evidence. Retired points never return.
5. A point's content is one sentence of at most 120 characters. The dream
   state holds at most 5 foundation statements and 5 themes, each at most
   140 characters. At most 10 changes of each type per pass.
6. The reply's overall `reasoning` is read while checking and never stored;
   each change's own `reason` is stored on its version row.
7. The pass reads the events described since the last pass (AI account,
   date, place, people), their confirmed and rejected labels, Honored
   marks, all active points, the archived list and the current dream state.
   Never free-write text or support readings.
8. Points about Quiet names are shown marked `[Quiet]` and may be revised
   from new events; a Quiet name never enters the foundation statements or
   themes, and the checker rejects any dream line that names one.
9. Choosing the 20 points for a prompt: points about the people and places
   in the request first (Honored marked `[Honored]`), then those with the
   most recent evidence, then those with the most evidence. Quiet points are
   left out unless the request involves that name.
10. The checker also rejects any point or dream line that repeats 6 or more
    words in a row from any free write.

If a sitting must end between pauses, Claude pushes what is done to the
branch with a note of where it stopped; nothing reaches `main`.

## Section 3: putting the memory to use

- **3.1** Rendered memory goes into the describer and graph builder. ⏸
- **3.2** "What the AI is learning" shows the real memory and what changed
  since last time, replacing the interim page. ⏸
- **3.3** The measurable learning signal (dashboard counts, label-rejection
  trend), stage log, CLAUDE.md.
- **End:** merge to `main`; the APK builds.

## Section 4: debugging and testing

- **4.1** Owner tests on the phone from a checklist Claude provides.
- **4.2** Owner, Hermes and Claude fix what comes up.
- **4.3** Hermes designs the learning page visuals and the "AI is working"
  indicators.

## Separate track

Crisis route stage B (reaching Dan) is independent; best done the day the
AI server, ntfy, email and SMS are set up (`docs/BUILD_STAGE_2.md`).
