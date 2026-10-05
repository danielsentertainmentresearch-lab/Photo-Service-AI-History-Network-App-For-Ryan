# The EventLens AI server

Owner decision, 5 Oct 2026 (post-review fix 1): the AI runs through the
owner's own server, so nobody using the app needs an Anthropic API key or an
Anthropic account. The server holds the owner's key, checks each request
comes from a signed-in account, and applies a daily allowance that reward
videos can top up.

## How it works

```
Phone (EventLens)  --sign-in token + request-->  AI server (Supabase)  -->  Anthropic
                   <--description + allowance--                        <--
```

- **Stateless for content.** The server passes requests through and keeps
  nothing people wrote, photographed or saved as memories. It stores only
  per-account usage counts (`ai_usage`) and reward-video receipts
  (`ai_ad_rewards`). The privacy promise stays as it is: photos, notes and
  memories live only on the phone.
- **The server decides the model and caps the cost.** Whatever the phone
  asks for, the server sets the model, caps effort (`high` by default) and
  output length, and turns on refusal fallbacks. The Settings model and
  effort choices are hidden when the server is in use.
- **Daily allowance, in credits.** Each account gets 20 credits a day
  (UTC). Requests cost what they spend:

  | Task | Credits |
  |---|---|
  | Describe an event (photos) | 4 |
  | Build or extend the timeline graph | 3 |
  | Label a free write | 1 |
  | Data platforms advice | 1 |

  A failed AI request gives its credits back. When the allowance runs out
  the app shows a clear message and the event waits as pending; nothing is
  lost, and Retry works the next day or after a top-up.
- **Reward videos top up AI work, never access to data.** One confirmed
  video adds 4 credits. Confirmation comes from AdMob's server-to-server
  callback, signed by Google, so a phone can't fake it. Each AdMob
  transaction counts once. Viewing, exporting and the Your data area stay
  free with no ads.
- **Sign-in.** The app signs in with Firebase today, so the server checks
  Firebase ID tokens. Moving sign-in to Supabase is scheduled separately
  (below).

Code: `supabase/functions/ai/` (server), `supabase/migrations/` (allowance
tables), `lib/ai/ai_server.dart` (the app's client), `lib/ai/ai_client.dart`
(the interface every AI backend implements).

## Setting it up (owner, once)

1. Create a free account at supabase.com and a new project. Note the
   project reference (the `xxxx` in `https://xxxx.supabase.co`).
2. Install the Supabase CLI (supabase.com/docs/guides/cli), then from the
   repository folder:
   ```
   supabase login
   supabase link --project-ref xxxx
   supabase db push
   ```
   `db push` creates the allowance tables.
3. Set the server's secrets. Only you see these; they never go into the app
   or the repository:
   ```
   supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
   supabase secrets set FIREBASE_PROJECT_ID=<the Firebase project id>
   ```
4. Deploy the function:
   ```
   supabase functions deploy ai --no-verify-jwt
   ```
   Its address is `https://xxxx.supabase.co/functions/v1/ai`.
5. **Tell Claude before this step**, so the privacy policy and Play
   data-safety answers that name the server ship in the same build
   (scheduled step 4). Then point the app at it: in GitHub, Settings →
   Secrets and variables → Actions, add `AI_SERVER_URL` with that address.
   The next build on `main` uses the server, and the API key box disappears
   from Settings. The server needs real accounts: the Firebase secrets in
   RELEASE.md must be set too, since the test-build "Continue as reviewer"
   sign-in has no token the server can check.

Until step 5, builds keep asking for the person's own key, exactly as
before.

### Optional settings

Set with `supabase secrets set NAME=value`:

| Name | Default | What it does |
|---|---|---|
| `AI_DAILY_CREDITS` | 20 | Free credits per account per day |
| `AI_MODEL` | `claude-opus-5-5` | Model for every task |
| `AI_MODEL_DESCRIBE`, `AI_MODEL_GRAPH`, `AI_MODEL_LABEL`, `AI_MODEL_ADVISE` | `AI_MODEL` | A different model for one task (for example `claude-sonnet-5-5` for labels) |
| `AI_MAX_EFFORT` | `high` | Highest effort any request may use |
| `AI_AD_CREDITS` | 4 | Credits one reward video adds |
| `ADS_ENABLED` | `false` | Accept reward-video top-ups (turn on once AdMob is connected) |

### Reward-video top-ups (when AdMob is connected)

1. In AdMob, open the rewarded ad unit → Server-side verification → set the
   callback URL to `https://xxxx.supabase.co/functions/v1/ai/admob-reward`.
2. `supabase secrets set ADS_ENABLED=true`.
3. The app sets the signed-in account id as the ad's user id
   (`ServerSideVerificationOptions`). That app change is scheduled below.

## Before beta testers and launch

The steps that wait until testers or deployment (spending limit, time limit
check, switching on, allowance size, ad callback, usage review) are in
`docs/LAUNCH_CHECKLIST.md`, section "AI server". Nothing is spent until
then.

## Scheduled (owner-approved order, 5 Oct 2026)

| # | Step | Who | Status |
|---|---|---|---|
| 1 | `AIClient` interface: every AI feature behind one contract | Claude | Done (`6057de5`) |
| 2 | AI server, allowance tables, app client, Settings in server mode, dashboard counts | Claude | Done (this change) |
| 3 | Set up Supabase, deploy, add `AI_SERVER_URL` (steps above) | Owner | Waits until beta testers (launch checklist) |
| 4 | Update the privacy policy and Play data-safety answers to name the owner's server as the route to Anthropic (it passes requests through and keeps only usage counts). The Settings privacy text already says this when the server is in use | Claude | Together with step 3, before `AI_SERVER_URL` is set |
| 5 | Reward-video top-ups in the app: set the ad's user id, a "watch a video for more AI" action where the allowance runs out | Claude (wiring), Hermes (how it looks) | After AdMob is connected |
| 6 | Allowance and "AI is working" indicators | Hermes (design), Claude (data: every server reply reports what's left) | With step 5 |
| 7 | Move sign-in from Firebase to Supabase (owner's non-Google preference); the server then checks Supabase tokens | Claude | Separate step, after the server is live |
| 8 | The app's own memory file and dream state: kept on the phone as promised; the app learns from how each person corrects and confirms it, and a periodic "dream" pass consolidates what it learned. Learning is measured with signals the dashboard already counts (for example, labels marked not right). When it is built, move every memory saved from an answer to the AI's who/where questions (source `answer`, see `lib/models/memory_item.dart`) into the app's memory file as a learned identifier, with its event as evidence | Hermes (proposal), Claude (build) | Owner is asking Hermes; design review with Claude before building |
| 9 | Optional: a cheaper or self-hosted model for light tasks (labels, advice), chosen on the server per task | Owner decision | Later; possible now through `AI_MODEL_LABEL` / `AI_MODEL_ADVISE` |

Not planned: storing memories or vectors on the server. That would change
the privacy promise and is the owner's decision if it ever comes up.
