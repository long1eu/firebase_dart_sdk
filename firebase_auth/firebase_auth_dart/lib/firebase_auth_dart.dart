// File created by
// Lung Razvan <long1eu>
// on 01/09/2020

library firebase_auth_dart;

import 'dart:async';
import 'dart:io';

import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart' as platform;
import 'package:firebase_auth_vm/firebase_auth_vm.dart' as dart;
import 'package:firebase_core/firebase_core.dart' as platform;
import 'package:firebase_core_vm/firebase_core_vm.dart' as dart;
import 'package:flutter/material.dart';
import 'package:meta/meta.dart';
import 'package:url_launcher/url_launcher.dart';

part 'src/firebase_auth_dart_confirmation_result.dart';

part 'src/firebase_auth_dart_recaptcha_verifier_factory.dart';

part 'src/firebase_auth_dart_user.dart';

part 'src/firebase_auth_dart_user_credential.dart';

part 'src/utils.dart';

/// The web delegate implementation for [FirebaseAuth].
class FirebaseAuthDart extends platform.FirebaseAuthPlatform {
  /// The entry point for the [FirebaseAuthDart] class.
  FirebaseAuthDart._({@required platform.FirebaseApp app, dart.UrlPresenter presenter})
      : assert(app != null),
        _auth = dart.FirebaseAuth.getInstance(dart.FirebaseApp.getInstance(app?.name)),
        _presenter = presenter,
        _userChangesListeners = StreamController<platform.UserPlatform>.broadcast(),
        _authStateChangesListeners = StreamController<platform.UserPlatform>.broadcast(),
        _idTokenChangesListeners = StreamController<platform.UserPlatform>.broadcast(),
        super(appInstance: app);

  /// Instance of Auth from the dart plugin
  final dart.FirebaseAuth _auth;
  bool _appVerificationDisabledForTesting = false;

  static Future<void> register({String appName = dart.FirebaseApp.defaultAppName, dart.UrlPresenter presenter}) async {
    if (_instances.containsKey(appName)) {
      final FirebaseAuthDart instance = _instances[appName];
      platform.FirebaseAuthPlatform.instance = instance;
      platform.RecaptchaVerifierFactoryPlatform.instance = RecaptchaVerifierFactoryDart._(instance._auth, presenter);
      return;
    }

    presenter ??= (Uri uri) => launch('$uri');
    final platform.FirebaseApp platformApp = platform.Firebase.app(appName);
    final FirebaseAuthDart instance = FirebaseAuthDart._(app: platformApp, presenter: presenter);
    _instances[appName] = instance;

    instance //
        ._auth
        .onAuthStateChanged
        .map((dart.FirebaseUser user) => user == null ? null : UserDart._(instance, user))
        .listen((UserDart event) {
      instance._authStateChangesListeners.add(event);
      instance._idTokenChangesListeners.add(event);
      instance._userChangesListeners.add(event);
    });

    platform.FirebaseAuthPlatform.instance = instance;
    platform.RecaptchaVerifierFactoryPlatform.instance = RecaptchaVerifierFactoryDart._(instance._auth, presenter);
  }

  dart.UrlPresenter _presenter;

  /// Used by the phone verification flow to allow opening of a browser window
  /// in a platform specific way, that presents a reCaptcha challenge.
  ///
  /// You can open the link in a in-app WebView or you can open it in the system
  /// browser
  dart.UrlPresenter get presenter => _presenter;

  set presenter(dart.UrlPresenter value) {
    assert(value != null);
    _presenter = value;
  }

  static final Map<String, FirebaseAuthDart> _instances = <String, FirebaseAuthDart>{};

  final StreamController<platform.UserPlatform> _authStateChangesListeners;
  final StreamController<platform.UserPlatform> _idTokenChangesListeners;
  final StreamController<platform.UserPlatform> _userChangesListeners;

  @override
  platform.FirebaseAuthPlatform delegateFor({platform.FirebaseApp app}) {
    return FirebaseAuthDart._(app: app, presenter: (Uri uri) => launch('$uri'));
  }

  @override
  FirebaseAuthDart setInitialValues({Map<String, dynamic> currentUser, String languageCode}) {
    // Values are already set on dart
    return this;
  }

  @override
  platform.UserPlatform get currentUser {
    final dart.FirebaseUser dartCurrentUser = _auth.currentUser;

    if (dartCurrentUser == null) {
      return null;
    }

    return UserDart._(this, _auth.currentUser);
  }

  @override
  void sendAuthChangesEvent(String appName, platform.UserPlatform userPlatform) {
    assert(appName != null);
    _userChangesListeners.add(null);
  }

  @override
  Future<void> applyActionCode(String code) {
    try {
      return _auth.applyActionCode(code);
    } catch (e) {
      throw convertDartFirebaseAuthError(e);
    }
  }

  @override
  Future<platform.ActionCodeInfo> checkActionCode(String code) async {
    final dart.ActionCodeInfo codeInfo = await _auth.checkActionCode(code);
    return convertDartActionCodeInfo(codeInfo);
  }

  @override
  Future<platform.UserCredentialPlatform> createUserWithEmailAndPassword(String email, String password) async {
    try {
      final dart.AuthResult authResult = await _auth.createUserWithEmailAndPassword(email: email, password: password);
      return UserCredentialDart._(this, authResult);
    } catch (e) {
      throw convertDartFirebaseAuthError(e);
    }
  }

  @override
  Future<List<String>> fetchSignInMethodsForEmail(String email) {
    try {
      return _auth.fetchSignInMethodsForEmail(email);
    } catch (e) {
      throw convertDartFirebaseAuthError(e);
    }
  }

  /*
  @override
  Future<platform.UserCredentialPlatform> signInWithPopup(platform.AuthProvider provider) async {
    try {
      final dart.AuthProvider authProvider = convertPlatformAuthProvider(provider);
      return UserCredentialDart._(this, await _auth.signInWithPopup(authProvider));
    } catch (e) {
      throw convertDartFirebaseAuthError(e);
    }
  }

  @override
  Future<void> signInWithRedirect(platform.AuthProvider provider) async {
    try {
      final dart.AuthProvider authProvider = convertPlatformAuthProvider(provider);
      return _auth.signInWithRedirect(authProvider);
    } catch (e) {
      throw convertDartFirebaseAuthError(e);
    }
  }

  @override
  Future<platform.UserCredentialPlatform> getRedirectResult() async {
    try {
      final authResult = await _auth.getRedirectResult();
      return UserCredentialDart._(this, authResult);
    } catch (e) {
      throw convertDartFirebaseAuthError(e);
    }
  }
  */

  @override
  Stream<platform.UserPlatform> authStateChanges() => _authStateChangesListeners.stream;

  @override
  Stream<platform.UserPlatform> idTokenChanges() => _idTokenChangesListeners.stream;

  @override
  Stream<platform.UserPlatform> userChanges() => _userChangesListeners.stream;

  @override
  Future<void> sendPasswordResetEmail(String email, [platform.ActionCodeSettings actionCodeSettings]) {
    try {
      final dart.ActionCodeSettings codeSettings = convertPlatformActionCodeSettings(actionCodeSettings);
      return _auth.sendPasswordResetEmail(email, codeSettings);
    } catch (e) {
      throw convertDartFirebaseAuthError(e);
    }
  }

  @override
  Future<void> sendSignInLinkToEmail(String email, [platform.ActionCodeSettings actionCodeSettings]) {
    try {
      final dart.ActionCodeSettings codeSettings = convertPlatformActionCodeSettings(actionCodeSettings);
      return _auth.sendSignInWithEmailLink(email, codeSettings);
    } catch (e) {
      throw convertDartFirebaseAuthError(e);
    }
  }

  @override
  Future<void> setLanguageCode(String languageCode) async {
    _auth.languageCode = languageCode;
  }

  @override
  Future<void> setSettings({
    bool appVerificationDisabledForTesting,
    String userAccessGroup,
  }) async {
    if (userAccessGroup != null && !dart.kIsWeb && (Platform.isIOS || Platform.isMacOS)) {
      Log.i('FirebaseAuthDart',
          'userAccessGroup can be implemented by providing a custom implementation for the LocalStorage in the PlatformDependencies object used by this FirebaseApp.');
    }

    _appVerificationDisabledForTesting = appVerificationDisabledForTesting ?? false;
  }

  @override
  Future<platform.UserCredentialPlatform> signInAnonymously() async {
    try {
      final dart.AuthResult authResult = await _auth.signInAnonymously();
      return UserCredentialDart._(this, authResult);
    } catch (e) {
      throw convertDartFirebaseAuthError(e);
    }
  }

  @override
  Future<platform.UserCredentialPlatform> signInWithCredential(platform.AuthCredential credential) async {
    try {
      final dart.AuthCredential dartCredential = convertPlatformCredential(credential);
      final dart.AuthResult authResult = await _auth.signInWithCredential(dartCredential);
      return UserCredentialDart._(this, authResult);
    } catch (e) {
      throw convertDartFirebaseAuthError(e);
    }
  }

  @override
  Future<platform.UserCredentialPlatform> signInWithCustomToken(String token) async {
    try {
      final dart.AuthResult authResult = await _auth.signInWithCustomToken(token);
      return UserCredentialDart._(this, authResult);
    } catch (e) {
      throw convertDartFirebaseAuthError(e);
    }
  }

  @override
  Future<platform.UserCredentialPlatform> signInWithEmailAndPassword(String email, String password) async {
    try {
      final dart.AuthResult authResult = await _auth.signInWithEmailAndPassword(email: email, password: password);
      return UserCredentialDart._(this, authResult);
    } catch (e) {
      throw convertDartFirebaseAuthError(e);
    }
  }

  @override
  Future<platform.UserCredentialPlatform> signInWithEmailLink(String email, String emailLink) async {
    try {
      final dart.AuthResult authResult = await _auth.signInWithEmailAndLink(email: email, link: emailLink);
      return UserCredentialDart._(this, authResult);
    } catch (e) {
      throw convertDartFirebaseAuthError(e);
    }
  }

  @override
  Future<platform.ConfirmationResultPlatform> signInWithPhoneNumber(
    String phoneNumber,
    platform.RecaptchaVerifierFactoryPlatform applicationVerifier,
  ) async {
    final platform.RecaptchaVerifierFactoryPlatform delegate = applicationVerifier.delegateFor(
      parameters: <String, Object>{
        'appName': _auth.app.name,
        'presenter': presenter,
      },
    );

    final String verificationId = await _auth.verifyPhoneNumber(
      phoneNumber,
      isTest: _appVerificationDisabledForTesting,
      provider: delegate.verify,
    );
    return ConfirmationResultDart._(this, _auth, verificationId);
  }

  @override
  Future<void> signOut() {
    try {
      return _auth.signOut();
    } catch (e) {
      throw convertDartFirebaseAuthError(e);
    }
  }

  @override
  Future<String> verifyPasswordResetCode(String code) {
    try {
      return _auth.verifyPasswordReset(code);
    } catch (e) {
      throw convertDartFirebaseAuthError(e);
    }
  }

  @override
  Future<void> verifyPhoneNumber({
    @required String phoneNumber,
    @required platform.PhoneVerificationCompleted verificationCompleted,
    @required platform.PhoneVerificationFailed verificationFailed,
    @required platform.PhoneCodeSent codeSent,
    @required platform.PhoneCodeAutoRetrievalTimeout codeAutoRetrievalTimeout,
    String autoRetrievedSmsCodeForTesting,
    Duration timeout = const Duration(seconds: 30),
    int forceResendingToken,
  }) async {
    try {
      final String verificationId =
          await _auth.verifyPhoneNumber(phoneNumber, isTest: _appVerificationDisabledForTesting, presenter: presenter);
      codeSent(verificationId, null);
    } catch (e) {
      throw convertDartFirebaseAuthError(e);
    }
  }
}
