# AduChat development status

_Last updated: 26 October 2026_

## Verification summary

"Automated" means GitHub Actions CI on every push. The end-to-end test
installs the app on an **Android emulator** (API 32) and drives the real UI,
against the **Firebase emulators** running the real `firestore.rules`. A
second and third user act through separate Firebase connections, like
separate phones. Nothing on this page was tested on a physical phone or on
the live `aduchat-c4ee6` project yet; see "Blocked by configuration".

| Feature | Result | How verified |
| --- | --- | --- |
| APK builds | PASS | CI (debug build; release build waits for the signing key) |
| App installs and opens | PASS | Android emulator (end-to-end test) |
| Connects to Firebase | PASS (emulator) / BLOCKED (aduchat-c4ee6) | e2e; live project needs the official config, see below |
| Email registration | PASS | e2e through the UI |
| Phone (SMS) registration | NOT TESTED | real SMS needs Blaze; test numbers not run |
| Profile save + unique username | PASS | e2e through the UI + 60 rules tests |
| User search by username | PASS | e2e through the UI |
| Send / receive private messages | PASS | e2e: A to B and B to A in real time |
| Read receipts | PASS | e2e |
| Group chat (create, send, receive) | PASS | e2e through the UI |
| Photo messages | PASS | e2e: sent by A, downloaded intact by B |
| Voice messages | PASS (transfer) | e2e: file sent and received intact; recording UI not automated |
| Documents and videos | NOT AVAILABLE | need Cloud Storage (Blaze plan, needs your approval) |
| Voice call signaling | PASS | e2e: call rings on B (WebRTC offer), decline ends call, history saved |
| Call audio/video media | NOT TESTED | needs two physical phones; mobile data may need a TURN relay |
| Notifications while app runs | NOT TESTED | implemented; not automated |
| Push notifications when app is closed | NOT AVAILABLE | need Cloud Functions (Blaze plan) |
| Security rules | PASS | 60 emulator tests + e2e (outsiders denied for direct and group chats) |
| English / Somali / Arabic (RTL) | PASS | widget tests: all 308 keys in 3 languages, RTL layout |
| Credential scan, analysis, formatting | PASS | CI |

## Blocked by configuration (needs the owner once)

1. The official Android config of `aduchat-c4ee6` (`google-services.json`)
   is only in the Firebase console. The GitHub secrets hold values from
   `chat-aduunka` / `chat-adunka`. Once the file is provided,
   `tool/import_google_services.py` writes it into
   `lib/config/firebase_options.dart`, and the app then always uses
   `aduchat-c4ee6` regardless of secrets.
2. A permanent release signing key: run the "Create signing keys" workflow
   and add its 2 secrets.

## Remaining limitations

- Call media quality on mobile networks: STUN only until a TURN relay is
  configured (paid or self-hosted; needs approval).
- Blaze-plan features not enabled: real SMS, documents/videos, push when the
  app is closed.
- Somali and Arabic texts should be reviewed by native speakers.
- No end-to-end encryption (see docs/SECURITY.md).
