# AduChat security and privacy

This page states what AduChat actually guarantees today.

## What is protected

| Area | Protection |
| --- | --- |
| Network | All traffic to Firebase uses TLS (HTTPS). Cleartext HTTP is disabled in the Android manifest. |
| Calls | WebRTC media is always encrypted with DTLS-SRTP between the two phones (or through the TURN relay, which cannot decrypt it). |
| Data access | Firestore security rules (`firestore.rules`) allow access only to signed-in users, and only to their own data or chats they belong to. Covered by automated emulator tests in CI (`firebase-tests/`). |
| Files | Storage rules (`storage.rules`) let only chat members read attachments and only the sender upload into their own folder. Files are fetched through the SDK, so the rules are checked on every access. No public links are stored in messages. |
| Phone numbers | Never in the public profile. They are stored only in the owner's private document. Lookup is by exact number only (`phoneIndex`, get-only, list denied), and only for people who allow it. |
| Address book | Never uploaded. Numbers are checked one by one on the phone, and matches are kept only on the phone. |
| Usernames | Unique, claimed atomically. Enforced by the rules, not only by the app. |
| Blocking | Enforced by the rules: a blocked person cannot create messages or calls to the blocker. |
| Group membership | Enforced by the rules. Non-members cannot read messages; only admins can add or remove members. |
| Message integrity | Senders cannot impersonate others. Only receivers can mark messages delivered or read. Edits are limited to the sender within 48 hours. |
| Abuse reports | Write-only: nobody can read reports from the app. Review them in the Firebase console. |
| Credentials | No API secrets, service accounts or signing keys in the repository. CI fails if one is committed (`tool/ci/scan_secrets.py`). Firebase values come from GitHub secrets. |
| Account deletion | Deletes profile, username, phone index, directory entry, private settings, device tokens, block list and call history, then the Firebase Auth account. |
| Logging | The app does not log message contents or credentials. CI prints no secret values. |

## What is NOT provided

* **No end-to-end encryption of messages.** Messages are encrypted in
  transit and at rest by Google, but the Firebase project owner (and Google,
  as processor) can technically read stored messages. Adding E2EE would
  need a reviewed protocol such as the Signal protocol (libsignal), with
  key management and multi-device support. AduChat does not use a custom
  cryptographic scheme.
* **Deleted messages** are removed from the database. Copies other people
  already made (screenshots, forwards) cannot be removed.
* **Rate limiting** relies on Firebase's built-in protections: Auth SMS
  throttling, Firestore quotas, and the rules limiting field sizes. For
  stronger abuse prevention, enable **Firebase App Check** (free; needs the
  Play Integrity provider, which needs the app on Google Play).
* **Phone-number enumeration:** someone could try many exact numbers one by
  one. The cost of each lookup and Firebase quotas limit this; App Check
  would further reduce it. Users can switch off "Find me by phone number".
* **TURN credentials** configured as build secrets end up inside the APK.
  Use short-lived credentials from a server for production.
* **Inline photos and voice notes** (free plan) are stored in Firestore
  documents protected by the same membership rules. They are not
  separately encrypted.

## Dependency security

CI runs `flutter pub outdated` on every build and reports security
advisories that pub prints (see the `ci-logs` branch). Update dependencies
regularly with `flutter pub upgrade`, then run the full CI.
