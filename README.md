# AduChat (Chat Aduunka)

Global messaging app for the web, Android, iPhone/iPad and Mac, all on one
Firebase backend (accounts work everywhere): email or phone sign-in, profiles with
unique usernames, contacts, private and group chats, photos and voice
messages, voice and video calls, notifications. Available in English,
Somali and Arabic, with light and dark mode.

Built with Flutter and Firebase. WebRTC handles calls.

## Use AduChat

* **Web (any phone or computer):** https://adamaliawale005-cmd.github.io/chat-adunka/
  In the browser menu choose "Install app" / "Add to Home Screen" to use it
  like an app. Works on Windows, Linux, macOS, Android and iPhone browsers.
* **Android:** GitHub > **Actions** > latest **AduChat CI** run on `main` >
  **Artifacts** > `AduChat-APK` (or `AduChat-debug-APK`). Unzip and install.
* **iPhone / iPad:** use the web app until the App Store / TestFlight
  release (see [docs/IOS_RELEASE.md](docs/IOS_RELEASE.md)).

## Documentation

* [Firebase setup checklist](docs/FIREBASE_SETUP.md): what you need to do
  in Firebase and GitHub, and what costs money
* [Architecture](docs/ARCHITECTURE.md): code layout, data model, calls
* [Security and privacy](docs/SECURITY.md): what is and is not protected
* [Testing](docs/TESTING.md): automated checks and the two-phone test plan
* [Development status](DEVELOPMENT_STATUS.md): completed and remaining work
* [Security audit](docs/SECURITY_AUDIT.md): checks done before going public
