# AduChat development status

_Last updated: 27 October 2026_

One Firebase backend for every platform: **aduchat-c4ee6**. Every push is
checked by GitHub Actions:

- **checks**: credential scan, formatting, analysis, 23 unit and widget tests.
- **rules**: 60 security-rule tests on the Firebase emulator.
- **e2e**: the real app on an Android emulator (API 32), driving the UI against the Firebase emulators. Users B and C act through separate connections, like separate phones.
- **Live backend check**: three temporary accounts on the real aduchat-c4ee6 project. Everything they create is deleted afterwards.
- **Web**: a release web build, opened in headless Chromium.
- **Apple**: an unsigned iOS build and a macOS build on a macOS runner.

## Test matrix

| Feature | Result | Evidence |
| --- | --- | --- |
| Android APK builds | PASS | CI (test/debug APK only; Google Play bundle is built separately) |
| Google Play target API 36 | PASS | CI reads the built APK: targetSdk 36, minSdk 24 |
| Signed App Bundle (.aab) for Google Play | WAITING | owner creates the upload key locally; built locally or by the protected Release App Bundle workflow (docs/RELEASE_SIGNING.md) |
| App installs and opens (Android) | PASS | emulator e2e |
| Connected to aduchat-c4ee6 | PASS | API key, app id and sender id verified online on every build |
| Email registration (live project) | PASS | live backend check: 3 new accounts |
| Two independent accounts message each other (live project) | PASS | live backend check: A to B and B to A |
| Outsider cannot read chats or private data (live project) | PASS | live backend check (HTTP 403) |
| Published security rules are current (live project) | PASS | live backend check (rules version probe) |
| Email registration through the app UI | PASS | emulator e2e |
| Profile with unique username | PASS | emulator e2e + rules tests |
| Username search | PASS | emulator e2e |
| Private messaging in real time | PASS | emulator e2e |
| Read receipts | PASS | emulator e2e |
| Group chat | PASS | emulator e2e (created in UI, both members exchange messages) |
| Photo messages | PASS | emulator e2e (bytes received intact) |
| Voice messages (transfer) | PASS | emulator e2e; recording UI is not automated |
| Voice call signaling | PASS | emulator e2e (rings, decline, call history) |
| Call audio/video on real devices | NOT TESTED | needs two physical devices |
| Web app builds and starts | PASS | Chromium smoke test reaches the sign-in screen |
| Public web URL | PASS | https://adamaliawale005-cmd.github.io/chat-adunka/ (deployed and checked by CI) |
| iPhone/iPad app compiles | PASS | unsigned iOS build on macOS runner |
| Mac app compiles | PASS | macOS build on macOS runner |
| iPhone install / TestFlight | NOT AVAILABLE | needs Apple Developer account (paid) |
| Windows / Linux | WEB | use the web app (installable from the browser); native desktop builds not provided |
| Phone (SMS) registration | NOT AVAILABLE | Firebase SMS needs the Blaze plan; hidden on web |
| Documents and videos | NOT AVAILABLE | need Cloud Storage (Blaze plan) |
| Push when app is closed | NOT AVAILABLE | needs Cloud Functions (Blaze plan) |
| Web: in-app banner for new messages (page on screen) | PASS | real-browser CI check with two accounts on aduchat-c4ee6 |
| Web: unread count in tab title, Open goes to the chat | PASS | real-browser CI check |
| Web: system notification while the tab/web app is in the background | PASS | real-browser CI check (Chromium, notifications allowed) |
| Web: tapped notification opens the chat after reload | PASS | real-browser CI check (`?open=chat:<id>` link) |
| Web: notifications when the browser/web app is fully closed | NOT AVAILABLE | needs FCM Web Push + deployed Cloud Functions (Blaze) |
| Android: notifications while the app runs | NOT TESTED | implemented (local notifications); not automated on a phone |
| English / Somali / Arabic (RTL) | PASS | widget tests: all keys in 3 languages, RTL layout |
| Security audit before going public | PASS | docs/SECURITY_AUDIT.md |

## Needs the owner

1. Google Play: see docs/PLAY_STORE_RELEASE_CHECKLIST.md.
2. Create the Google Play upload key and a test key **on your own computer**
   (docs/RELEASE_SIGNING.md). The old "Create signing keys" workflow was
   removed: it put the key and password in a downloadable artifact of a
   public repository (it was never run, nothing leaked).
3. iPhone: see docs/IOS_RELEASE.md (free iOS app registration in Firebase,
   paid Apple Developer membership for TestFlight).
4. Optional, paid (needs approval): Blaze plan for SMS sign-in, documents and
   videos, push while closed; a TURN relay for calls on restrictive networks.

## Remaining limitations

- Calls use STUN only; some mobile networks need a TURN relay.
- Somali and Arabic texts should be reviewed by native speakers.
- No end-to-end encryption (see docs/SECURITY.md).
