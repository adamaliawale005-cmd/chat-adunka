# Publishing the security rules: backup, deploy, verify, roll back

_Prepared 28 October 2026 for PR #2 (Firestore rules version `2026-10-27`).
Firebase project: **aduchat-c4ee6**. Free: publishing rules costs nothing
and does not need the Blaze plan._

Rules never change or delete data. Publishing or rolling back only changes
who may read and write, and takes effect within about a minute (up to 10
minutes for apps that are already open).

## What changes for users

Nothing visible. Every write the current app makes (Android APK, web) was
replayed against the new rules in CI (`firebase-tests/app-compat.test.mjs`),
and the end-to-end test drove the real app on an Android emulator under the
new rules. The only app change in PR #2 is the rules-version constant; the
new rules still answer the old version (`2026-10-25`), so installed apps
keep working before and after they update. Existing accounts, chats,
groups, messages and call history are untouched.

Refused from now on (by design): blocked people writing into the blocker's
chat list, members posting fake admin notices, username squatting,
downloading the whole directory in one request, malformed reports, oversized
call data, and (once Storage is enabled) installer/script/HTML/SVG uploads.

## Step 1 — Back up the rules that are live now

Do **both** a) and b); they take two minutes.

a) **Console copy** (exactly what is live):
   Firebase console > aduchat-c4ee6 > **Firestore Database > Rules**.
   Select all text in the editor, copy it into a new file on your computer
   named `firestore.rules.live-backup-2026-10-28.txt`. Keep it.
   (Storage is not enabled yet, so there are no Storage rules to back up.)

b) **Git copy** (what CI verified as live on 27 October, version
   `2026-10-25`): commit `ff36642` on `main`
   <https://github.com/adamaliawale005-cmd/chat-adunka/blob/ff366422afae4429225599c17c8d2a7921fca412/firestore.rules>.

If a) and b) differ, stop and tell me: someone changed the live rules in
the console, and those changes must be reviewed before anything is
replaced.

The console also keeps its own version history (the list on the left of
the Rules editor), which is used for rollback.

## Step 2 — Publish (only after you approve)

Choose one.

**Option A: Firebase console (no tools needed)**
1. Open the new rules:
   <https://github.com/adamaliawale005-cmd/chat-adunka/blob/fix/release-readiness-security/firestore.rules>
   and click **Raw**; select all and copy.
2. Firebase console > Firestore Database > **Rules**: replace the whole
   editor content with the copied text.
3. Click **Publish**. The console checks the syntax first; if it shows an
   error, do not publish and send me the message.

**Option B: Firebase CLI on your computer**
```bash
git clone https://github.com/adamaliawale005-cmd/chat-adunka && cd chat-adunka
git checkout fix/release-readiness-security
npx firebase-tools login
npx firebase-tools deploy --only firestore:rules --project aduchat-c4ee6
```
Do not run `firebase deploy` without `--only firestore:rules`: that
would also try to deploy Cloud Functions (needs Blaze) and Storage.

## Step 3 — Verify the live backend

1. GitHub > Actions > **AduChat CI** > **Run workflow** > choose branch
   `fix/release-readiness-security` > Run. (I can also start it.)
   The job **Live backend check** must show all PASS, including:
   * Published security rules are current
   * Outsider cannot post into the group
   * A member cannot forge an admin event
   * The user directory cannot be downloaded in one query
   * Usernames cannot be reserved without a profile
   * Test data and test accounts deleted

   The job **Web notifications in a real browser** must also pass.
2. Quick phone check with the APK you already have installed (no update
   needed): open a chat, send a text, a photo and a voice note, open a
   group, start and end a call. Everything should work as before.

## Step 4 — If anything breaks: roll back

Any of these is a reason to roll back immediately: messages fail to send,
"permission denied" / "rules outdated" errors in the app, or a FAIL in the
live check other than the new-protection lines.

* **Console:** Firestore Database > Rules > in the version list on the
  left, select the previous version (published before today) > the editor
  shows it > **Publish**. Or paste your backup file from Step 1a and Publish.
* **CLI:** `git checkout ff36642 -- firestore.rules && npx firebase-tools deploy --only firestore:rules --project aduchat-c4ee6`

Rollback is safe at any time: rules do not modify data, and the previous
rules accept everything the app does. Then tell me what failed; PR #2 stays
unmerged until it is fixed.

## Step 5 — Merge

Only after Step 3 passes: merge PR #2. The push to `main` runs the full CI
again (checks, rules tests, end-to-end, APK, web, live backend check, web
notifications, GitHub Pages deploy).
