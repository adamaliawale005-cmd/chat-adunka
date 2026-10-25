/// Build-time feature switches, injected with --dart-define values by CI
/// (from GitHub repository variables and secrets). Nothing secret is
/// hard-coded here.
class AppConfig {
  AppConfig._();

  static const String appName = 'AduChat';

  /// Cloud Storage for Firebase needs the Blaze plan. When false, photos and
  /// voice notes are stored inline in Firestore (free) and videos/documents
  /// are unavailable.
  static const bool storageEnabled = bool.fromEnvironment('STORAGE_ENABLED');

  /// Email/password sign-in (free on the Spark plan; useful for testing).
  static const bool emailAuthEnabled =
      bool.fromEnvironment('EMAIL_AUTH_ENABLED', defaultValue: true);

  /// Phone number + SMS code sign-in (real SMS needs the Blaze plan;
  /// Firebase test phone numbers do not send SMS).
  static const bool phoneAuthEnabled =
      bool.fromEnvironment('PHONE_AUTH_ENABLED', defaultValue: true);

  /// Comma separated TURN server URLs, e.g.
  /// "turn:turn.example.com:3478?transport=udp,turns:turn.example.com:5349".
  static const String _turnUrls = String.fromEnvironment('TURN_URLS');
  static const String turnUsername = String.fromEnvironment('TURN_USERNAME');
  static const String turnCredential = String.fromEnvironment('TURN_CREDENTIAL');

  static List<String> get turnUrls => _turnUrls
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  static bool get turnConfigured => turnUrls.isNotEmpty;

  /// Free public STUN servers. They help most home and mobile networks, but
  /// calls behind strict NATs or carrier-grade NAT need a TURN relay.
  static const List<String> stunUrls = [
    'stun:stun.l.google.com:19302',
    'stun:stun1.l.google.com:19302',
  ];

  /// Largest attachment stored inline in Firestore (raw bytes). Base64
  /// adds about 33%, which keeps documents under the 1 MiB Firestore limit.
  static const int inlineAttachmentLimit = 690 * 1024;

  /// Largest file uploaded to Cloud Storage.
  static const int storageAttachmentLimit = 50 * 1024 * 1024;

  /// Longest voice message.
  static const Duration maxVoiceNote = Duration(minutes: 2);

  /// How long a ringing call waits before it counts as missed.
  static const Duration ringTimeout = Duration(seconds: 45);
}
