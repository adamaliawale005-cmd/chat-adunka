import 'package:firebase_auth/firebase_auth.dart';

/// Sign-in with phone number + SMS code, or email + password (testing).
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  FirebaseAuth get _auth => FirebaseAuth.instance;

  User? get currentUser => _auth.currentUser;
  Stream<User?> authStateChanges() => _auth.authStateChanges();

  // ---------- phone ----------

  /// Starts phone verification. Normally exactly one of [onCodeSent],
  /// [onAutoVerified] or [onError] is called.
  Future<void> sendCode({
    required String phoneNumber,
    int? resendToken,
    required void Function(String verificationId, int? resendToken) onCodeSent,
    required void Function() onAutoVerified,
    required void Function(String code) onError,
  }) {
    return _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      forceResendingToken: resendToken,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (PhoneAuthCredential credential) async {
        // Android can read the SMS automatically and finish without typing.
        try {
          await _auth.signInWithCredential(credential);
          onAutoVerified();
        } on FirebaseAuthException catch (e) {
          onError(e.code);
        }
      },
      verificationFailed: (FirebaseAuthException e) => onError(e.code),
      codeSent: onCodeSent,
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  Future<void> verifyCode(
      {required String verificationId, required String smsCode}) async {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    await _auth.signInWithCredential(credential);
  }

  // ---------- email ----------

  Future<void> registerWithEmail(String email, String password) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    try {
      await cred.user?.sendEmailVerification();
    } catch (_) {
      // Verification email is optional for testing.
    }
  }

  Future<void> signInWithEmail(String email, String password) =>
      _auth.signInWithEmailAndPassword(email: email.trim(), password: password);

  /// Account recovery for email accounts.
  Future<void> sendPasswordReset(String email) =>
      _auth.sendPasswordResetEmail(email: email.trim());

  Future<void> resendEmailVerification() async {
    await _auth.currentUser?.sendEmailVerification();
  }

  // ---------- session ----------

  Future<void> signOut() => _auth.signOut();

  /// Firebase only allows account deletion shortly after signing in.
  bool get signedInRecently {
    final last = _auth.currentUser?.metadata.lastSignInTime;
    if (last == null) return false;
    return DateTime.now().difference(last).inMinutes < 5;
  }

  Future<void> deleteCurrentUser() async {
    await _auth.currentUser?.delete();
  }

  /// Translation key for a Firebase Auth error code.
  static String errorKey(String code) {
    switch (code) {
      case 'invalid-phone-number':
        return 'err_invalid_phone';
      case 'invalid-verification-code':
        return 'err_invalid_code';
      case 'session-expired':
        return 'err_code_expired';
      case 'too-many-requests':
        return 'err_too_many_requests';
      case 'quota-exceeded':
        return 'err_sms_quota';
      case 'app-not-authorized':
      case 'missing-client-identifier':
      case 'invalid-app-credential':
        return 'err_app_not_authorized';
      case 'billing-not-enabled':
        return 'err_billing_required';
      case 'network-request-failed':
        return 'err_network';
      case 'operation-not-allowed':
        return 'err_sign_in_method_disabled';
      case 'email-already-in-use':
        return 'err_email_in_use';
      case 'invalid-email':
        return 'err_invalid_email';
      case 'weak-password':
        return 'err_weak_password';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
      case 'INVALID_LOGIN_CREDENTIALS':
        return 'err_wrong_credentials';
      case 'user-disabled':
        return 'err_user_disabled';
      case 'requires-recent-login':
        return 'err_recent_login';
      default:
        return 'err_generic';
    }
  }
}
