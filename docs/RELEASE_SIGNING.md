# Android signing keys: create them safely on your own computer

_Last updated: 27 October 2026_

AduChat uses two different keys. Keep them apart.

| Key | Used for | Where it lives | If it leaks or is lost |
| --- | --- | --- | --- |
| **Upload key** (`aduchat-upload.jks`) | Signing the `.aab` you upload to Google Play | Your computer + two encrypted offline backups; optionally the protected `play-release` GitHub environment | Ask Google Play support for an **upload key reset** (possible because Google holds the real app signing key with Play App Signing) |
| **Test key** (`aduchat-test.keystore`) | Test APKs from routine CI, so test installs update each other and phone sign-in works on test phones | GitHub secret `ANDROID_DEBUG_KEYSTORE_BASE64` | Low impact: make a new one and replace its fingerprints in Firebase |

The **app signing key** that users' phones trust is created and kept by
Google (Play App Signing). You never handle it.

> **Never** generate a key inside GitHub Actions, never put a key or
> password in an Actions artifact, a commit, an issue, a chat or an email.
> This repository is public: anyone signed in to GitHub can download
> artifacts of any run. The old "Create signing keys" workflow did exactly
> that and has been removed (it was never run; see "Investigation" below).

---

## Part A — Upload key for Google Play (do this once)

Use a computer you trust (your own, up to date, with disk encryption on).
You need Java 17+ (`keytool` comes with it; Android Studio includes one).

1. Open a terminal **in a folder outside the repository** (for example
   `Documents/AduChat-keys`).
2. Create the key. `keytool` asks for a password — type a long one
   (at least 16 random characters, from your password manager). Use the
   same password for the store and the key when asked.

   ```bash
   keytool -genkeypair -v \
     -keystore aduchat-upload.jks -storetype JKS \
     -alias upload -keyalg RSA -keysize 4096 -validity 10000 \
     -dname "CN=AduChat Upload, O=AduChat"
   ```

   The password is typed at the prompt, so it never appears in your shell
   history.

3. Save the password in your password manager (entry "AduChat upload key").
4. Make **two encrypted offline backups** of `aduchat-upload.jks`, e.g. two
   USB drives kept in different places, each inside an encrypted archive
   (7-Zip AES-256, VeraCrypt, or your OS's encrypted disk image) protected
   with a *different* strong password, also stored in the password manager.
5. Note the public fingerprints (safe to share):

   ```bash
   keytool -list -v -keystore aduchat-upload.jks -alias upload | grep -E "SHA1:|SHA256:"
   ```

### Option 1 (recommended): build the `.aab` on your computer

1. Create `android/key.properties` in your local checkout (git-ignored,
   never commit it):

   ```properties
   storeFile=/full/path/to/aduchat-upload.jks
   storePassword=<the password>
   keyAlias=upload
   keyPassword=<the password>
   ```

2. Build: `flutter build appbundle --release --dart-define-from-file=defines.json`
   (the same Firebase values CI uses).
3. Delete `android/key.properties` when finished.

Without `key.properties` the Gradle build **refuses** to make a release
App Bundle, so a debug-signed bundle can never be uploaded by mistake.

### Option 2: let a protected GitHub workflow build it

Only if you cannot build on your computer. Order matters:

1. GitHub > Settings > **Environments** > New environment `play-release`.
   **First** add yourself under *Required reviewers* and limit
   *Deployment branches* to `main`. (If the environment does not exist,
   GitHub would create it without protection on the first run.)
2. Then add these as **environment secrets** of `play-release` (not as
   repository secrets):
   * `ANDROID_UPLOAD_KEYSTORE_BASE64` — the file encoded as one line:
     macOS/Linux `base64 -i aduchat-upload.jks | tr -d '\n' | pbcopy`
     (or `base64 -w0 aduchat-upload.jks`), Windows PowerShell
     `[Convert]::ToBase64String([IO.File]::ReadAllBytes("aduchat-upload.jks")) | Set-Clipboard`.
     Paste directly into the secret field; do not save it in a file.
   * `ANDROID_UPLOAD_STORE_PASSWORD`, `ANDROID_UPLOAD_KEY_ALIAS` (`upload`),
     `ANDROID_UPLOAD_KEY_PASSWORD`.
3. Actions > **Release App Bundle** > Run workflow (on `main`). Approve the
   run. It builds, checks that the bundle is not debug-signed, prints only
   the public certificate fingerprint and deletes its temporary key copy.
4. Download `AduChat-release-AAB` and upload it to Play Console yourself.

Routine CI (`AduChat CI`) never receives these secrets.

### After the first upload to Play Console

1. Accept **Play App Signing** (default for new apps).
2. Play Console > Test and release > App integrity > App signing: copy the
   **app signing key** SHA-1 and SHA-256 and add them in Firebase
   (Project settings > Your apps > AduChat Android > Add fingerprint).
   These are required for phone sign-in and Play Integrity (App Check) in
   apps installed from Google Play.
3. Increase the number after `+` in `pubspec.yaml` for every upload.

---

## Part B — Test key for test APKs (optional, recommended)

```bash
keytool -genkeypair -v -keystore aduchat-test.keystore -storetype JKS \
  -alias androiddebugkey -storepass android -keypass android \
  -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US"
```

This uses the standard public debug password on purpose: it is a test key,
not a secret release key. Store it as the repository secret
`ANDROID_DEBUG_KEYSTORE_BASE64` (base64 as above) and add its SHA-1/SHA-256
(`keytool -list -v -keystore aduchat-test.keystore -storepass android`) in
Firebase so phone sign-in works on test APKs. Never use it for Google Play.

---

## Investigation of the removed workflow (27 October 2026)

Checked through the GitHub API on the public repository:

* `.github/workflows/create-signing-keys.yml` (workflow id 395783682):
  **0 runs** ever. All 60 workflow runs in the repository belong to
  `build-apk.yml` (52), `apple.yml` (7) and an older `generate-android.yml` (1).
* Artifacts named `aduchat-signing-keys-PRIVATE`: **0**. Every artifact in
  the repository is a debug APK, unsigned iOS build, web build or log.
* No `AduChat-APK` / `AduChat-release-AAB` artifacts exist, so CI never
  held a release key.
* Full git history (49 commits on `main`) contains no keystore, `.jks`,
  `key.properties`, service-account or private-key file; the only match
  for `storePassword=` is a shell variable reference in a workflow.

Conclusion: no key was generated or exposed, so no rotation is needed.
If you ever did run it in a fork or copy of the repository, treat that key
as compromised and create a new one with Part A.
