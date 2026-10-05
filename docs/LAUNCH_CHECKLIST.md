# Launch checklist

Living list of outside accounts and platforms EventLens needs. The
illustrated version (same content, updated at the end of every stage) is
the "EventLens Launch Checklist" page shared with the owner.

Preference order for every choice: open source first, then non-Google
services. Rewarded ads are the exception: Google AdMob stays an option.

**When the checklist work starts** (owner, 4 Oct 2026): after build stage 3
closes (the stage after stage 2; planned as the parts and features that
run on the AI backbone). Starting slightly earlier is possible,
but the target is the end of stage 3. Until then the reminder below
continues at the end of every stage.

## Standing reminder (repeat at the end of every build stage until done)

- [ ] **Accounts backend**: not active. Test builds use "Continue as
      reviewer". Recommended at the end of build stage 1: **Supabase** (open source,
      managed now, can self-host later; it also verifies Web3 sign-in for
      Ethereum and Solana wallets natively). Alternatives: PocketBase (cheapest,
      single binary, pre-1.0), Appwrite, Firebase (Google; already wired).
- [ ] **Rewarded ads**: not active. Test builds show Google test ads.
      Recommended at the end of build stage 1: **AdMob** (already integrated). Alternatives:
      AppLovin MAX, Unity LevelPlay, Liftoff, Mintegral, Pangle, Meta
      Audience Network; open source Prebid Mobile only at large scale.

## AI server: waits until beta testers or deployment

Owner rule (5 Oct 2026): nothing is spent until testers use the server, so
these steps wait until then. Setup commands: `docs/AI_SERVER.md`.

**Before beta testers**

- [ ] **Supabase project**: create it, run `supabase db push`, set
      `ANTHROPIC_API_KEY` and `FIREBASE_PROJECT_ID`, deploy the `ai`
      function (`docs/AI_SERVER.md`, steps 1 to 4).
- [ ] **Privacy before switching on**: tell Claude first, so the privacy
      policy, Play data-safety answers and store listing name the AI server
      in the same build.
- [ ] **Switch on**: add the `AI_SERVER_URL` GitHub secret (the Firebase
      secrets in RELEASE.md must be set too; reviewer sign-in can't use the
      server).
- [ ] **Spending limit**: set a monthly limit on the Anthropic key in the
      Anthropic Console.
- [ ] **Time limit check**: on the owner's phone, describe a multi-photo
      event at high effort and confirm it finishes within Supabase's time
      limit (about 150 s on the free plan). If not: a paid Supabase plan or
      `AI_MAX_EFFORT=medium`.
- [ ] **Allowance size**: check the 20 daily credits against real costs
      from the first testers; change with `AI_DAILY_CREDITS`.

**Before public launch**

- [ ] **Reward-video top-ups**: once AdMob is connected, set its
      server-side verification callback to `.../functions/v1/ai/admob-reward`,
      set `ADS_ENABLED=true`, and ship the app's top-up action.
- [ ] **Usage review**: watch the dashboard's allowance counts; if usage
      looks off, charge credits by request size (the server currently trusts
      the task name the app sends; requests over 20 MB are refused).
- [ ] **Sign-in on Supabase**: move sign-in off Firebase (owner's
      non-Google preference); the server then checks Supabase tokens.
- [ ] **Hosting plan**: choose the Supabase plan (or self-hosting) from
      real usage.

## Everything else

| Item | Status | Recommended |
|---|---|---|
| Web3 sign-in | Built in, not connected | Wallet connection: **Reown AppKit** (WalletConnect; free project id at cloud.reown.com, open-source SDK). Verification: the accounts backend (Supabase Web3 provider). Farcaster: Sign In With Farcaster (open-source AuthKit), verified by a small backend function |
| Passkeys | Later | Hanko (open source) alongside the backend |
| SMS for phone sign-up | Waiting on owner | Twilio Messaging via the backend's SMS hook (not Twilio Verify) |
| Google sign-in | Waiting on owner | Google Cloud OAuth client, connected to the chosen backend |
| Ad consent (EEA/UK) | Waiting on owner | The ad network's consent tool |
| app-ads.txt | Waiting on owner | GitHub Pages site |
| App store | Waiting on owner | Google Play; later Samsung Galaxy Store, Huawei AppGallery |
| Upload signing key + GitHub secrets | Waiting on owner | See RELEASE.md; keep in Bitwarden |
| Privacy policy URL | Waiting on owner | GitHub Pages |
| Support email | Waiting on owner | Proton Mail on a custom domain |
| AI access | Built; deploy waits until beta testers (see "AI server" above) | The owner's AI server on **Supabase** (Edge Function) holds the Anthropic key; daily allowance with reward-video top-ups. Until `AI_SERVER_URL` is set, builds still use each user's own key. Set a monthly spend limit on the key in the Anthropic Console |
| Crash reporting | Owner to choose (not picked yet) | Options: GlitchTip (open source, self-host or hosted), Sentry (open-source SDK; self-host or sentry.io), Bugsink (open source, self-host). Crash data goes to the owner dashboard |
| Payments (paywall stage) | Later | Google Play Billing (required); RevenueCat optional |
| Place names (Nominatim) | Active (free, light use) | OpenStreetMap's public server allows max 1 request/s and no heavy use. Before launch at scale: self-host Nominatim or Photon (open source), or a paid OSM-based provider; base URL is configurable in `PlacesService` |
| Weather (Open-Meteo) | Active (free, non-commercial) | Free tier is non-commercial only. A monetized release needs the Open-Meteo API subscription, or self-host Open-Meteo (open source, Docker) |
| Weather daily pass | Built (3 rewarded videos, refresh 12:00 noon) | Uses the same rewarded-ad platform as rings |
| Owner metrics dashboard | Demo built (`owner-dashboard/`, demo data); connecting real metrics is the final stage | Self-hosted on the owner's computer (localhost). Metrics source options, open source first: PostHog (self-host), Umami, Plausible, Matomo; Aptabase (open source, privacy-first, has a Flutter SDK). Not chosen yet. Needs a consent line in the privacy policy before any usage metrics are sent |
| Export plan | Built: free CSV; full export at 100 events | The paywall stage adds the higher ("+1") tier requirement for export once Play Billing is connected |
| Backup/sync paywall | Ideas listed, not built | Payments platform above; storage options: Supabase Storage, Backblaze B2, Cloudflare R2, or self-hosted MinIO/Garage |
| Owner dashboard notebook | Built (JupyterLite, open source) | Loads Python (Pyodide) from the jsDelivr CDN on first use; for fully offline use, self-host Pyodide in the notebook folder |
| Brand palette | After this build phase | Swap `lib/models/ring_palette.dart` |

## Reminder log

- **Stage 7 (3 Oct 2026)**: accounts and ads not active. Recommended:
  Supabase for accounts, AdMob for ads.
- **Stage 8 (3 Oct 2026)**: accounts and ads still not active. Recommended:
  Supabase for accounts, AdMob for ads. Added: crash reporting (undecided),
  owner dashboard, Nominatim and Open-Meteo usage terms.
- **End of build stage 1 (3 Oct 2026)**: accounts and ads still not active.
  Recommended: Supabase for accounts (now also for Web3 sign-in), AdMob for
  ads. Added: Reown (WalletConnect) project id for Web3 sign-in; owner
  dashboard demo built.
- **Build stage 1 ended (4 Oct 2026)**: accounts and ads still not active.
  Recommended: Supabase for accounts (and Web3 sign-in), AdMob for ads.
  Added: the owner dashboard's built-in notebook (JupyterLite).
- **Build stage 2 started (4 Oct 2026)**: accounts and ads still not
  active. Recommended: Supabase for accounts (and Web3 sign-in), AdMob for
  ads.
- **Post-review fix 1 (5 Oct 2026)**: accounts and ads still not active.
  Recommended: Supabase for accounts (and Web3 sign-in), AdMob for ads.
  Added: the AI server (Supabase) and its "waits until beta testers or
  deployment" list.
