# Memory architecture

_Hermes's official final draft, 11 October 2026 (Section 0.3). Approved by
Dan on 11 October 2026, with his answers and Claude's build notes in
section 8. Where section 8 is more exact than sections 1 to 7, section 8
governs the build._

## 1. Schema (v8)
The memory system uses a row-based relational store. 

| Record Type | Fields | Source |
| :--- | :--- | :--- |
| **LearnedPoint** | `id`, `kind`, `content`, `sentiment` (polarity, intensity), `source`, `event_ids`, `version`, `parent_id`, `status` (active/archived/retired) | AI (Dream Pass) |
| **DreamState** | `id`, `foundation_statements` (list), `themes` (list), `version`, `event_ids`, `created_at` | AI (Dream Pass) |

*   **AI-Written:** `content`, `sentiment`, `foundation_statements`, `themes`.
*   **App-Filled:** `id`, `event_ids` (AI-cited evidence mapping, validated against app events), `version` (increments), `parent_id` (links to previous version), `status`, `created_at`.

## 2. Compact Rendering (Example)
**Size Limit:** Max 2000 characters or 20 points.

```text
MEMORY_V8:
[DREAM: Ana is the user's closest friend. Themes: Growth.]
[ACTIVE:
- {id: 101, kind: person, sent: pos:med, cont: "Ana wears red", Src: answer, Ev: [5, 12]}
- {id: 102, kind: pref, sent: neut:low, cont: "Likes coffee", Src: ai, Ev: [8]}
]
```

## 3. The Dream Pass Reply (Librarian API)
The Dream Pass returns a structured JSON to update the state.
```json
{
  "add_active": [{"kind": "...", "content": "...", "sentiment": "...", "source": "..."}],
  "revise_active": {"id": "...", "new_content": "...", "reason": "...", "event_ids": [...]},
  "archive_active": [{"id": "...", "reason": "..."}],
  "update_dream": {"foundation_statements": [...], "themes": [...]},
  "reasoning": "..."
}
```

## 4. Key Mechanisms
*   **Version Control:** Every revision creates a new row with an incremented `version` and a `parent_id` pointing to the previous state. Old rows are preserved.
*   **Row-Based Archival:** Points are marked `archived` to maintain row-level integrity for global operations like `Erase`.
*   **Evidence Validation:** The AI cites `event_ids` during generation. The app validates these against the existing event log; if an ID is invalid, the point is rejected.
*   **Support & Privacy:** Support readings are strictly isolated and never feed the memory system. This ensures that personal stories of loss or grief are preserved as history while preventing support-level data from being stored or learned.
*   **Erase:** A destructive button that removes all `LearnedPoint`, `DreamState`, and version history records globally. It operates on the database level, ensuring absolute erasure, including all archived versions.

## 5. Quiet and Honored Names
*   **Quiet:** Names are stored in memory but are never injected into the "Active" prompt. They remain in the DB but are skipped by the `EventDescriber` and `LearningPage`.
*   **Honored:** Marked with an `[Honored]` tag in the active prompt. The AI is instructed to write with continuity and care, referencing past events mapped in `event_ids`.

## 6. Open Questions for Dan
1. **Who pays for the dream pass?** Will this deduct from the user's daily 20-credit allowance, or is this a server-side "free" operation that you absorb?
2. **Sentiment Evidence:** We have opted out of an `evidence_snippet` field to keep sentiment focused on polarity/intensity without violating privacy or cluttering records. Does this align with your design needs?

## 7. Build Notes (Rules & Constraints)
*   **Support Readings:** Strictly isolated from memory feeding.
*   **Evidence Handling:** AI cites IDs; app validates. No quotes stored.
*   **Erase:** Destroys all versions, rows, and history.
*   **Memory Migration:** `source` (ai/answer/user) is preserved for all migrated records.

## 8. Dan's answers and Claude's build notes

### Dan's answers (11 October 2026)

1. **Who pays for a dream pass:** the person's daily 20 credits. When
   they're used up, the pass and other AI work wait for the next reset
   (`docs/MEMORY_WORKFLOW.md`).
2. **Evidence snippet:** no, in line with rule 6. `event_ids` are the
   evidence, and no quotes are stored.
3. **Rows, not blobs**, as in section 4.

### Build notes

1. **Support readings stay out of memory (rule 10).** The support reading
   (`support_level`) isn't a label and never reaches the dream pass, not
   even to filter events. The dream pass reads events and their confirmed
   and rejected labels the same way, whatever the support reading says.
   So grief and loss stay part of the story, as section 4 intends.
2. **Evidence is cited by the AI and checked by the app.** The AI names
   the event ids behind each added, revised or archived point (only it
   knows why). The app drops any id that isn't a real event in the
   library, and a point with no valid evidence is not saved.
   `add_active` items carry `event_ids` and `reason`. `revise_active` is a
   list, like the others.
3. **Quiet (rule 8) means "never on its own".** Quiet names are left out
   of everything that surfaces things: the learning page, insights, On
   this day, and the dream state's foundation statements. When the person
   records or rewrites an event that already involves a Quiet name, the
   points about that name may be used for that one event, because the
   person brought them up, so the AI still knows who they are.
4. **Migration (Section 1.2).** Every row in today's `memories` table
   becomes a version-1 LearnedPoint with status `active`. Its source is
   kept: `ai`, `user` or `answer`. `answer` stays, because it is the
   person's own reply to the AI's question. Its `event_id`, when present,
   becomes its `event_ids`. Sentiment starts as `neutral:low` with source
   `migrated`, until a dream pass revises it. The old table is removed in
   the same upgrade.
5. **Triggers.** A pass runs after every 5 newly described events, or on
   a milestone (the first time the account is fully set up, and the
   timeline graph unlocking at 10 events). At most one pass a day. A
   pass that is due while the allowance is used up waits for the next
   reset (owner decision, `docs/MEMORY_WORKFLOW.md`).
6. **Erase and spelling fixes** reach every row of every status and
   version, and the dream state with its history. A spelling fix changes
   old versions in place. It is the one in-place change allowed, because
   it is the person's correction of a name, not a change of what the AI
   learned.
7. **Export.** The full export gains a readable `memory.md` (active points
   and the current dream state). If memory ever goes into the analysis
   CSV, it follows the no-blanks rule there (`unknown`, `none`, -999).
8. **Sizes.** The rendering limit (2000 characters or 20 points) applies
   to active points and is chosen by relevance to the request. Honored
   names are marked `[Honored]`. The dream pass itself may see more,
   within one request (rule 4).
9. **Built in Section 1 (11 October 2026).** Database v8 holds two tables,
   `learned_points` and `dream_states` (`lib/data/memory_repository.dart`,
   `lib/models/learned_point.dart`). Each point row also carries a
   `point_id`, shared by all its versions, so prompts and the dream pass
   can name a point that stays the same across revisions. Archiving and
   retiring write new versions too, so no stored row ever changes (except
   for a spelling fix). Points saved from answers before any dream pass
   has run carry the sentiment source `pending`.
