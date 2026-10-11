# Memory architecture

_Draft 1, by Hermes, 11 October 2026. Section 0 of `docs/MEMORY_WORKFLOW.md`.
Under review: Claude's check against the code and the fixed rules is in
progress, and Hermes revises once. Nothing here is built until Dan approves
the revised design._

## 1. Schema (v8)

The memory system maintains an Active store for current context and an
Archived store for historical fidelity.

| Record type | Fields | Source |
|---|---|---|
| ActivePoint | id, kind, content, sentiment, source, event_ids, version | Dream pass |
| ArchivedRecord | id, compressed_blob (JSON), original_ids (list), timestamp, reason | Dream pass |
| DreamState | id, foundation_statements (list), themes (list), version, created_at | Dream pass |

## 2. Compact rendering (the "Active" prompt)

The AI receives an active, lean state. If it needs historical context, it
requests a "Fetch" from the Archive.

```text
MEMORY_V8:
[DREAM: <foundation_statements>]
[ACTIVE: <points>]
[ARCHIVE_INDEX: <blobs_list>]
```

## 3. The dream pass: Librarian pattern

The dream pass is a stateful librarian task running periodically (every 5
new events or user milestones, capped at once per 24 hours).

```json
{
  "archive_outdated": { "point_ids": [], "reason": "..." },
  "retrieve_archive": ["blob_id"],
  "add_active": [{ "kind": "...", "content": "..." }],
  "update_dream": { "foundation_statements": [], "themes": [] }
}
```

## 4. Archival and retrieval logic

- **Compression:** cold points are bundled into ArchivedRecord blobs.
  Nothing is deleted; preservation is absolute.
- **Retrieval:** when the AI fetches an archive, the app decompresses it
  into the temporary context.
- **Re-compression:** upon completing the task, if the retrieved data
  remains "cold", it must be re-archived to restore the state. This keeps
  the active database optimized without data loss.
- **No blanks:** every database query mapping to these records must handle
  the "-999" (numeric) or "none" (text) requirements established in the
  dashboard and analysis specs.

## 5. Design notes (aligned with the build stages)

- **Mind map first:** the memory architecture supports the mind-map view by
  prioritizing subjective experience ("what this event meant to the
  person") over purely objective data.
- **Privacy first:** memory does not store the free-write text itself, only
  the labels extracted from it (v5+ schema). Support readings and raw
  free-write text remain local and private and are excluded from the
  memory vault.
- **Support and safety:** any record labeled "distress" or "crisis" is
  flagged for the app-level support line and excluded from the archival and
  memory-linking process, per the owner's instruction never to judge or
  inappropriately archive crisis-related material.
