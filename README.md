# AduChat (Chat Aduunka)

Global messaging app for Android: phone or email sign-in, profiles with
unique usernames, contacts, private and group chats, photos and voice
messages, voice and video calls, notifications. Available in English,
Somali and Arabic, with light and dark mode.

Built with Flutter and Firebase. WebRTC handles calls.

## Download the app

GitHub > **Actions** > latest **AduChat CI** run on `main` > **Artifacts** >
`AduChat-debug-APK`. Unzip it and install `app-debug.apk` on the phone.

The app needs a Firebase project to sign in. Until the Firebase secrets are
added, it opens a "Setup required" screen.

## Documentation

* [Firebase setup checklist](docs/FIREBASE_SETUP.md): what you need to do
  in Firebase and GitHub, and what costs money
* [Architecture](docs/ARCHITECTURE.md): code layout, data model, calls
* [Security and privacy](docs/SECURITY.md): what is and is not protected
* [Testing](docs/TESTING.md): automated checks and the two-phone test plan
* [Development status](DEVELOPMENT_STATUS.md): completed and remaining work
