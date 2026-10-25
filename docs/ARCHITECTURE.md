# AduChat architecture

Flutter (Dart) app for Android, with an architecture that can also target
iOS. Backend: Firebase (Authentication, Cloud Firestore, Cloud Messaging,
optional Cloud Storage and Cloud Functions). Calls: WebRTC.

## Code layout

```
lib/
  main.dart                 Firebase init, offline cache, background push handler
  app.dart                  MaterialApp: themes, languages, root navigator
  config/                   build-time settings (Firebase options, feature switches, TURN)
  l10n/                     English, Somali, Arabic texts + RTL support
  theme/                    light/dark themes, chat bubble colours
  state/                    device settings (theme/language), signed-in session state
  models/                   AppUser, AccountPrivate, Chat, ChatMessage, Attachment, calls
  services/
    auth_service.dart       phone OTP, email/password, password reset, sign-out
    user_service.dart       profiles, unique usernames, privacy, presence, block, report, delete account
    chat_service.dart       direct + group chats, messages, receipts, typing, edit/delete, retries
    attachment_service.dart photos/voice inline (free) or Cloud Storage (Blaze), forwarding
    contacts_service.dart   opt-in contact discovery (no upload)
    call_service.dart       WebRTC calls, Firestore signaling, ICE restart, history
    notification_service.dart FCM tokens, local notifications, tap navigation
  screens/                  UI (auth, chat, contacts, groups, calls, settings, profile)
  widgets/                  avatars, empty/error states, dialogs
android/                    permanent Android project (do not regenerate)
firestore.rules             Firestore security rules
storage.rules               Cloud Storage security rules
firestore.indexes.json      index settings (no composite indexes needed)
functions/                  Cloud Functions for push notifications (Blaze)
firebase-tests/             security rules tests (run in the emulator in CI)
test/                       Flutter unit and widget tests
tool/ci/                    CI helpers (credential scan, Firebase config check)
```

## Firestore data model

| Path | Contents | Who can read | Who can write |
| --- | --- | --- | --- |
| `users/{uid}` | public profile: name, username, about, photo, presence | any signed-in user (single get) | owner |
| `users/{uid}/private/account` | phone, email, privacy and notification settings | owner | owner |
| `users/{uid}/devices/{token}` | FCM push tokens | owner | owner |
| `users/{uid}/blocked/{uid2}` | block list | owner | owner |
| `users/{uid}/calls/{callId}` | call history | owner | owner, or the caller of that call |
| `usernames/{username}` | `{uid}` (uniqueness) | signed-in (get only) | claimant |
| `phoneIndex/{e164}` | `{uid}` for people who allow phone lookup | signed-in (get only) | verified owner of the number |
| `directory/{uid}` | name + username for search (opt-in) | signed-in | owner |
| `chats/{chatId}` | type, members, admins, name, last message, typing, unread | members | members (rules limit which fields) |
| `chats/{chatId}/messages/{id}` | message | members | sender creates; receiver sets status; sender edits/deletes |
| `chats/{chatId}/blobs/{id}` | inline photo/voice bytes | members | sender |
| `calls/{callId}` | WebRTC offer/answer, status | caller and callee | caller and callee (role-limited) |
| `calls/{callId}/candidates/{id}` | ICE candidates | caller and callee | caller and callee |
| `reports/{id}` | abuse reports | nobody (console only) | reporter |

Direct chat ids are the two user ids sorted and joined with `_`. Group
chat ids are random. Message ids are generated on the phone, so a retry
can never create a duplicate.

### Message status

* Direct: `sent`, then `delivered` (receiver's phone fetched it), then
  `read` (receiver opened the chat). With read receipts off, a message only
  reaches `delivered`.
* Groups: `readBy` lists the members who read the message. The sender sees
  blue ticks when everyone has read it.
* Pending (clock icon) means the message is saved on the phone and waiting
  to reach the server. It is sent automatically when the phone is online
  again. Failed sends show a retry button.

## Calls

1. The caller creates `calls/{id}` with an SDP offer and writes call-history
   entries. The callee's entry starts as `missed` until answered.
2. The callee's app listens for `calls where calleeId == me and status == ringing`
   and shows the incoming-call screen.
3. The callee answers with an SDP answer. Both sides exchange ICE candidates.
4. If the network changes, the caller performs an ICE restart (up to 3 times).
5. Ringing times out after 45 seconds (missed call).

STUN (free, Google) is always used. A TURN relay is used when configured.
When the app is closed, incoming calls need the `notifyIncomingCall` Cloud
Function (Blaze) to wake the phone.

## Free plan vs Blaze plan

The app works on the free Spark plan with email sign-in or Firebase test
phone numbers, Firestore, and in-app notifications. Blaze adds real SMS,
push notifications when the app is closed (Cloud Functions), and
videos/documents (Cloud Storage). See [FIREBASE_SETUP.md](FIREBASE_SETUP.md).

## Building

CI (`.github/workflows/build-apk.yml`) runs a credential scan, `dart format`,
`flutter analyze`, the Flutter tests, the security-rules tests in the
Firebase emulator, and a Cloud Functions syntax check. It then builds the
debug APK, plus the release APK when signing secrets exist. All logs are
pushed to the `ci-logs` branch.

Local build (needs Flutter stable, Android SDK and Java 17):

```
flutter pub get
flutter build apk --debug --dart-define-from-file=defines.json
```

where `defines.json` (never committed) holds the same keys that
`tool/ci/firebase_check.py` writes.
