import 'package:firebase_auth/firebase_auth.dart';

/// Phone-number sign-in with SMS one-time codes (Firebase Authentication).
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  FirebaseAuth get _auth => FirebaseAuth.instance;

  User? get currentUser => _auth.currentUser;
  Stream<User?> authStateChanges() => _auth.authStateChanges();

  /// Starts verification. Exactly one of [onCodeSent], [onAutoVerified] or
  /// [onError] is normally called.
  Future<void> sendCode({
    required String phoneNumber,
    int? resendToken,
    required void Function(String verificationId, int? resendToken) onCodeSent,
    required void Function() onAutoVerified,
    required void Function(String message) onError,
  }) {
    return _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      forceResendingToken: resendToken,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (PhoneAuthCredential credential) async {
        // Android can read the SMS automatically and verify without typing.
        try {
          await _auth.signInWithCredential(credential);
          onAutoVerified();
        } on FirebaseAuthException catch (e) {
          onError(describeError(e));
        }
      },
      verificationFailed: (FirebaseAuthException e) => onError(describeError(e)),
      codeSent: onCodeSent,
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  Future<void> verifyCode({
    required String verificationId,
    required String smsCode,
  }) async {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    await _auth.signInWithCredential(credential);
  }

  Future<void> signOut() => _auth.signOut();

  static String describeError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-phone-number':
        return 'That phone number is not valid. Check the country code and number.';
      case 'invalid-verification-code':
        return 'The code is incorrect. Please try again.';
      case 'session-expired':
        return 'The code has expired. Request a new one.';
      case 'too-many-requests':
        return 'Too many attempts from this device. Please wait and try again later.';
      case 'quota-exceeded':
        return 'The daily SMS limit for this app has been reached. Try again tomorrow or use a Firebase test number.';
      case 'app-not-authorized':
      case 'missing-client-identifier':
        return 'This app build is not authorised for phone sign-in yet. The app\'s SHA fingerprints must be added in Firebase.';
      case 'network-request-failed':
        return 'No internet connection. Check your network and try again.';
      case 'operation-not-allowed':
        return 'Phone sign-in is not enabled in Firebase Authentication.';
      default:
        return e.message ?? 'Sign-in failed (${e.code}).';
    }
  }
}
