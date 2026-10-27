# AduChat release readiness (worldwide / Google Play)

_Assessed 27 October 2026 against baseline `ff36642` (CI #52 green) and
PR #2 (`fix/release-readiness-security`). Nothing has been published,
merged, deployed or paid for._

## Final recommendation: **NO-GO**

Blocking gates that are not met (any one of them is enough for NO-GO):

1. **International phone OTP** – not available (needs Blaze; SMS region
   policy and anti-fraud settings not configured; never tested on a phone).
2. **Call delivery** – TURN relay not configured; audio/video never tested
   on two physical phones or across mobile operators; no incoming-call
   wake-up while the app is closed.
3. **Closed-app push** – Cloud Functions not deployed (needs Blaze); FCM
   never tested on Android/Huawei/iOS in background or killed state.
4. **Release signing** – no upload key yet, no signed `.aab`, no Play App
   Signing fingerprints in Firebase. (The insecure CI key workflow has been
   removed; safe process in `RELEASE_SIGNING.md`.)
5. **Required policy documents** – no public privacy policy URL, no account
   deletion web page, no support contact, Data safety form not filled.
6. **User safety** – reports are write-only with no review workflow or
   response process; email verification is not enforced; no server-side
   rate limiting; no App Check.

## Readiness matrix

Status: **PASS** verified by an executed test (CI run named) ·
**FAIL** verified broken or missing · **NOT TESTED** implemented but not
verified where it matters · **BLOCKED** needs an owner decision, payment
or account.

### Security and signing

| Item | Status | Evidence / code path |
| --- | --- | --- |
| Insecure CI key-generation workflow | **PASS (fixed)** | `create-signing-keys.yml` deleted in PR #2. API check: 0 runs, 0 `aduchat-signing-keys-PRIVATE` artifacts; git history (49 commits) has no key material → no rotation needed |
| Routine CI isolated from upload key | **PASS (fixed)** | `build-apk.yml` builds debug/test APKs only; `release-bundle.yml` manual + `play-release` environment |
| Debug-signed bundle impossible | **PASS (fixed)** | `android/app/build.gradle.kts` refuses `bundleRelease` without `key.properties`; workflow checks cert ≠ Android Debug |
| Upload key exists, offline backups | **BLOCKED** | Owner: `RELEASE_SIGNING.md` Part A |
| Signed `.aab`, Play App Signing fingerprints in Firebase | **BLOCKED** | After Part A and first Play upload |
| Firestore rules: membership, existence, blocking, admin-only posting, system messages, privacy, calls, reports | **PASS (CI emulator)** | `firestore.rules`; `firebase-tests/adversarial.test.mjs`, `firestore.test.mjs` — see "CI results" |
| Storage rules: types, sizes, blocked uploads | **PASS (CI emulator)** | `storage.rules`; `firebase-tests/storage.test.mjs` |
| New rules published to aduchat-c4ee6 | **BLOCKED** | Owner: `firebase deploy --only firestore:rules,storage` before merging |
| End-to-end encryption | **FAIL (by design today)** | `docs/SECURITY.md` states it honestly. Needs a reviewed libsignal integration with multi-device keys and recovery; separate release gate if WhatsApp-grade privacy is required |
| App Check (Play Integrity / App Attest / reCAPTCHA Enterprise) | **FAIL** | Not integrated. Plan: metrics-only, then enforce |
| Server-side rate limits (sign-up, lookups, messages, media, calls, reports) | **FAIL** | Only rules-level size limits and the TURN function limit exist |
| Static TURN passwords kept out of APK/JS | **PASS (fixed)** | `tool/ci/firebase_check.py` fails the build if `TURN_USERNAME/TURN_CREDENTIAL` are set |
| Budget alerts, redacted audit logs | **BLOCKED** | Needs Blaze / Cloud Billing |
| OWASP MASVS/MASTG assessment, dependency vulnerability scan | **NOT TESTED** | Only `flutter pub outdated` report exists |

### Accounts

| Item | Status | Evidence |
| --- | --- | --- |
| Email registration and sign-in (live project) | **PASS** | CI #52 live backend check, 3 accounts |
| Email verification enforced | **FAIL** | `auth_service.dart` sends the email but nothing requires it |
| Password reset / resend verification | **NOT TESTED** | Code exists (`sendPasswordReset`, `resendEmailVerification`) |
| Phone OTP with country picker, E.164 | **BLOCKED** | UI exists (`sign_in_screen.dart`, `utils/phone.dart`); SMS needs Blaze, SMS region policy, SHA fingerprints |
| Phone/email linking and recovery | **FAIL** | Not implemented |
| Session management (sign out other devices) | **FAIL** | Not implemented |
| Tests on two physical devices | **NOT TESTED** | |

### Messaging, media, groups

| Item | Status | Evidence |
| --- | --- | --- |
| Private real-time messages, read receipts | **PASS** | CI #52 e2e (Android emulator) + live check |
| Groups (create, members exchange) | **PASS** | CI #52 e2e |
| Photos and voice notes (inline, free plan) | **PASS** | CI #52 e2e (bytes intact) |
| Documents and video | **BLOCKED** | Needs Cloud Storage (Blaze) |
| Edit/delete/forward, search, offline queue, large groups, low connectivity | **NOT TESTED** | Implemented; no automated or device test |
| Orphan cleanup (deleted chats, deleted accounts' media) | **FAIL** | Direct-chat messages/blobs and deleted accounts' sent media are kept; no scheduled cleanup |

### Calls and notifications

| Item | Status | Evidence |
| --- | --- | --- |
| Call signaling (ring, decline, history) | **PASS** | CI #52 e2e |
| Two-way audio/video on real phones, Wi-Fi/4G/5G, operators | **NOT TESTED** | |
| TURN/TURNS relay with short-lived credentials | **BLOCKED** | Server function `turnCredentials` written and unit-tested (PR #2), not deployed; app integration pending; needs a TURN server/provider |
| Incoming call while app closed | **BLOCKED** | `functions/index.js` `notifyIncomingCall`; needs Blaze; no full-screen call notification on Android yet |
| Message push while closed (Android, Huawei, web, iOS) | **BLOCKED** | Functions not deployed; Huawei devices without Google services will not receive FCM |
| Web notifications while page open / in background tab | **PASS** | CI #52 web-notify (9/9) |
| Logout removes device token | **NOT TESTED** | `notification_service.dart` deletes token on sign-out |

### Store, policy, quality

| Item | Status | Evidence |
| --- | --- | --- |
| targetSdk ≥ 36, permanent app id | **PASS** | CI #52: targetSdk 36, minSdk 24, `com.aduchat.chat_adunka` |
| versionCode | **PASS** (3) | Must increase per upload |
| Privacy policy URL, support email | **BLOCKED** | Needs legal owner name and contact |
| Account deletion in app | **NOT TESTED** on device | `UserService.deleteAccount` |
| Account deletion web request page | **FAIL** | Not built |
| User agreement acceptance (recorded) | **FAIL** | Only a notice on the welcome screen |
| Report review workflow / moderation | **FAIL** | Reports readable only in Firebase console |
| Data safety, content rating, target audience (13+/18+) | **BLOCKED** | Owner fills in Play Console; data table in `PLAY_STORE_RELEASE_CHECKLIST.md` |
| Feature graphic 1024×500, screenshots | **FAIL** | Not produced |
| Store listing copy | **NOT TESTED** | Draft not yet written |
| Closed test (12 testers × 14 days, new personal accounts) | **BLOCKED** | Needs Play Console account and testers |
| Somali/Arabic text and RTL | **NOT TESTED** by native speakers | Widget tests cover keys and RTL layout |
| Accessibility, performance/memory device matrix | **NOT TESTED** | |
| iOS | **BLOCKED** | Unsigned build compiles (Apple run #6 green; #7 was a GitHub macOS capacity failure, not a code failure). Needs Apple Developer membership, Firebase iOS app, APNs key |

## Paid or account actions that need explicit owner consent

| Action | Why | Cost (approx., check current pricing) |
| --- | --- | --- |
| Firebase **Blaze** plan | SMS OTP, Cloud Functions (push, TURN credentials), Cloud Storage, budget alerts | Pay-as-you-go; SMS is charged per message and varies by country |
| TURN relay (self-hosted coturn or provider) | Calls on mobile networks | Server or per-GB relay traffic |
| Google Play developer account | Publishing | One-time registration fee |
| Apple Developer Program | iPhone TestFlight / App Store | Yearly fee |
| Domain + hosting for privacy/deletion pages (optional) | Policy URLs (GitHub Pages works for free) | Optional |

## Realistic security limitations (to disclose)

* No end-to-end encryption: the Firebase project owner and Google (as
  processor) can technically access stored messages.
* Firebase client config is public by design; access control relies on the
  rules, which are tested but cannot stop a logged-in account from abusing
  allowed actions (spam, directory paging) without App Check and rate limits.
* Phone-number lookup is exact-match only but can still be enumerated slowly.
* No app is hack-proof; compromised phones, screenshots and forwarded
  copies are outside the app's control.

## Next steps (in order)

1. Owner: review PR #2, deploy rules, merge.
2. Owner: create upload + test keys locally (`RELEASE_SIGNING.md`).
3. Owner decision: approve Blaze with a budget alert (unblocks OTP, push,
   Storage, TURN credentials).
4. Code: email-verification gate (rules + app), App Check (metrics mode),
   client use of `turnCredentials`, full-screen incoming-call notification,
   recorded terms acceptance, deletion web page, report review tooling.
5. Device test plan on at least two physical Android phones (+ one Huawei),
   then closed test with 12+ testers for 14 days.
