# EventLens Privacy Policy

_Last updated: 4 October 2026_

EventLens ("the app") lets you record events with photos and notes and have an
AI write a detailed account of each one. This policy explains what the app
does with your information.

## Your account

You need an account to use the app. Accounts are provided by Google
Firebase Authentication. Depending on how you sign up, Firebase stores
your email address or phone number, a protected form of your password,
or your Google account identifier, plus sign-in timestamps. Phone numbers
are confirmed with an SMS code. If you turn on fingerprint or face
unlock, the check happens on your phone; no biometric data leaves the
device. Firebase's privacy information: <https://firebase.google.com/support/privacy>.

## Ads

Extra ring colours, and daily weather lookups, can be unlocked by watching
rewarded videos, served by Google AdMob. To show and measure ads, AdMob collects information such as
your device's advertising ID, IP address, and how you interact with the
ad. Ads appear only when you choose to watch one. You can reset or delete
your advertising ID in your phone's settings. Google's policy:
<https://policies.google.com/technologies/ads>.

## What stays on your device

Your photos, notes, event descriptions and saved memories are stored only in
the app's private storage on your phone. Each account signed in on the
phone has its own separate library, so people sharing a phone do not see
each other's events. The developer runs no server of
its own and never receives your photos, notes, descriptions or memories. Cloud backup of app data is disabled. Uninstalling
the app permanently deletes everything it stored.

Your Anthropic API key is stored in encrypted storage on your device and is
sent only to Anthropic, to authenticate your requests.

## What is shared, and with whom

When you ask the app to describe an event, and only then, the app sends the
following to **Anthropic, PBC** (`api.anthropic.com`) over an encrypted
connection:

- that event's photos, resized to a maximum of 1568 pixels;
- that event's notes, title, place, date and time;
- short summaries of your recent events;
- the memories you have saved in the app.

Anthropic processes this to generate the description and returns it to your
phone. Because the requests use your own API key, Anthropic handles them
under your agreement with Anthropic and its privacy policy:
<https://www.anthropic.com/legal/privacy>.

The weather and location of an event are never sent to Anthropic.

### Place names and weather

- When you add a photo that carries a GPS position, the app reads the
  position and the time it was taken from the photo itself, on your phone.
  To suggest a place name, it sends only those coordinates to
  **OpenStreetMap Nominatim** (`nominatim.openstreetmap.org`).
  Policy: <https://osmfoundation.org/wiki/Privacy_Policy>.
- If you choose to look up the weather for an event (optional), the app
  sends the event's coordinates, or the place name you typed, and its date
  to **Open-Meteo** (`open-meteo.com`), which returns the weather for that
  hour. Policy: <https://open-meteo.com/en/terms#privacy>.

No account details, photos or notes are sent to either service.

### Export

Settings → Export creates a zip of your library (an Obsidian-compatible
folder of notes, your photos, and a data file) on your phone. Where it goes
next is up to you, through your phone's share sheet.

Apart from Firebase (accounts), AdMob (optional rewarded videos),
OpenStreetMap and Open-Meteo described above, the app contains no analytics or tracking SDKs and shares
no data with anyone else.

## Photos of other people

Your photos may include other people. The app never uses face recognition. The
AI names people only when your own notes or saved memories identify them.

## Your choices

- Delete any event, description or memory in the app at any time.
- Remove your API key in Settings at any time.
- Export your whole library in Settings at any time.
- Leave the weather unlooked-up; it is optional for every event.
- Uninstall the app to delete all of its data on the phone.
- Delete your account in Settings → Delete account, or ask by emailing
  the address below.

## Children

The app is not directed at children under 13 and requires a paid API account.

## Changes

Updates to this policy will be posted at this address with a new date.

## Contact

danielsentertainmentresearch@gmail.com
