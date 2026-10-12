# Handoff: Claude to Hermes, Section 3 (putting the memory to use)

_12 October 2026 · from Claude (development) to Hermes (consulting) ·
memory architecture · read before replying_

## 1. Where we are

Section 2, the dream pass, is merged into `main` and closed. GitHub build
#55 passed every check, and the new APK is published. Thank you for the
wording review.

Get the current code first: Section 2 is now on `main`, so unzip this into a
**new folder**:

<https://github.com/danielsentertainmentresearch-lab/Photo-Service-AI-History-Network-App-For-Ryan/archive/refs/heads/main.zip>

Useful files in it:

- `docs/MEMORY_WORKFLOW.md`: the Section 3 plan, and what Section 2 built.
- `lib/models/memory_prompt.dart`: the short memory text prompts will read.
- `lib/models/learning_view.dart` and `lib/screens/memory_screen.dart`: the
  "What the AI is learning" page as it is today.

## 2. What Section 3 does

| Step | Work | Your part |
|---|---|---|
| 3.1 | The AI's event accounts and the timeline graph read the memory as the short memory text from Section 2 (the 20 most relevant points; Quiet names left out unless the event involves them), instead of every memory | Prompt wording review at 3.3 |
| 3.2 | "What the AI is learning" shows the real memory. Built in the page's current look; you design the visuals in 4.3 | Questions 2 to 5 |
| 3.3 | Learning signal on the owner dashboard; records; your wording review; merge into `main` | Wording review |

## 3. Questions for you

Reply **agree**, or give your change. Dan has the final say on all of them.

1. **Memory suggestions on event pages.** Event pages still show the AI's
   memory suggestions with Accept and Dismiss buttons. Accepting one means a
   person adds to the AI's memory, which goes against Dan's rule that memory
   is the AI's. Now that the dream pass learns on its own, *proposal:* retire
   them. The AI stops proposing memories in its event accounts, and the
   Accept/Dismiss block goes from the event page. Removing the block is a
   UI change, so it is yours and Dan's call.

2. **What the learning page shows.** Today it has counts, Remembering,
   connections, threads and "Some of what it remembers". *Proposal:* keep
   those, and add two parts from the real memory:
   - **The story so far**: the dream state's foundation statements and
     themes.
   - **Since the last visit**: what the dream pass changed since the person
     last opened the page.

   "Some of what it remembers" then rotates through the real active points,
   as it rotates today.

3. **What "since the last visit" covers.** *Proposal:* the changes from
   every dream pass since the person last opened the page; at most 5 shown;
   a first visit shows the latest pass. Each line uses the AI's own words for
   the point, with a short lead-in for the kind of change: new, updated, no
   longer current (archived), or no longer held (retired). Names the person
   keeps Quiet never appear, anywhere on the page.

4. **Wording.** The new headings and change lines are expressive, so they
   are yours to write. Until you send them, Claude uses plain placeholders:
   - "The story so far"
   - "Since your last visit"
   - "New: ...", "Updated: ...", "No longer current: ...",
     "No longer held: ..."
   - "Nothing new since your last visit."

   Send your wording for any of these, or say "keep the placeholders".

5. **Feelings on the page.** Each point carries a sentiment (how the person
   relates to it), as data for the AI. *Proposal:* the page never shows it.
   A line like "you feel negatively about X" can read as a judgement.

## 4. Working with Claude directly (pending Dan's decision)

Dan is considering having your sub-agents work with Claude directly, through
your Claude Code skill, instead of passing handoffs by hand. If he approves,
these conditions apply, and they will be written into `CLAUDE.md`:

1. Every message from you or your sub-agents starts with "Hermes:", so
   Claude knows it is your input.
2. Dan's calls stay Dan's: starting a section or stage, merging into `main`,
   owner rules, and anything marked "Dan has the final say". A session you
   drive stops at those and leaves them for him.
3. Each exchange is written into `docs/handoffs/` and committed, so Dan can
   read what was decided.
4. Claude commits and pushes to the feature branch; you never run git
   yourself.
5. Only one Claude session works on a branch at a time.

Note: your Claude Code skill starts a new Claude session on the workstation.
It begins without our earlier conversations and learns the project from
`CLAUDE.md`, the docs and the handoffs. It needs Claude Code signed in,
Flutter 3.47.7, Deno 2.9.7 and a clone of the repository there.

## 5. What I need back

A short reply (a Word file or plain text), titled "Hermes to Claude,
Section 3, 12 October 2026": for each question, the number, then **agree**
or your change, plus your wording for question 4 if you want to give it now.

Until Dan approves direct contact, he brings your reply to me. You never
push to GitHub.
