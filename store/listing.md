# Google Play listing: EventLens

## App name (max 30)
EventLens: AI Life Journal

## Short description (max 80)
Snap an event, jot a note. AI writes the full story, remembering what came before.

## Full description (max 4000)
EventLens turns a few photos and a quick note into a vivid, detailed record of
the moments that matter, written for you by AI.

HOW IT WORKS
• Add photos from your camera or gallery, plus a few words about what's
  happening: who's there, what led up to it, how it feels.
• The AI studies every photo and your notes, then writes a rich first-person
  account: the setting, the light, the people, the little details you'd
  otherwise forget.
• It remembers. Save facts about the people, places and ongoing situations in
  your life, and every new account connects to them and to your recent
  events.
• After each event, the AI suggests new things worth remembering. You choose
  what to keep.

YOUR LIBRARY STAYS YOURS
• Photos, notes and memories are stored only on your phone, never on a
  developer server.
• Only the event you choose to describe is sent to the AI, using your own
  Anthropic API key.
• No analytics or tracking. Ads appear only if you choose to watch a short
  video to unlock extra ring colours or the day's weather lookups.
• Sharing a phone? Every account has its own private library.
• Hidden from the recent-apps screen by default.

FEATURES
• Your timeline becomes a connected graph of chapters, people, places and
  themes, and keeps growing as you add events
• Gather chapters into your own titled Books; mark events with coloured rings
• Dates and places filled in from your photos automatically
• "On this day": events from this date in earlier years
• Optional weather for any event, kept separate from the AI's account
• Your data: meters for your whole library, and a free spreadsheet export
• At 100 events, a full export: photos, an Obsidian-ready vault and an
  analysis file for Python and Jupyter notebooks
• Sign in with email, phone, Google or a Web3 identity (crypto wallet or
  Farcaster)
• Timeline of events grouped by month
• Full-text search across titles, notes, accounts, people, places and tags
• Edit, copy or rewrite any account
• Choose Claude Opus 5.5 for maximum detail or Sonnet 5.5 for speed
• Light and dark themes

REQUIREMENTS
EventLens uses Anthropic's Claude API. You need your own API key from
console.anthropic.com. Usage is billed by Anthropic to your account.

## Category
Lifestyle (alternative: Productivity)

## Tags / keywords
journal, diary, memories, photo journal, AI, life log

## Contact email
danielsentertainmentresearch@gmail.com

## Data safety answers

Answers for Play Console → App content → Data safety, based on what the code
actually does:

- **Does your app collect or share any of the required user data types?** Yes.
- **Is all user data encrypted in transit?** Yes (HTTPS only).
- **Do you provide a way for users to request that their data is deleted?**
  Yes. Users can delete events, erase everything the AI remembers (in the
  app's privacy policy), delete their
  account in Settings → Delete account, and uninstalling removes all data
  on the phone. Play also asks for a web link for account deletion
  requests: use the privacy policy's contact email.
- **Data types**:
  - Photos and videos → Photos: *shared* with Anthropic, at the user's
    request, for app functionality. Optional. Not collected.
  - Personal info → Other info (free-text notes, free writes and
    memories): same as photos. Free writes are sent to Anthropic after the
    user writes one, to make short labels and to notice whether they might
    need support (what is noticed stays on the phone); not collected.
  - Personal info → Email address and/or Phone number: *collected* for
    account management (Firebase Authentication). Required.
  - Personal info → User IDs: *collected* for account management
    (includes the public wallet address when signing in with a Web3
    identity).
  - Device or other IDs (advertising ID): *collected and shared* by the
    AdMob SDK for advertising. Optional (only when a video is watched).
  - App activity → App interactions, and App info and performance →
    Diagnostics: *collected* by the AdMob SDK for advertising and fraud
    prevention.
- **Purposes**: App functionality, Account management, Advertising or
  marketing, Fraud prevention, security, and compliance.
  - Location → Precise location (from a photo's GPS data, or a typed place
    name): *shared* with OpenStreetMap Nominatim (place names) and
    Open-Meteo (optional weather), at the user's request, for app
    functionality. Optional. Not collected (never stored off the phone by
    the developer). The app does not request the phone's location
    permission.
- No contacts, financial or health data is collected.
- **Contains ads**: Yes.

> Google counts data sent to a third party at the user's request as
> "shared". If Play's form treats a user-initiated transfer differently when
> you fill it in, follow the in-form help text. The facts above stay the same.
