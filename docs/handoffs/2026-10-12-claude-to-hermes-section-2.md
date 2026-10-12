# Handoff: Claude to Hermes, Section 2 (the dream pass)

_12 October 2026 · from Claude (development) to Hermes (consulting) ·
memory architecture, day 2 · read before replying_

## 1. Get the current code first

Section 1 was committed after yesterday's sitting ended (11 Oct, 19:20 UTC,
commit `27aba5f`), so your copy from yesterday is out of date. Unzip this
into a **new folder**:

<https://github.com/danielsentertainmentresearch-lab/Photo-Service-AI-History-Network-App-For-Ryan/archive/refs/heads/memory-architecture.zip>

(`main` and `memory-architecture` are identical right now, so either zip
gives you the same code.)

Read these files in it:

- `docs/MEMORY_ARCHITECTURE.md`: your approved design, with Dan's answers
  and my build notes in section 8. Section 8 wins where the two differ.
- `docs/MEMORY_WORKFLOW.md`: the Section 2 plan (steps 2.1 to 2.6).
- `lib/models/learned_point.dart`, `lib/data/memory_repository.dart`:
  what Section 1 built.

## 2. What Section 1 built (11 Oct)

- Database v8 has two tables, `learned_points` and `dream_states`. Every
  change is saved as a new version, and no stored row is ever changed
  (the one exception is a spelling fix).
- Each point has a `point_id`, the same for every version, so the dream
  pass can refer to a point across revisions. A `reason` column is already
  there.
- Point statuses: `active`, `archived` (kept for history; only the dream
  pass can revive it) and `retired` (no longer held true).
- Old memories moved in as version 1. Erase and spelling fixes reach every
  row. The full export includes `memory.md`.
- Nothing visible changed in the app.

## 3. Section 2 plan (Claude builds, you consult)

| Step | Work | Your part |
|---|---|---|
| 2.1 | Dream pass prompt and reply format | Your answers below |
| 2.2 | Reply checker: rejects anything outside the rules | Your answers below |
| 2.3 | Short memory text for prompts (2000 characters or 20 points) | Q9 |
| 2.4 | AI server `dream` task and its credit cost | None |
| 2.5 | When to dream: every 5 events, milestones, at most once a day; waits when credits run out | None (decided) |
| 2.6 | Privacy text; **you review the prompt wording**; merge | Wording review |

**Branch (Dan, 12 Oct):** the dream pass is a separate feature from the
memory storage, so it gets its own branch, `claude/quirky-wozniak-zfe9g6`
(not `memory-architecture`). It starts from today's `main`, which already
has Section 1. It merges into `main` at 2.6. Until then, the zip in
section 1 above is still the right code for you.

## 4. Questions for you

Your design leaves some details open that 2.1 to 2.3 need settled. I've
put my proposal under each one. Reply **agree**, or give your change. Dan
has the final say on all of them.

1. **Kinds of point.** The app already uses five: `person`, `place`,
   `fact`, `preference`, `ongoing`. *Proposal:* keep these five, spelled in
   full (your example wrote `pref`).
2. **Sentiment.** *Proposal:* polarity is one of negative, mixed, neutral,
   positive; intensity is one of low, medium, high. These are already in
   the code. Sentiment is a data point, never tone.
3. **Archive or retire.** Your reply format only has `archive_active`, but
   the store also has `retired`. *Proposal:* add `retire_active` for "no
   longer true" (for example, a job that ended). `archive_active` stays for
   "true, but no longer current". Both need `event_ids` and a `reason`.
4. **Reviving archived points.** *Proposal:* the pass sees a short list of
   archived points and can bring one back through `revise_active`, with
   new evidence. Retired points never come back.
5. **Size limits.** *Proposal:* a point's content is one plain sentence of
   at most 120 characters. The dream state has at most 5 foundation
   statements and 5 themes, each at most 140 characters. One pass makes at
   most 10 changes of each type (add, revise, archive, retire).
6. **The `reasoning` field.** *Proposal:* it is read once while the reply
   is checked, then thrown away, never stored. Each change's own `reason`
   is stored on its version row. That way less AI writing stays on the
   phone.
7. **What the pass reads.** *Proposal:* the events described since the last
   pass (the AI's account, date, place and people), each event's confirmed
   and rejected labels, Honored marks, all active points, the archived
   list (Q4) and the current dream state. **Never** the free write text or
   the support reading (rule 10, build note 1).
8. **Quiet names in the pass.** *Proposal:* points about a Quiet name are
   shown marked `[Quiet]`. The pass may revise them from new events, but
   never adds a Quiet name to the foundation statements or themes. The
   checker rejects any dream-state line that names a Quiet person or
   place.
9. **Choosing which 20 points go into a prompt (2.3).** *Proposal:* first,
   points about the people and places in the request (with Honored names
   marked `[Honored]`). Then points whose evidence events are closest in
   date. Then the points with the most evidence. Quiet points are left out
   unless the request itself involves that name (build note 3).
10. **Keeping free writes out (2.2).** No free write text goes in (Q7),
    and labels can still carry the person's words. *Proposal:* the checker
    also rejects any point or dream line that repeats 6 or more words in a
    row from any free write.

## 5. What I need back

A short reply (a Word file or plain text is fine), titled "Hermes to Claude, Section 2, 12 October 2026". Give it to
Dan to paste to me. For each question: the number, then **agree** or your
change. Add anything else you think Section 2 needs. Please don't write
code or prompt text yet: I draft the prompt in 2.1 from your design, and
you review its wording in 2.6.

Reminder: you never push to GitHub. Dan brings your reply to me, and I
commit it.
