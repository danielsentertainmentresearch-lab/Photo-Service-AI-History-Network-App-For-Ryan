# Releasing EventLens on Google Play

Everything in the code is already set up for release. These steps need the
owner's own accounts, so they can't be done ahead of time.

## 0. Decide before the first upload (permanent after that)

- **Application ID**: currently `com.danielsentertainmentresearch.eventlens`.
  Once a build is uploaded to Play, this can never change. To use another
  one, change `applicationId` and `namespace` in `android/app/build.gradle.kts`
  and move `MainActivity.kt` to the matching package folder.
- **App name**: "EventLens" (`android:label` in
  `android/app/src/main/AndroidManifest.xml`, and `appName` in `lib/app.dart`).
  The name can change later, but check that it isn't already taken on Play.

## 1. Create an upload key (once, keep it forever)

```bash
keytool -genkey -v -keystore ~/eventlens-upload.jks -keyalg RSA \
  -keysize 2048 -validity 10000 -alias upload
```

Back up the `.jks` file and both passwords somewhere safe, such as a password
manager. Never commit them. With Play App Signing (the default), Google holds
the real app-signing key. If the upload key is lost, Google support can reset
it, but that takes days.

## 2. Get a signed build

### Option A: GitHub Actions (recommended)

In the GitHub repo, go to **Settings → Secrets and variables → Actions** and add:

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | output of `base64 -w0 ~/eventlens-upload.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | store password |
| `ANDROID_KEY_ALIAS` | `upload` |
| `ANDROID_KEY_PASSWORD` | key password |

From then on, every run of the **Android** workflow (on each push to `main`,
on a `v*` tag, or started by hand from the Actions tab) is signed with the
upload key. Download `app-release.aab` from the run's `eventlens-N` artifact.
The version code is the workflow run number, so every upload is unique. To
bump the visible version, edit `version:` in `pubspec.yaml` (the part before
`+`).

### Option B: build locally

Create `android/key.properties` (it is git-ignored):

```properties
storePassword=YOUR_STORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=upload
storeFile=/absolute/path/to/eventlens-upload.jks
```

Then run `flutter build appbundle --release`. The output is
`build/app/outputs/bundle/release/app-release.aab`.

## 3. Google Play Console

1. Create a developer account at <https://play.google.com/console> (one-time
   $25 fee). New personal accounts must run a **closed test with at least 12
   testers for 14 days** before they can publish to production. Plan for that.
2. **Create app**: name EventLens, type App, Free.
3. **Store listing**: copy the text from [store/listing.md](store/listing.md).
   Upload `store/play_icon_512.png`, `store/feature_graphic_1024x500.png` and
   at least 2 phone screenshots (take them on a device with a few sample
   events).
4. **Privacy policy**: host [PRIVACY_POLICY.md](PRIVACY_POLICY.md) at a public
   URL (for example GitHub Pages, or a public gist) and paste the URL.
5. **App content** forms:
   - *Data safety*: use the answers in [store/listing.md](store/listing.md#data-safety-answers).
   - *Content rating*: complete the questionnaire (no violence, gambling or
     user-to-user sharing). The usual result is "Everyone" or "Teen".
   - *Target audience*: 18+ is simplest, because users must hold their own
     paid API key.
   - *Ads*: No ads.
6. **Testing → Closed testing**: create a track, add testers, and upload the
   signed `.aab`. After the testing period, **promote to Production**.

## 4. Pre-release checklist

- [ ] The latest Android workflow run is green.
- [ ] Install the release APK on a real phone. Add an API key, create an
      event with camera and gallery photos, describe it, accept a memory
      suggestion, then create a second event and confirm the account
      references the first one.
- [ ] Turn on airplane mode, describe an event, and check that the error is
      friendly and Retry works.
- [ ] Privacy policy URL is live.
