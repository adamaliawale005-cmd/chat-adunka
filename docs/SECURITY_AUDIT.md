# Security audit before public release

_Date: 26 October 2026_

Scope: every commit on every branch (`main`, `dev`, `ci-logs`, `phase2`,
`android-scaffold`), 33 commits and 547 file versions, plus GitHub Actions
artifacts and the published CI logs.

| Check | Result |
| --- | --- |
| Google API keys (`AIza…`) in any file version | None |
| Private keys (`-----BEGIN … PRIVATE KEY-----`) | None |
| Firebase service-account JSON | None |
| GitHub tokens (`ghp_`, `gho_`, …) | None |
| Android keystores / `.jks` / `key.properties` | None |
| `google-services.json` / `GoogleService-Info.plist` | Never committed |
| Hard-coded passwords | None (Gradle reads them from a git-ignored file) |
| `ci-logs` branch | Build/test output only; secret values masked by GitHub |
| Actions artifacts | Debug APKs and logs only; no signing-key artifact exists |
| Test accounts | Exist only in the local Firebase emulator during CI |

Nothing had to be removed from history and no credential needed rotating.

## What stays private after the repository is public

* GitHub Actions secrets (Firebase values, signing key, passwords). Pull
  requests from forks never receive them.
* The release keystore and its password: kept by the owner, never committed.
* User data: protected by Firebase Authentication and `firestore.rules`.
  The source code being public does not give anyone access; the rules are
  verified by 60 emulator tests and the end-to-end test.

## Public by design

The Firebase client values (project id, API key, app id) are included in
every Android, iOS and web app and are visible to anyone who installs the
app or opens the website. They identify the project; they do not grant
access. Access is enforced by the security rules.

Ongoing protection: CI fails if a credential is ever committed
(`tool/ci/scan_secrets.py`).
