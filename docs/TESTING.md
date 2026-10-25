# AduChat testing

## Automated (run by CI on every push)

| Suite | What it checks | Where |
| --- | --- | --- |
| Credential scan | No keys, keystores or service accounts committed | `tool/ci/scan_secrets.py` |
| Formatting | `dart format` | CI |
| Static analysis | `flutter analyze` (errors and warnings fail the build) | CI |
| Unit tests | Phone parsing, usernames, chat ids, group read status, edit window, settings, formatting | `test/logic_test.dart` |
| Widget tests | Welcome screen, setup screen, Arabic right-to-left, Somali, translation completeness and placeholders | `test/widget_test.dart` |
| Security rules | 43 tests covering profiles, private data, usernames, phone lookup, direct and group chats, blocking, receipts, editing, typing, calls, candidates, reports and Storage | `firebase-tests/` (Firebase emulator) |
| Cloud Functions | Syntax check | CI |
| Android build | Debug APK, plus release APK when signing secrets exist | CI |

Results of the latest run are on the `ci-logs` branch (`SUMMARY.txt`).

## Manual test plan (two Android phones)

Prerequisites: the Firebase setup checklist steps 1–6 are done, and both
phones have the same APK installed. Use two email accounts, or two
Firebase test phone numbers.

Record results in the table at the end. Mark a test as passed only after it
has actually been run on the phones.

| # | Test | Steps | Expected |
| --- | --- | --- | --- |
| 1 | Install | Download the APK artifact, unzip, open `app-debug.apk`, allow installing from this source | AduChat icon appears |
| 2 | Launch | Open the app | Teal splash, then the welcome screen |
| 3 | Language | Welcome > globe icon > Soomaali, then العربية | Texts change; Arabic is right-to-left |
| 4 | Register (email) | Create account > Email > new email + password | Profile setup opens |
| 5 | Register (phone) | Create account > Phone > test number > code | Profile setup opens |
| 6 | Profile | Enter name, username, photo > Continue | Home screen with 4 tabs |
| 7 | Duplicate username | Phone B tries the same username as A | "Already taken" |
| 8 | Search | B: Contacts > search A's username | A appears |
| 9 | Phone lookup | B searches A's full phone number (phone accounts) | A appears; after A turns off "Find me by phone number", A no longer appears |
| 10 | Send / receive | B opens A, sends text | A gets it instantly; B sees ✓ then ✓✓ |
| 11 | Read receipt | A opens the chat | B sees blue ✓✓ |
| 12 | Typing | A types | B sees "typing…" |
| 13 | Offline | B turns on airplane mode, sends, turns it off | Clock icon, then sent automatically |
| 14 | Reply / edit / delete / forward | Long-press a message | Each action works for both phones |
| 15 | Photo | Attach > Photo | Arrives and opens full screen |
| 16 | Voice note | Tap mic, speak, send | Plays on the other phone |
| 17 | Group | A creates a group with B | Both see the group and system message |
| 18 | Group admin | A turns on "only admins can send" | B cannot send |
| 19 | Voice call (same Wi-Fi) | A calls B | B sees incoming call; audio both ways |
| 20 | Video call | A video-calls B | Video both ways; flip camera, mute work |
| 21 | Call on mobile data | Both phones on mobile data | Works, or fails without TURN (note the networks) |
| 22 | Missed call | A calls, B does not answer for 45 s | Missed call in B's Calls tab |
| 23 | Notification (app in background) | B presses Home, A sends | B gets a notification; tapping opens the chat |
| 24 | Notification (app closed) | B swipes the app away, A sends | Needs Cloud Functions (Blaze); otherwise no notification |
| 25 | Block | B blocks A | A's messages and calls fail; B can unblock |
| 26 | Report | Long-press > Report | "Report sent" |
| 27 | Dark mode | Settings > Theme > Dark | Whole app dark |
| 28 | Logout / login | Sign out, sign in again | Chats are still there |
| 29 | Delete account | Sign in again, Settings > Account > Delete | Account removed; other phone shows "Deleted account" |
| 30 | Permissions | Deny microphone, then try a call | Clear message and a link to settings |
| 31 | Stability | Use the app for 15 minutes, rotate, background/foreground | No crashes |

### Results

| # | Phone A model / Android | Phone B model / Android | Network | Result | Notes |
| --- | --- | --- | --- | --- | --- |
| | | | | | |
