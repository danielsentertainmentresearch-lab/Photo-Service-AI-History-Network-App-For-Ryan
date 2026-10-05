# Memory architecture: workflow

Owner-approved plan, 6 October 2026. Builds the app's own memory file and
dream state (`docs/AI_SERVER.md` step 8), on the design decisions in the
"Memory and Dream State Brief".

## Rules for every sitting

- **Hermes never pushes to GitHub.** She writes documents and code as
  handoffs; the owner pastes them to Claude, and Claude commits them.
- **All work happens on the branch `memory-architecture`.** Every pause
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
- Work in progress: `.../archive/refs/heads/memory-architecture.zip`

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

## Section 1: storage foundation

- **1.1** Records and version history: model, database v8, repository,
  upgrade tests. ⏸
- **1.2** Keeping promises true: "Erase what the AI remembers" also erases
  the new memory and all versions; name spelling fixes reach it; the export
  includes a readable `memory.md`; memories with source `answer` migrate
  in. ⏸
- **End:** merge to `main` (nothing visible changes yet).

## Section 2: the dream pass

Data starts flowing to the AI on its own here, so the privacy text ships in
the same merge. This is the longest section, so it has six pause points.
Every one is safe to stop at overnight: the work is pushed to the
`memory-architecture` branch with tests passing, and `main` is untouched
until 2.6.

| Step | Work | Ends at pause | Next sitting starts with |
|---|---|---|---|
| 2.1 | Dream pass prompt and structured reply schema, from Hermes's design | ⏸ P1: request builds, schema tests pass | 2.2 |
| 2.2 | Reply parser: points added, revised, retired; rejects anything outside the rules (raw free writes, support readings, Quiet names surfacing); tests with a fake AI | ⏸ P2: parser tests pass | 2.3 |
| 2.3 | Compact rendering of the memory for prompts, with its size limit; tests | ⏸ P3: rendering tests pass | 2.4 |
| 2.4 | AI server: `dream` task and its credit cost; server tests (Deno) | ⏸ P4: server tests pass | 2.5 |
| 2.5 | Coordinator: when to dream (every N events, on app open when due), one at a time, failure and retry, saving a new version; tests | ⏸ P5: whole app test suite passes | 2.6 |
| 2.6 | Privacy policy, Play data-safety answers, SUPPORT_AND_SAFETY.md; Hermes reviews the prompt wording; merge to `main` | ⏸ P6: merged, APK builds | Section 3 |

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
