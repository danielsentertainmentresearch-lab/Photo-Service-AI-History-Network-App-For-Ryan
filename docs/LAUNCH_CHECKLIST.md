# Launch checklist

Living list of outside accounts and platforms EventLens needs. The
illustrated version (same content, updated at the end of every stage) is
the "EventLens Launch Checklist" page shared with the owner.

Preference order for every choice: open source first, then non-Google
services. Rewarded ads are the exception: Google AdMob stays an option.

## Standing reminder (repeat at the end of every build stage until done)

- [ ] **Accounts backend**: not active. Test builds use "Continue as
      reviewer". Recommended at stage 8: **Supabase** (open source, managed
      now, can self-host later). Alternatives: PocketBase (cheapest,
      single binary, pre-1.0), Appwrite, Firebase (Google; already wired).
- [ ] **Rewarded ads**: not active. Test builds show Google test ads.
      Recommended at stage 8: **AdMob** (already integrated). Alternatives:
      AppLovin MAX, Unity LevelPlay, Liftoff, Mintegral, Pangle, Meta
      Audience Network; open source Prebid Mobile only at large scale.

## Everything else

| Item | Status | Recommended |
|---|---|---|
| Passkeys | Later | Hanko (open source) alongside the backend |
| SMS for phone sign-up | Waiting on owner | Twilio Messaging via the backend's SMS hook (not Twilio Verify) |
| Google sign-in | Waiting on owner | Google Cloud OAuth client, connected to the chosen backend |
| Ad consent (EEA/UK) | Waiting on owner | The ad network's consent tool |
| app-ads.txt | Waiting on owner | GitHub Pages site |
| App store | Waiting on owner | Google Play; later Samsung Galaxy Store, Huawei AppGallery |
| Upload signing key + GitHub secrets | Waiting on owner | See RELEASE.md; keep in Bitwarden |
| Privacy policy URL | Waiting on owner | GitHub Pages |
| Support email | Waiting on owner | Proton Mail on a custom domain |
| AI access | Active | Each user's own Anthropic API key |
| Crash reporting | Owner to choose (not picked yet) | Options: GlitchTip (open source, self-host or hosted), Sentry (open-source SDK; self-host or sentry.io), Bugsink (open source, self-host). Crash data goes to the owner dashboard |
| Payments (paywall stage) | Later | Google Play Billing (required); RevenueCat optional |
| Place names (Nominatim) | Active (free, light use) | OpenStreetMap's public server allows max 1 request/s and no heavy use. Before launch at scale: self-host Nominatim or Photon (open source), or a paid OSM-based provider; base URL is configurable in `PlacesService` |
| Weather (Open-Meteo) | Active (free, non-commercial) | Free tier is non-commercial only. A monetized release needs the Open-Meteo API subscription, or self-host Open-Meteo (open source, Docker) |
| Weather daily pass | Built (3 rewarded videos, refresh 12:00 noon) | Uses the same rewarded-ad platform as rings |
| Owner metrics dashboard | Final stage | Self-hosted on the owner's computer (localhost). Metrics source options, open source first: PostHog (self-host), Umami, Plausible, Matomo; Aptabase (open source, privacy-first, has a Flutter SDK). Not chosen yet. Needs a consent line in the privacy policy before any usage metrics are sent |
| Backup/sync paywall | Ideas listed, not built | Payments platform above; storage options: Supabase Storage, Backblaze B2, Cloudflare R2, or self-hosted MinIO/Garage |
| Brand palette | After this build phase | Swap `lib/models/ring_palette.dart` |

## Reminder log

- **Stage 7 (3 Oct 2026)**: accounts and ads not active. Recommended:
  Supabase for accounts, AdMob for ads.
- **Stage 8 (3 Oct 2026)**: accounts and ads still not active. Recommended:
  Supabase for accounts, AdMob for ads. Added: crash reporting (undecided),
  owner dashboard, Nominatim and Open-Meteo usage terms.
