# Google Play release checklist

_Last updated: 27 October 2026_

Status values: **DONE** (verified in this repository or in CI), **TODO**
(work left, usually for the owner), **N/A**. Nothing here was submitted to
Google Play.

Package name (application ID): `com.aduchat.chat_adunka` (permanent; it
cannot be changed after the first upload).

## Build

| Item | Status | Notes |
| --- | --- | --- |
| Target API level 36 (Android 16) or later | DONE | `android/app/build.gradle.kts` sets `targetSdk` to at least 36; CI reads the built APK and fails below 36 |
| Minimum Android version | DONE | API 23 (Android 6.0), needed by Firebase Auth and WebRTC |
| Signed release App Bundle (`.aab`) | TODO | Owner creates the **upload key on their own computer** (`docs/RELEASE_SIGNING.md`, Part A) and builds the `.aab` locally, or with the manual, approval-protected **Release App Bundle** workflow (`play-release` environment). Gradle refuses to build a release bundle without the upload key, and the workflow fails if the bundle is debug-signed. Routine CI never sees the upload key |
| Keep the upload key safe | TODO | Password in a password manager; two encrypted offline backups. If lost or exposed, request an upload-key reset through Play Console (possible with **Play App Signing**, the default for new apps). Never generate or store keys in Actions artifacts |
| Version code increases with every upload | TODO | `version:` in `pubspec.yaml` (currently `2.0.0+3`; the number after `+` must grow each upload) |
| Firebase SHA fingerprints | TODO | After enabling Play App Signing, add the **app signing key** SHA-1/SHA-256 from Play Console to Firebase (Project settings > Android app). Needed for phone sign-in and App Check |

## Store listing

| Item | Status | Notes |
| --- | --- | --- |
| App name, short and full description | TODO | Suggested name: "AduChat". Describe only features that work (see `DEVELOPMENT_STATUS.md`) |
| App icon 512 × 512 | DONE | `web/icons/Icon-512.png` (same artwork as the app icon) |
| Feature graphic 1024 × 500 | TODO | |
| Phone screenshots (2–8) | TODO | Take them from the release build on a phone |
| Support email | TODO | Owner must provide; not invented here |
| Privacy policy URL | TODO | Must be a public web page naming the developer and a contact, and describing the data below. Not written here because the legal owner and contact are not known |

## App content (Play Console declarations)

| Item | Status | Notes |
| --- | --- | --- |
| Data safety form | TODO | Fill from the "Data handled" table below |
| Account deletion inside the app | DONE | Settings > Account > Delete account (`UserService.deleteAccount`) |
| Account deletion web link | TODO | Play requires a web page where people can request deletion without the app. Possible: a page explaining the steps in the web app (https://adamaliawale005-cmd.github.io/chat-adunka/ > Settings > Account > Delete account), plus a contact for people who cannot sign in. Needs the owner's contact |
| What deletion removes | DONE (to disclose) | Removed: profile, username, phone index, directory entry, private settings, device tokens, block list, call history, the login account. **Kept:** messages the person already sent stay in the recipients' chats (direct and group), including inline photos/voice notes; the person's user ID stays in the member list of their chats and groups (shown as a deleted account). The privacy policy and Data safety form must say this |
| User-generated content (chat) | DONE (to declare) | Report and block exist (`reports` collection, write-only; blocking enforced by security rules). Owner must review reports in the Firebase console and state the moderation process |
| Content rating questionnaire | TODO | Chat apps that let users communicate are usually rated with "users interact" |
| Target audience / age | TODO | Recommended 18+ or 13+ (no features for children); not for children under 13 |
| Ads | DONE | No ads |
| Encryption claims | DONE (to disclose) | Traffic uses TLS; calls use DTLS-SRTP. **Messages are not end-to-end encrypted**; do not claim E2EE anywhere in the listing |
| Permissions explanation | DONE | Camera, microphone (calls, voice notes), notifications, contacts (optional, never uploaded), photos (sending images) |
| Login details for app review | TODO | Create a dedicated test account (email + password) and enter it in App access. Do not reuse a personal account |

## Data handled (for the Data safety form)

| Data | Collected | Purpose | Shared |
| --- | --- | --- | --- |
| Email address or phone number | Yes (sign-in) | Account | No |
| Name, username, profile photo, "about" | Yes | App functionality | Visible to other users |
| Messages, photos, voice notes | Yes (stored in Firestore) | App functionality | Only with chat members |
| Call signaling and call history | Yes | App functionality | Only with the other participant |
| Contacts | Optional, processed on the phone only | Find friends | Not uploaded |
| Device push tokens | Yes (Android) | Notifications | No |
| Online status / last seen | Yes (can be hidden) | App functionality | Visible to other users |

All data is stored in Google Firebase (project `aduchat-c4ee6`) and encrypted
in transit. Users can delete their account in the app.

## Developer account and testing

| Item | Status | Notes |
| --- | --- | --- |
| Play Console developer account | TODO | One-time USD 25 fee and identity verification by the owner |
| Closed test | TODO | A new **personal** developer account must run a closed test with at least 12 opted-in testers for 14 days in a row before applying for production |
| Test on real phones before submitting | TODO | Login, profile, direct and group chats, read receipts, photos, voice notes, voice and video calls both ways on different networks, notifications with the app open and in the background, block/report, account deletion |
| Submit for review | TODO | Only after the items above |

## Not needed for the first Android release (paid, needs approval)

* Firebase Blaze plan: SMS sign-in, Cloud Storage (documents/videos),
  Cloud Functions (push notifications when the app is fully closed,
  including Web Push for the web app).
* TURN relay for calls on restrictive mobile networks.

Email sign-in, messaging, inline photos and voice notes, calls over STUN and
notifications while the app is running all work on the free plan.

## Official references (check again before submitting)

* https://support.google.com/googleplay/android-developer/answer/11926878
* https://support.google.com/googleplay/android-developer/answer/14151465
* https://support.google.com/googleplay/android-developer/answer/13327111
* https://support.google.com/googleplay/android-developer/answer/6112435
