# Phase 2 plan: global messaging features

_Prepared 28 October 2026. Nothing here is started until Phase 1 (PR #2)
is deployed and merged. Items marked **Owner/paid** need your explicit
approval before any setting is changed or anything is bought._

Ground rules for every item: work on a feature branch, keep all existing
accounts, chats and features working (compatibility tests like
`firebase-tests/app-compat.test.mjs` for every rules change), add tests,
open a PR with CI evidence, and never publish or deploy without approval.

## Order and dependencies

| # | Workstream | Needs Blaze? | Can start before approvals? | Rough effort |
| --- | --- | --- | --- | --- |
| 2 | Mandatory email verification | No | **Yes** | 2–3 days |
| 3 | Secure account recovery | Partly (session revocation) | Yes (app parts) | 3–4 days |
| 9 | Privacy policy + deletion request page | No | Yes (needs your name/contact) | 2 days |
| 7 | App Check (monitor mode) + abuse limits | Functions: yes | App part yes | 4–6 days |
| 1 | International phone OTP | **Yes** | Code yes, enabling no | 3–5 days + device tests |
| 5 | Notifications when the app is closed | **Yes** | Code yes | 5–8 days + device tests |
| 4 | Calls with TURN | **Yes** + TURN server | Code yes | 4–6 days + network tests |
| 8 | Android / iPhone / web compatibility | iOS: Apple membership | Android/web yes | ongoing |
| 10 | Google Play production readiness | Play account | Partly | 2–3 weeks incl. closed test |
| 6 | Reviewed end-to-end encryption | No | Design only | **2–4 months + external audit** |

Recommended sequence: 2 → 3 → 9 → 7 (monitor) → *Blaze decision* → 1, 5, 4
→ device test round → 10 (closed test) → production. E2EE (6) runs as a
separate track and is its own release gate.

---

## 1. International phone number + SMS OTP

* **Today:** UI with country picker and E.164 formatting exists
  (`lib/screens/auth/sign_in_screen.dart`, `lib/utils/phone.dart`); SMS is
  off because Firebase charges per SMS (Blaze).
* **Work:** enable Phone provider; **SMS region policy** (allow only the
  countries you serve, e.g. Somalia, Saudi Arabia, Gulf, East Africa, then
  widen) to block SMS-pumping fraud; reCAPTCHA/Play Integrity verification;
  clear error messages for every `verifyPhoneNumber` error code; resend
  cool-down; Firebase **test phone numbers** for CI and for Google's
  reviewers; register SHA-1/SHA-256 of the test key and the Play app
  signing key.
* **Tests:** two physical Android phones on different operators; web
  (reCAPTCHA); wrong code, expired code, too many attempts, no network.
* **Owner/paid:** Blaze plan with a budget alert; SMS price varies by
  country (check Firebase pricing for SO/SA before enabling).

## 2. Email registration with mandatory verification

* **Today:** a verification email is sent but not required.
* **Work:** "Verify your email" screen after sign-up (resend with
  cool-down, "I've verified" reloads the token, sign out); rules require
  `request.auth.token.email_verified == true` (or a phone sign-in) to send
  messages, create chats, calls and reports — reading own profile and
  settings stays allowed so nobody is locked out.
* **Existing accounts:** kept. Unverified email users see the verify
  screen on next launch and can resend the email; their chats stay intact.
  Staged rollout: app update first, rules enforcement only after most
  users have the update (watch Firebase Auth user list).
* **Tests:** emulator e2e (unverified user is blocked from sending, then
  verifies and can send); rules tests; live check.

## 3. Secure account recovery

* **Work:** password reset (exists; add error handling + rate limit
  message); link phone and email to one account (`linkWithCredential`) so
  either can recover it; re-authentication before deleting the account or
  changing email/phone; "Sign out of all devices" (Cloud Function revokes
  refresh tokens and deletes device tokens); email notice on new sign-in
  (later). No security questions.
* **Tests:** reset flow, linking conflicts (number already used by
  another account), re-auth errors.

## 4. Voice and video calls with TURN

* **Today:** WebRTC with STUN only; signaling tested in CI; the
  short-lived credential function `turnCredentials` is ready (PR #2), not
  deployed; the app does not call it yet.
* **Work:** app requests credentials before each call (falls back to STUN
  if unavailable); TURN over UDP 3478, TCP and **TURNS on 443** for
  restrictive networks; call quality stats (relay vs direct) in logs
  without personal data; fix "declined/missed" edge cases; ringtone,
  speaker/Bluetooth routing, camera switch, permission-denied screens.
* **Owner/paid choice:** (a) self-hosted coturn on a small VPS (fixed
  monthly cost, you manage it), or (b) a managed TURN service (pay per GB).
  Either way the shared secret goes into Firebase Secret Manager only.
* **Tests:** Wi-Fi ↔ 4G/5G, two operators, one side behind strict NAT,
  network drop and reconnect, call while the other app is in background.

## 5. Notifications when the app is closed

* **Today:** functions `notifyNewMessage`, `notifyIncomingCall`,
  `notifyMissedCall` are written, not deployed (Blaze). Web notifications
  work while the browser is open.
* **Work:** deploy functions to the Firestore region; Android
  notification channels; **full-screen incoming-call notification** with
  Answer/Decline (Android 14+ `USE_FULL_SCREEN_INTENT` declaration — allowed
  for calling apps) and a phone-call foreground service; web push (FCM
  service worker + VAPID key) for closed browsers; iOS APNs key + PushKit/
  CallKit (needs Apple account); token cleanup on logout (exists, test it);
  tap opens the right chat; muted chats; privacy: "hide message preview"
  option (exists) and no message text in pushes once E2EE is on.
* **Huawei** phones without Google services cannot receive FCM: either
  Huawei Push Kit (separate account) or document "notifications only
  while open" for those devices.
* **Tests:** app killed / background / screen locked on 2+ Android
  phones (one Samsung/Xiaomi with aggressive battery saving), web closed,
  duplicates, muted chats.

## 6. Secure messaging and reviewed end-to-end encryption

* **Today:** TLS in transit, Google encryption at rest, strict rules; **no
  E2EE** (stated honestly in `docs/SECURITY.md`). Never claim otherwise.
* **Options:**
  * **Signal protocol via official libsignal** (Rust, maintained by
    Signal). Strongest choice, but **AGPL-3.0 licensed**: the app must be
    distributed under AGPL-compatible terms — a legal decision for you.
    Needs Rust/FFI bindings for Android, iOS and web (WASM).
  * **MLS (RFC 9420)** via OpenMLS (MIT): designed for groups and
    multi-device; also needs FFI bindings.
  * Community Dart ports of Signal exist but are **not audited**; not
    acceptable for a WhatsApp-grade claim.
* **Required design pieces:** identity/pre-key bundles in Firestore,
  per-device keys (phone + web), adding a new device, key backup and
  recovery (PIN-protected), safety-number verification screen, group key
  rotation on member changes, encrypted attachments, push without
  content, server-side search removed, migration of existing plaintext
  chats (stay plaintext, marked "not end-to-end encrypted").
* **Gate:** written design → independent security review → implementation
  behind a flag → external audit → release. Realistically 2–4 months.
  Until then the app must be described as "encrypted in transit and at
  rest", not "end-to-end encrypted".

## 7. Firebase App Check and server-side abuse prevention

* **App Check:** `firebase_app_check` with Play Integrity (Android; works
  fully once distributed via Play), App Attest (iOS), reCAPTCHA Enterprise
  (web). Debug provider for CI. **Monitor mode first**, enforce on
  Firestore, Auth and Functions only when ≥ 99% of requests are verified.
* **Abuse limits (Cloud Functions, Blaze):** per-user counters for messages
  per minute, new chats per day, reports per day, directory searches, call
  attempts; blocking function on sign-up (Identity Platform) to throttle
  mass registration; automatic temporary restriction after many reports.
* **Moderation:** private admin tool (separate web page, admin custom
  claim) to read reports, see the reported message, warn/suspend/delete,
  with an audit log that stores no message content beyond the report.
* **Cost control:** budget alerts at small amounts, `maxInstances` on all
  functions (already set to 10).

## 8. Android, iPhone and web compatibility

* Android: min API 24, target 36 (done). Device matrix: Android 8, 10,
  13, 15/16; Samsung, Xiaomi, Tecno/Infinix (common in East Africa), one
  low-RAM phone.
* Web: Chrome, Edge, Firefox, Safari (iOS "Add to Home Screen").
* iPhone: unsigned build compiles in CI. **Owner/paid:** Apple Developer
  Program, Firebase iOS app, APNs key; then TestFlight.
* Accessibility (screen reader labels, text scaling), Somali and Arabic
  review by native speakers, RTL screenshots.

## 9. Privacy policy and account deletion

* **Needs from you:** legal name of the publisher (person or company),
  country, support email.
* **Work:** privacy policy and terms pages hosted free on GitHub Pages
  (`…/chat-adunka/privacy.html`, `terms.html`), linked in the app and on
  the sign-up screen with a recorded acceptance (version + date on the
  private account document); **account deletion request page**
  (`delete-account.html`) that works without the app (sign in on the web
  app → delete, or a request form for people who lost access); accurate
  retention text (what deletion removes and what stays in other people's
  chats — see `PLAY_STORE_RELEASE_CHECKLIST.md`); age rule (13+ or 18+).
* **Improve deletion:** also delete the user's own uploaded files once
  Storage is enabled, and run a scheduled cleanup of orphaned data.

## 10. Google Play production readiness

* Upload key on your computer, signed AAB, Play App Signing, fingerprints
  in Firebase (`RELEASE_SIGNING.md`).
* Play Console: Data safety, content rating, target audience, app access
  (reviewer test account), permissions declarations (camera, microphone,
  contacts, full-screen intent, foreground service types for calls).
* Store listing: name, short/long description (no E2EE claim), 512 px
  icon (exists), 1024×500 feature graphic, 4–8 phone screenshots.
* **Closed test:** new personal developer accounts need **12+ testers
  opted in for 14 continuous days** before production access.
* Final gate: every item in `RELEASE_READINESS.md` PASS or explicitly
  accepted by you; then GO/NO-GO review.

## Approvals and purchases you will be asked for (none done yet)

| Decision | Unlocks |
| --- | --- |
| Firebase Blaze + budget alert | SMS OTP, Cloud Functions (push, TURN credentials, abuse limits), Storage (documents/video) |
| TURN server (self-host or managed) | Reliable calls on mobile networks |
| Google Play developer account | AAB upload, closed test, production |
| Apple Developer Program | iPhone app, iOS push |
| E2EE library/licence choice (AGPL libsignal vs MLS) | Phase 6 implementation |
| Publisher name, country, support email | Privacy policy, Play listing |
