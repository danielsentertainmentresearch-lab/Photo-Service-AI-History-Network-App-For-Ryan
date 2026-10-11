# Memory architecture

_Final draft, by Hermes, 11 October 2026 (Section 0.3). Claude's check and
build notes follow her design in section 8. Waiting on Dan's approval;
nothing is built until then._

## 1. Schema (v8)
The memory system uses a row-based relational store. 

| Record Type | Fields | Source |
| :--- | :--- | :--- |
| **LearnedPoint** | `id`, `kind`, `content`, `sentiment` (polarity, intensity), `source`, `event_ids`, `version`, `parent_id`, `status` (active/archived/retired) | AI (Dream Pass) |
| **DreamState** | `id`, `foundation_statements` (list), `themes` (list), `version`, `event_ids`, `created_at` | AI (Dream Pass) |

*   **AI-Written:** `content`, `sentiment`, `foundation_statements`, `themes`.
*   **App-Filled:** `id`, `event_ids` (evidence mapping), `version` (increments), `parent_id` (links to previous version), `status`, `created_at`.

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
*   **Version Control:** Every revision creates a new row with an incremented `version` and a `parent_id` pointing to the previous state. Old rows are preserved unless `Erase` is invoked.
*   **Row-Based Archival:** Instead of blobs, points are marked `archived`. This enables global operations (like `Erase` or spell-fixes) to run as standard database updates.
*   **Pre-fetching:** To save credits, the app queries relevant historical points based on `event_ids` *before* the prompt is generated. Only the Dream Pass has the authority to request a "revival" of an archived point.
*   **Sentiment Definition:** `polarity` (negative, mixed, neutral, positive) + `intensity` (low, medium, high). Includes the `source` and `event_ids` that constitute the evidence.
*   **Privacy & Support:** Labels for "distress" or "crisis" trigger app-level support lines. These labels feed memory based on their classification. We do not filter events—we keep grief and loss to respect the Honored/continuity rule.
*   **Erase:** A destructive button that removes all `LearnedPoint`, `DreamState`, and version history records globally. It operates on the database level, ensuring absolute erasure.

## 5. Triggers & Migration
*   **Triggers:** Runs every 5 **newly described** events or when an account reaches a milestone (e.g., account setup).
*   **Migration:** Existing `memories` table records are assigned source `user` or `ai` and assigned to `v8` rows. `event_ids` are mapped from the event log.

## 6. Quiet and Honored Names
*   **Quiet:** Names are stored in memory but are never injected into the "Active" prompt. They remain in the DB but are skipped by the `EventDescriber` and `LearningPage`.
*   **Honored:** Marked with an `[Honored]` tag in the active prompt. The AI is instructed to write with continuity and care, referencing past events mapped in `event_ids`.

## 7. Open Questions for Dan
1. **Who pays for the dream pass?** Do we deduct from the user's daily 20-credit allowance, or is this a server-side "free" operation that you absorb?
2. **Rows vs. Blobs:** Claude suggested row-based archival for better database utility (spelling fixes/erase). Does this approach satisfy your compression requirements?
3. **Sentiment Source:** Is `intensity` (low/med/high) sufficient, or should we include a specific `evidence_snippet` field from the event?

## 8. Claude's check and build notes (Section 0.2, second pass)

Hermes's revision answers all 14 points from the first review. Four
needed tightening: support readings, evidence, the reach of Quiet, and
migration. The notes below make them exact, so the build follows the
fixed rules. Where they differ from sections 1 to 7, these notes govern.

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

### Answers to the open questions (section 7)

1. **Who pays:** the person's daily 20 credits, with the hold until reset
   (Dan, 11 October 2026).
2. **Rows vs. blobs:** rows. There was no separate compression
   requirement; rows make erase, spelling fixes and the export simple.
3. **Evidence snippet:** no. `event_ids` are the evidence. A snippet could
   pull free-write text into memory (rule 6) and would cost prompt space.
   Recommended; for Dan to confirm.
