# Firebase setup for AduChat

Project: **aduchat-c4ee6** · Android package: **com.aduchat.chat_adunka**

This checklist lists every step that needs your Google/Firebase or GitHub
account. Nothing here can be done from the code. Billing is never needed
for the steps marked **Free**.

## What each Firebase service costs

| Service | Used for | Spark (free) plan | Blaze (pay-as-you-go) |
| --- | --- | --- | --- |
| Authentication: email/password | Testing sign-in | **Free** | Free |
| Authentication: phone/SMS | Real phone sign-in | **Not available** (test numbers only) | Billed per SMS |
| Cloud Firestore | Profiles, chats, messages, photos, voice notes, call signaling | **Free** up to 50k reads, 20k writes per day | Free tier, then per use |
| Cloud Messaging (FCM) | Delivering push notifications | **Free** | Free |
| Cloud Functions | Sending pushes when the app is closed | Not available | 2M calls/month free, then per use |
| Cloud Storage | Videos and documents | Not available for new projects | 5 GB stored + 100 GB/month downloads free, then per use |

Sources: Firebase pricing page and the Cloud Storage FAQ (Sept 2024 changes).
Check the current prices before upgrading.

**Recommendation:** test on Spark with email sign-in and Firebase test
phone numbers first. Move to Blaze only when you approve real SMS, push
notifications for closed apps, and video/document sharing. On Blaze, set a
budget alert in Google Cloud Billing.

---

## Checklist

### 1. Register the Android app (Free)

1. Firebase console > project **aduchat-c4ee6** > Project overview > **Add app > Android**.
2. Package name: `com.aduchat.chat_adunka` (exactly this).
3. App nickname: `AduChat`. Leave the SHA field empty for now (step 5).
4. Download `google-services.json`. **Do not commit it to GitHub.** Its
   values go into secrets (step 4).

### 2. Turn on sign-in methods (Free)

Firebase console > Build > **Authentication** > Get started > Sign-in method:

* **Email/Password: Enable.** This is the free testing method.
* **Phone: Enable.** Then under **Phone numbers for testing** add fictional
  numbers with fixed codes, for example:
  * `+252 61 000 0001` → `111111`
  * `+252 61 000 0002` → `222222`

  Test numbers never send a real SMS. Real numbers need Blaze.

### 3. Create the Firestore database and rules (Free)

1. Build > **Firestore Database** > Create database > **Production mode**.
   Choose a location close to your users. The location cannot be changed
   later, so note it down for the Cloud Functions region.
2. Open the **Rules** tab, replace everything with the contents of
   [`firestore.rules`](../firestore.rules), and click **Publish**.
3. Optional: indexes. AduChat needs no composite indexes. The
   [`firestore.indexes.json`](../firestore.indexes.json) file only turns
   off indexing of large photo/blob fields, to save cost. It can be deployed
   later with the Firebase CLI (`firebase deploy --only firestore:indexes`).

### 4. Add GitHub repository secrets (Free)

GitHub > repository **chat-adunka** > Settings > Secrets and variables >
Actions > **New repository secret**. Copy the values from `google-services.json`:

| Secret name | Value in google-services.json |
| --- | --- |
| `FIREBASE_API_KEY` | `client[0].api_key[0].current_key` |
| `FIREBASE_APP_ID` | `client[0].client_info.mobilesdk_app_id` |
| `FIREBASE_MESSAGING_SENDER_ID` | `project_info.project_number` |
| `FIREBASE_PROJECT_ID` | `project_info.project_id` (should be `aduchat-c4ee6`) |
| `FIREBASE_STORAGE_BUCKET` | `project_info.storage_bucket` (optional) |

The CI step **Validate Firebase configuration** checks the formats without
printing the values.

### 5. Stable signing key and SHA fingerprints (Free)

Firebase phone sign-in only works for an app whose signing certificate is
registered in Firebase, and every APK must be signed with the same key so
updates install over the old version.

1. GitHub > Actions > **Create signing keys (run once)** > Run workflow.
2. Open the finished run and download the artifact
   `aduchat-signing-keys-PRIVATE`. It is deleted automatically after one day.
3. Open `README.txt` from the artifact and create the five secrets it lists
   (`ANDROID_DEBUG_KEYSTORE_BASE64`, `ANDROID_RELEASE_KEYSTORE_BASE64`,
   `ANDROID_RELEASE_STORE_PASSWORD`, `ANDROID_RELEASE_KEY_ALIAS`,
   `ANDROID_RELEASE_KEY_PASSWORD`).
4. Keep `release.keystore` and its password in a safe place outside GitHub.
   **If they are lost, future versions cannot update installed apps.**
5. Firebase > Project settings > Your apps > AduChat > **Add fingerprint**.
   Add the SHA-1 and SHA-256 values from `README.txt` for both keys.
6. Delete the downloaded files from your computer.

### 6. Build

GitHub > Actions > **AduChat CI** > Run workflow (branch `main`). When it
finishes, download **AduChat-debug-APK** (and **AduChat-release-APK** once
the release key secrets exist) from the run's Artifacts section.

---

## Optional (Blaze plan, needs your approval)

### Real SMS codes

Upgrade to Blaze, then real phone numbers work with no code change. Set
SMS region policy (Authentication > Settings) to allow only the countries
you serve, to limit SMS fraud costs.

### Videos and documents (Cloud Storage)

1. Upgrade to Blaze. Build > **Storage** > Get started.
2. Rules tab: paste [`storage.rules`](../storage.rules) and Publish.
3. GitHub > Settings > Secrets and variables > Actions > **Variables** tab >
   New variable `STORAGE_ENABLED` = `true`. Rebuild.

### Notifications when the app is closed (Cloud Functions)

Source code is in [`functions/`](../functions). It is not deployed
automatically.

```
npm install -g firebase-tools
firebase login
cd functions && npm install && cp .env.example .env   # set FUNCTIONS_REGION
cd .. && firebase deploy --only functions --project aduchat-c4ee6
```

### Calls on all networks (TURN relay)

Calls use free Google STUN servers, which work on many Wi-Fi and mobile
networks. Behind strict or carrier-grade NAT, which is common on mobile
data, a TURN relay is needed. Options:

| Option | Cost | Notes |
| --- | --- | --- |
| Self-hosted coturn on a small VPS | about $5–10/month + bandwidth | You manage the server |
| Managed TURN (Cloudflare Calls TURN, Twilio, Metered, Xirsys) | Free tier or pay per GB relayed | Easiest |

A relayed video call uses roughly 0.5–1.5 MB per minute in each direction.
Configure with secrets `TURN_URLS` (comma separated, e.g.
`turn:turn.example.com:3478?transport=udp,turns:turn.example.com:5349`),
`TURN_USERNAME` and `TURN_CREDENTIAL`, then rebuild.

**Note:** fixed TURN credentials are stored inside the APK and can be
extracted. For production, use short-lived credentials issued by a server
(the coturn REST API, or the provider's API through a Cloud Function).

## Feature switches (GitHub repository variables)

| Variable | Default | Effect |
| --- | --- | --- |
| `STORAGE_ENABLED` | `false` | `true` enables videos/documents and stores photos/voice in Storage |
| `EMAIL_AUTH_ENABLED` | `true` | Shows email/password sign-in |
| `PHONE_AUTH_ENABLED` | `true` | Shows phone/SMS sign-in |
