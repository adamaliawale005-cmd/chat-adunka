import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';

/// Which Firebase project the app connects to.
///
/// 1. Automated tests (USE_FIREBASE_EMULATOR=true): local Firebase
///    emulators with the demo project "demo-aduchat". No real data.
/// 2. Otherwise the official project aduchat-c4ee6 from
///    firebase_options.dart, when its values are filled in.
/// 3. Fallback while those values are missing: --dart-define values from
///    CI (GitHub secrets), accepted only when they are for aduchat-c4ee6.
class FirebaseConfig {
  FirebaseConfig._();

  static const bool useEmulator = bool.fromEnvironment('USE_FIREBASE_EMULATOR');

  /// Address of the computer running the emulators, as seen from the Android
  /// emulator (10.0.2.2 is the host machine).
  static const String emulatorHost =
      String.fromEnvironment('FIREBASE_EMULATOR_HOST', defaultValue: '10.0.2.2');

  static const String _defApiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const String _defAppId = String.fromEnvironment('FIREBASE_APP_ID');
  static const String _defSender =
      String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const String _defProject = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const String _defBucket =
      String.fromEnvironment('FIREBASE_STORAGE_BUCKET');

  static bool get _defsUsable =>
      _defProject == OfficialFirebase.projectId &&
      _defApiKey.isNotEmpty &&
      RegExp(r'^1:\d+:android:[0-9a-f]+$').hasMatch(_defAppId) &&
      _defSender.isNotEmpty;

  static String get source => useEmulator
      ? 'emulator'
      : OfficialFirebase.isComplete
          ? 'official'
          : _defsUsable
              ? 'build-settings'
              : 'missing';

  static String get projectId => useEmulator ? 'demo-aduchat' : OfficialFirebase.projectId;

  static String get apiKey => switch (source) {
        'emulator' => 'emulator-api-key',
        'official' => OfficialFirebase.apiKey,
        _ => _defApiKey,
      };

  static String get appId => switch (source) {
        'emulator' => '1:000000000000:android:0000000000000000',
        'official' => OfficialFirebase.appId,
        _ => _defAppId,
      };

  static String get messagingSenderId => switch (source) {
        'emulator' => '000000000000',
        'official' => OfficialFirebase.messagingSenderId,
        _ => _defSender,
      };

  static String get storageBucket => switch (source) {
        'emulator' => '',
        'official' => OfficialFirebase.storageBucket,
        _ => _defBucket,
      };

  static bool get isConfigured => source != 'missing';

  static FirebaseOptions get options => FirebaseOptions(
        apiKey: apiKey,
        appId: appId,
        messagingSenderId: messagingSenderId,
        projectId: projectId,
        storageBucket: storageBucket.isEmpty ? null : storageBucket,
      );
}
