# Firebase setup for Chat Aduunka

Everything below uses the free **Spark** plan. Do not upgrade to Blaze unless
you decide to.

## 1. Create the Firebase project (owner)

1. Open https://console.firebase.google.com and click **Add project**.
2. Name it (for example `chat-aduunka`). Google Analytics is optional.
3. In **Project overview → Add app → Android**, enter the package name
   **`com.aduchat.chat_adunka`**. Leave the SHA fields empty for now.
4. Download `google-services.json`. **Do not commit it to GitHub.** Its values
   go into repository secrets (step 3).

## 2. Turn on the services

* **Build → Authentication → Get started → Sign-in method → Phone → Enable.**
* **Authentication → Settings → SMS region policy:** allow the countries you
  will test with (for example Somalia and Saudi Arabia).
* **Authentication → Sign-in method → Phone → Phone numbers for testing:** add
  a few fictional numbers with fixed codes (e.g. `+252 61 000 0001` → `123456`).
  Test numbers do not send real SMS and do not count against the free SMS limit.
* **Build → Firestore Database → Create database** (production mode, a nearby
  region). Then open **Rules**, paste the contents of `firestore.rules` from this
  repository, and click **Publish**.
* Cloud Messaging is enabled automatically.

## 3. Add GitHub Actions secrets (owner)

GitHub → repository → **Settings → Secrets and variables → Actions → New
repository secret**. Take the values from `google-services.json`:

| Secret | Where in google-services.json |
| --- | --- |
| `FIREBASE_API_KEY` | `client[0].api_key[0].current_key` |
| `FIREBASE_APP_ID` | `client[0].client_info.mobilesdk_app_id` |
| `FIREBASE_MESSAGING_SENDER_ID` | `project_info.project_number` |
| `FIREBASE_PROJECT_ID` | `project_info.project_id` |
| `FIREBASE_STORAGE_BUCKET` | `project_info.storage_bucket` (optional) |

## 4. Stable signing key and SHA fingerprints

Phone sign-in only works for an app whose signing certificate is registered in
Firebase. The build reads a fixed key from the `ANDROID_DEBUG_KEYSTORE_BASE64`
secret. Without it, every build is signed with a different temporary key.

After a build with the secret set, open the run in GitHub Actions. The
**SHA fingerprints** annotation shows `SHA1` and `SHA256`. Add both in Firebase:
**Project settings → Your apps → Android app → Add fingerprint**.

## 5. Push notifications

The app requests notification permission and stores each device's FCM token
privately in `users/{uid}/devices`. Sending a push when a new message arrives
needs a trusted server, because the sending credentials must never be in the
app. Options:

* **Cloud Functions** (a Firestore trigger on `chats/{chatId}/messages/{id}`).
  Needs the Blaze plan. It has a free monthly allowance, but needs a billing
  account. Owner approval required.
* A small server you already run, using the FCM HTTP v1 API with a service
  account.

Until then, new messages appear instantly while the app is open, and the
notification setup can be tested from **Firebase console → Messaging → New
campaign → Send test message**, using a token from Firestore.

## Free-plan limits worth knowing

* Phone auth on Spark has a small daily SMS quota. Use test numbers for
  development.
* Firestore free tier: 50,000 reads, 20,000 writes per day, 1 GiB storage.
* Profile pictures are compressed to about 256 px and kept in Firestore, so no
  Cloud Storage bucket (Blaze-only for new projects) is needed.
