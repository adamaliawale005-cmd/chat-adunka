/// Official AduChat Firebase project: aduchat-c4ee6, Android app
/// com.aduchat.chat_adunka.
///
/// These are public identifiers, not secrets: Firebase puts the same values
/// into every Android app (google-services.json). Access to data is
/// protected by Firebase Authentication and firestore.rules, not by hiding
/// these values. Keeping them in the code means the app always connects to
/// the official project, whatever is stored in GitHub secrets.
///
/// Fill them from Firebase console > Project settings > Your apps > Android
/// app com.aduchat.chat_adunka (or run tool/import_google_services.py with
/// the downloaded google-services.json).
class OfficialFirebase {
  OfficialFirebase._();

  static const String projectId = 'aduchat-c4ee6';
  static const String apiKey = '';
  static const String appId = '';
  static const String messagingSenderId = '';
  static const String storageBucket = '';

  static bool get isComplete =>
      apiKey.isNotEmpty && appId.isNotEmpty && messagingSenderId.isNotEmpty;
}
