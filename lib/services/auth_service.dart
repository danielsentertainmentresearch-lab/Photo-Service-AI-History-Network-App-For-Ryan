import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The signed-in person, as far as the app needs to know.
class AppUser {
  final String uid;

  /// Email, phone number or Google account shown in Settings.
  final String label;

  const AppUser({required this.uid, required this.label});
}

class AuthException implements Exception {
  final String message;

  const AuthException(this.message);

  @override
  String toString() => message;
}

/// Account sign-up and sign-in. An account is required to use the app
/// beyond the tutorial.
abstract class AuthService extends ChangeNotifier {
  AppUser? get user;

  /// False when this build has no account backend configured.
  bool get available;

  /// Review builds only: lets testers in without a real account.
  bool get isReviewBuild => false;

  Future<void> signUpWithEmail(String email, String password);
  Future<void> signInWithEmail(String email, String password);

  /// Sends a code by SMS to prove the phone number belongs to the user.
  /// Returns an id to pass to [signUpWithPhone].
  Future<String> sendPhoneCode(String phone);

  /// Creates an account for [phone] that signs in with [password].
  Future<void> signUpWithPhone({
    required String phone,
    required String verificationId,
    required String smsCode,
    required String password,
  });
  Future<void> signInWithPhone(String phone, String password);

  Future<void> signInWithGoogle();
  Future<void> sendPasswordReset(String email);
  Future<void> signInAsReviewer() =>
      Future.error(const AuthException('Not available in this build.'));
  Future<void> signOut();

  /// Permanently deletes the account (required by Google Play for apps
  /// with sign-up). Data on the phone is not affected.
  Future<void> deleteAccount();
}

/// Firebase connection settings, passed at build time:
/// `--dart-define=FIREBASE_API_KEY=… FIREBASE_APP_ID=…
/// FIREBASE_SENDER_ID=… FIREBASE_PROJECT_ID=…` (see RELEASE.md).
class FirebaseConfig {
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const senderId = String.fromEnvironment('FIREBASE_SENDER_ID');
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');

  static bool get configured =>
      apiKey.isNotEmpty &&
      appId.isNotEmpty &&
      senderId.isNotEmpty &&
      projectId.isNotEmpty;

  static FirebaseOptions get options => const FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    messagingSenderId: senderId,
    projectId: projectId,
  );
}

/// Review builds (`--dart-define=REVIEW_MODE=true`) add a "Continue as
/// reviewer" option so the app can be tried before Firebase is set up.
const reviewMode = bool.fromEnvironment('REVIEW_MODE');

/// Phone accounts sign in with phone number + password. Firebase phone
/// sign-in is SMS-only, so after the SMS check the phone number is also
/// given an email/password login under this private address.
String phoneLoginEmail(String phone) {
  final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
  return 'phone-$digits@phone.eventlens.app';
}

String _friendly(FirebaseAuthException e) => switch (e.code) {
  'invalid-email' => 'That email address doesn\'t look right.',
  'user-disabled' => 'This account has been disabled.',
  'user-not-found' ||
  'wrong-password' ||
  'invalid-credential' => 'Wrong sign-in details. Check them and try again.',
  'email-already-in-use' ||
  'credential-already-in-use' => 'An account already exists. Sign in instead.',
  'weak-password' => 'Choose a stronger password (at least 8 characters).',
  'invalid-phone-number' =>
    'Enter the phone number with country code, '
        'for example +1 555 123 4567.',
  'invalid-verification-code' => 'That code isn\'t right. Check the SMS.',
  'too-many-requests' => 'Too many attempts. Wait a while and try again.',
  'network-request-failed' => 'No internet connection.',
  _ => e.message ?? 'Sign-in failed (${e.code}).',
};

class FirebaseAuthService extends AuthService {
  final FirebaseAuth _auth;
  AppUser? _user;

  FirebaseAuthService(this._auth) {
    _user = _map(_auth.currentUser);
    _auth.authStateChanges().listen((u) {
      _user = _map(u);
      notifyListeners();
    });
  }

  static Future<FirebaseAuthService> create() async {
    await Firebase.initializeApp(options: FirebaseConfig.options);
    return FirebaseAuthService(FirebaseAuth.instance);
  }

  static AppUser? _map(User? u) {
    if (u == null) return null;
    final email = u.email ?? '';
    return AppUser(
      uid: u.uid,
      label:
          u.phoneNumber ??
          (email.endsWith('@phone.eventlens.app') ? 'Phone account' : email),
    );
  }

  @override
  AppUser? get user => _user;

  @override
  bool get available => true;

  @override
  bool get isReviewBuild => reviewMode;

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on FirebaseAuthException catch (e) {
      throw AuthException(_friendly(e));
    }
  }

  @override
  Future<void> signUpWithEmail(String email, String password) => _guard(
    () => _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    ),
  );

  @override
  Future<void> signInWithEmail(String email, String password) => _guard(
    () => _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    ),
  );

  @override
  Future<String> sendPhoneCode(String phone) async {
    final id = Completer<String>();
    await _guard(
      () => _auth.verifyPhoneNumber(
        phoneNumber: phone.trim(),
        verificationCompleted: (_) {},
        verificationFailed: (e) {
          if (!id.isCompleted) id.completeError(AuthException(_friendly(e)));
        },
        codeSent: (verificationId, _) {
          if (!id.isCompleted) id.complete(verificationId);
        },
        codeAutoRetrievalTimeout: (verificationId) {
          if (!id.isCompleted) id.complete(verificationId);
        },
      ),
    );
    return id.future;
  }

  @override
  Future<void> signUpWithPhone({
    required String phone,
    required String verificationId,
    required String smsCode,
    required String password,
  }) => _guard(() async {
    final result = await _auth.signInWithCredential(
      PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode.trim(),
      ),
    );
    await result.user!.linkWithCredential(
      EmailAuthProvider.credential(
        email: phoneLoginEmail(phone),
        password: password,
      ),
    );
  });

  @override
  Future<void> signInWithPhone(String phone, String password) => _guard(
    () => _auth.signInWithEmailAndPassword(
      email: phoneLoginEmail(phone),
      password: password,
    ),
  );

  @override
  Future<void> signInWithGoogle() =>
      _guard(() => _auth.signInWithProvider(GoogleAuthProvider()));

  @override
  Future<void> sendPasswordReset(String email) =>
      _guard(() => _auth.sendPasswordResetEmail(email: email.trim()));

  @override
  Future<void> signInAsReviewer() async {
    if (!reviewMode) return super.signInAsReviewer();
    await _guard(() => _auth.signInAnonymously());
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<void> deleteAccount() => _guard(() async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await user.delete();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        throw const AuthException(
          'For your security, sign out and sign in again, then delete the '
          'account straight away.',
        );
      }
      rethrow;
    }
  });
}

/// Used when the build has no Firebase settings. Review builds can still be
/// tried with a local reviewer account; normal builds can't sign in.
class LocalReviewAuthService extends AuthService {
  static const _key = 'review_signed_in';
  final SharedPreferences _prefs;

  LocalReviewAuthService(this._prefs);

  @override
  AppUser? get user => _prefs.getBool(_key) == true
      ? const AppUser(uid: 'reviewer', label: 'Reviewer (test build)')
      : null;

  @override
  bool get available => false;

  @override
  bool get isReviewBuild => reviewMode;

  static const _unavailable = AuthException(
    'Accounts aren\'t set up in this build yet. '
    '${reviewMode ? 'Use "Continue as reviewer" for now.' : ''}',
  );

  @override
  Future<void> signUpWithEmail(String email, String password) =>
      Future.error(_unavailable);
  @override
  Future<void> signInWithEmail(String email, String password) =>
      Future.error(_unavailable);
  @override
  Future<String> sendPhoneCode(String phone) => Future.error(_unavailable);
  @override
  Future<void> signUpWithPhone({
    required String phone,
    required String verificationId,
    required String smsCode,
    required String password,
  }) => Future.error(_unavailable);
  @override
  Future<void> signInWithPhone(String phone, String password) =>
      Future.error(_unavailable);
  @override
  Future<void> signInWithGoogle() => Future.error(_unavailable);
  @override
  Future<void> sendPasswordReset(String email) => Future.error(_unavailable);

  @override
  Future<void> signInAsReviewer() async {
    if (!reviewMode) return super.signInAsReviewer();
    await _prefs.setBool(_key, true);
    notifyListeners();
  }

  @override
  Future<void> signOut() async {
    await _prefs.remove(_key);
    notifyListeners();
  }

  @override
  Future<void> deleteAccount() => signOut();
}

/// Optional fingerprint / face unlock each time the app opens.
class BiometricLock extends ChangeNotifier {
  static const _key = 'biometric_lock';
  final SharedPreferences _prefs;
  final LocalAuthentication _auth;
  bool _unlocked = false;

  BiometricLock(this._prefs, [LocalAuthentication? auth])
    : _auth = auth ?? LocalAuthentication();

  bool get enabled => _prefs.getBool(_key) ?? false;

  /// True when the app may be shown (lock off, or unlocked this session).
  bool get unlocked => !enabled || _unlocked;

  Future<bool> get supported async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  Future<bool> unlock() async {
    try {
      _unlocked = await _auth.authenticate(
        localizedReason: 'Unlock EventLens',
        biometricOnly: false,
      );
    } catch (_) {
      _unlocked = false;
    }
    notifyListeners();
    return _unlocked;
  }

  /// Turning the lock on requires a successful check first.
  Future<bool> setEnabled(bool on) async {
    if (on && !await unlock()) return false;
    await _prefs.setBool(_key, on);
    _unlocked = true;
    notifyListeners();
    return true;
  }

  void lockAgain() {
    _unlocked = false;
    notifyListeners();
  }
}
