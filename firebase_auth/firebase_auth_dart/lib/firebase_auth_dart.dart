// File created by
// Lung Razvan <long1eu>
// on 04/03/2020

library firebase_auth_dart;

import 'dart:async';

import 'package:built_value/json_object.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart'
    as platform;
import 'package:firebase_auth_vm/firebase_auth_vm.dart' as dart;
import 'package:firebase_core_vm/firebase_core_vm.dart' as dart;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:meta/meta.dart';
import 'package:url_launcher/url_launcher.dart';

export 'package:firebase_auth_vm/firebase_auth_vm.dart' show UrlPresenter;

class FirebaseAuthDart extends platform.FirebaseAuthPlatform {
  FirebaseAuthDart._({@required dart.UrlPresenter presenter})
      : assert(presenter != null),
        _presenter = presenter;

  /// Registers this implementation as default implementation for FirebaseAuth
  ///
  /// see [GoogleSignInPlatform.presenter]
  static Future<void> register({dart.UrlPresenter presenter}) async {
    presenter ??= (Uri uri) => launch(uri.toString());

    platform.FirebaseAuthPlatform.instance =
        FirebaseAuthDart._(presenter: presenter);
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

  dart.FirebaseAuth _getAuth(String name) {
    name = _normalizeName(name);
    final dart.FirebaseApp app = dart.FirebaseApp.getInstance(name);
    return dart.FirebaseAuth.getInstance(app);
  }

  String _normalizeName(String name) {
    if (name == '__FIRAPP_DEFAULT' || name == '[DEFAULT]') {
      return dart.FirebaseApp.defaultAppName;
    } else {
      return name;
    }
  }

  platform.PlatformAdditionalUserInfo _fromJsAdditionalUserInfo(
      dart.AdditionalUserInfo additionalUserInfo) {
    return platform.PlatformAdditionalUserInfo(
      isNewUser: additionalUserInfo.isNewUser,
      providerId: additionalUserInfo.providerId,
      username: additionalUserInfo.username,
      profile: additionalUserInfo.profile?.asMap()?.map<String, dynamic>(
          (String key, JsonObject value) =>
              MapEntry<String, dynamic>(key, value.value)),
    );
  }

  platform.PlatformUserInfo _fromDartUserInfo(dart.UserInfo userInfo) {
    return platform.PlatformUserInfo(
      providerId: userInfo.providerId,
      uid: userInfo.providerId,
      displayName: userInfo.displayName,
      photoUrl: userInfo.photoUrl,
      email: userInfo.email,
      phoneNumber: userInfo.phoneNumber,
    );
  }

  platform.PlatformUser _fromDartUser(dart.FirebaseUser user) {
    if (user == null) {
      return null;
    }
    return platform.PlatformUser(
      providerId: user.providerId,
      uid: user.uid,
      displayName: user.displayName,
      photoUrl: user.photoUrl,
      email: user.email,
      phoneNumber: user.phoneNumber,
      creationTimestamp: user.metadata.creationDate.millisecondsSinceEpoch,
      lastSignInTimestamp: user.metadata.lastSignInDate.millisecondsSinceEpoch,
      isAnonymous: user.isAnonymous,
      isEmailVerified: user.isEmailVerified,
      providerData: user.providerData
          .map<platform.PlatformUserInfo>(_fromDartUserInfo)
          .toList(),
    );
  }

  platform.PlatformAuthResult _fromDartAuthResult(dart.AuthResult result) {
    return platform.PlatformAuthResult(
      user: _fromDartUser(result.user),
      additionalUserInfo: _fromJsAdditionalUserInfo(
        result.additionalUserInfo,
      ),
    );
  }

  platform.PlatformIdTokenResult _fromDartIdTokenResult(
      dart.GetTokenResult idTokenResult) {
    return platform.PlatformIdTokenResult(
      token: idTokenResult.token,
      expirationTimestamp:
          idTokenResult.expirationTimestamp.millisecondsSinceEpoch,
      authTimestamp: idTokenResult.authTimestamp.millisecondsSinceEpoch,
      issuedAtTimestamp: idTokenResult.issuedAtTimestamp.millisecondsSinceEpoch,
      claims: idTokenResult.claims,
      signInProvider: idTokenResult.signInProvider,
    );
  }

  dart.FirebaseUser _getCurrentUserOrThrow(dart.FirebaseAuth auth) {
    final dart.FirebaseUser user = auth.currentUser;
    if (user == null) {
      throw PlatformException(
        code: 'USER_REQUIRED',
        message: 'Please authenticate with Firebase first',
      );
    }
    return user;
  }

  dart.AuthCredential _getCredential(platform.AuthCredential credential) {
    if (credential is platform.EmailAuthCredential) {
      return dart.EmailAuthProvider.getCredential(
        email: credential.email,
        password: credential.password,
      );
    }
    if (credential is platform.GoogleAuthCredential) {
      return dart.GoogleAuthProvider.getCredential(
        idToken: credential.idToken,
        accessToken: credential.accessToken,
      );
    }
    if (credential is platform.FacebookAuthCredential) {
      return dart.FacebookAuthProvider.getCredential(credential.accessToken);
    }
    if (credential is platform.TwitterAuthCredential) {
      return dart.TwitterAuthProvider.getCredential(
        authToken: credential.authToken,
        authTokenSecret: credential.authTokenSecret,
      );
    }
    if (credential is platform.GithubAuthCredential) {
      return dart.GithubAuthProvider.getCredential(credential.token);
    }
    if (credential is platform.PhoneAuthCredential) {
      return dart.PhoneAuthProvider.getCredential(
        verificationId: credential.verificationId,
        verificationCode: credential.smsCode,
      );
    }
    return null;
  }

  @override
  Future<platform.PlatformUser> getCurrentUser(String app) {
    final dart.FirebaseAuth auth = _getAuth(app);
    final dart.FirebaseUser currentUser = auth.currentUser;
    return Future<platform.PlatformUser>.value(_fromDartUser(currentUser));
  }

  @override
  Future<platform.PlatformAuthResult> signInAnonymously(String app) async {
    final dart.FirebaseAuth auth = _getAuth(app);
    final dart.AuthResult result = await auth.signInAnonymously();
    return _fromDartAuthResult(result);
  }

  @override
  Future<platform.PlatformAuthResult> createUserWithEmailAndPassword(
    String app,
    String email,
    String password,
  ) async {
    final dart.FirebaseAuth auth = _getAuth(app);
    final dart.AuthResult result = await auth.createUserWithEmailAndPassword(
        email: email, password: password);
    return _fromDartAuthResult(result);
  }

  @override
  Future<List<String>> fetchSignInMethodsForEmail(String app, String email) {
    final dart.FirebaseAuth auth = _getAuth(app);
    return auth.fetchSignInMethodsForEmail(email: email);
  }

  @override
  // TODO(long1eu): expose ActionCodeSettings
  Future<void> sendPasswordResetEmail(String app, String email,
      [dart.ActionCodeSettings settings]) {
    final dart.FirebaseAuth auth = _getAuth(app);
    return auth.sendPasswordResetEmail(email: email, settings: settings);
  }

  @override
  Future<void> sendLinkToEmail(
    String app, {
    @required String email,
    @required String url,
    @required bool handleCodeInApp,
    @required String iOSBundleID,
    @required String androidPackageName,
    @required bool androidInstallIfNotAvailable,
    @required String androidMinimumVersion,
  }) {
    final dart.FirebaseAuth auth = _getAuth(app);
    final dart.ActionCodeSettings actionCodeSettings = dart.ActionCodeSettings(
      continueUrl: url,
      handleCodeInApp: handleCodeInApp,
      iOSBundleId: iOSBundleID,
      androidPackageName: androidPackageName,
      androidInstallIfNotAvailable: androidInstallIfNotAvailable,
      androidMinimumVersion: androidMinimumVersion,
    );
    return auth.sendSignInWithEmailLink(
        email: email, settings: actionCodeSettings);
  }

  @override
  Future<bool> isSignInWithEmailLink(String app, String link) {
    final dart.FirebaseAuth auth = _getAuth(app);
    return Future<bool>.value(auth.isSignInWithEmailLink(link));
  }

  @override
  Future<platform.PlatformAuthResult> signInWithEmailAndLink(
    String app,
    String email,
    String link,
  ) async {
    final dart.FirebaseAuth auth = _getAuth(app);
    final dart.AuthResult result =
        await auth.signInWithEmailAndLink(email: email, link: link);
    return _fromDartAuthResult(result);
  }

  @override
  Future<void> sendEmailVerification(String app) {
    final dart.FirebaseAuth auth = _getAuth(app);
    final dart.FirebaseUser currentUser = _getCurrentUserOrThrow(auth);
    return currentUser.sendEmailVerification();
  }

  @override
  Future<void> reload(String app) {
    final dart.FirebaseAuth auth = _getAuth(app);
    final dart.FirebaseUser currentUser = _getCurrentUserOrThrow(auth);
    return currentUser.reload();
  }

  @override
  Future<void> delete(String app) {
    final dart.FirebaseAuth auth = _getAuth(app);
    final dart.FirebaseUser user = _getCurrentUserOrThrow(auth);
    return user.delete();
  }

  @override
  Future<platform.PlatformAuthResult> signInWithCredential(
    String app,
    platform.AuthCredential credential,
  ) async {
    final dart.FirebaseAuth auth = _getAuth(app);
    final dart.AuthCredential firebaseCredential = _getCredential(credential);
    final dart.AuthResult result =
        await auth.signInWithCredential(firebaseCredential);
    return _fromDartAuthResult(result);
  }

  @override
  Future<platform.PlatformAuthResult> signInWithCustomToken(
      String app, String token) async {
    final dart.FirebaseAuth auth = _getAuth(app);
    final dart.AuthResult result =
        await auth.signInWithCustomToken(token: token);
    return _fromDartAuthResult(result);
  }

  @override
  Future<void> signOut(String app) {
    final dart.FirebaseAuth auth = _getAuth(app);
    return auth.signOut();
  }

  @override
  Future<platform.PlatformIdTokenResult> getIdToken(
      String app, bool refresh) async {
    final dart.FirebaseAuth auth = _getAuth(app);
    final dart.FirebaseUser currentUser = auth.currentUser;
    final dart.GetTokenResult idTokenResult =
        await currentUser.getIdToken(forceRefresh: refresh);
    return _fromDartIdTokenResult(idTokenResult);
  }

  @override
  Future<platform.PlatformAuthResult> reauthenticateWithCredential(
    String app,
    platform.AuthCredential credential,
  ) async {
    final dart.FirebaseAuth auth = _getAuth(app);
    final dart.FirebaseUser currentUser = _getCurrentUserOrThrow(auth);
    final dart.AuthCredential firebaseCredential = _getCredential(credential);
    final dart.AuthResult result =
        await currentUser.reauthenticateWithCredential(firebaseCredential);
    return _fromDartAuthResult(result);
  }

  @override
  Future<platform.PlatformAuthResult> linkWithCredential(
    String app,
    platform.AuthCredential credential,
  ) async {
    final dart.FirebaseAuth auth = _getAuth(app);
    final dart.FirebaseUser currentUser = _getCurrentUserOrThrow(auth);
    final dart.AuthCredential firebaseCredential = _getCredential(credential);
    final dart.AuthResult result =
        await currentUser.linkWithCredential(firebaseCredential);
    return _fromDartAuthResult(result);
  }

  @override
  Future<void> unlinkFromProvider(String app, String provider) {
    final dart.FirebaseAuth auth = _getAuth(app);
    final dart.FirebaseUser currentUser = _getCurrentUserOrThrow(auth);
    return currentUser.unlinkFromProvider(provider);
  }

  @override
  Future<void> updateEmail(String app, String email) {
    final dart.FirebaseAuth auth = _getAuth(app);
    final dart.FirebaseUser currentUser = _getCurrentUserOrThrow(auth);
    return currentUser.updateEmail(email);
  }

  @override
  Future<void> updatePhoneNumberCredential(
    String app,
    platform.PhoneAuthCredential phoneAuthCredential,
  ) {
    final dart.FirebaseAuth auth = _getAuth(app);
    final dart.FirebaseUser currentUser = _getCurrentUserOrThrow(auth);
    final dart.AuthCredential credential = _getCredential(phoneAuthCredential);
    return currentUser.updatePhoneNumberCredential(credential);
  }

  @override
  Future<void> updatePassword(String app, String password) {
    final dart.FirebaseAuth auth = _getAuth(app);
    final dart.FirebaseUser currentUser = _getCurrentUserOrThrow(auth);
    return currentUser.updatePassword(password);
  }

  // TODO(long1eu): This doesn't seem to allow removing of the name with a null value
  @override
  Future<void> updateProfile(
    String app, {
    String displayName,
    String photoUrl,
  }) {
    final dart.FirebaseAuth auth = _getAuth(app);
    final dart.FirebaseUser currentUser = _getCurrentUserOrThrow(auth);
    final dart.UserUpdateInfo profile = dart.UserUpdateInfo();
    if (displayName != null) {
      profile.displayName = displayName;
    }
    if (photoUrl != null) {
      profile.photoUrl = photoUrl;
    }
    return currentUser.updateProfile(profile);
  }

  @override
  Future<void> setLanguageCode(String app, String language) async {
    _getAuth(app).languageCode = language;
  }

  @override
  Stream<platform.PlatformUser> onAuthStateChanged(String app) {
    final dart.FirebaseAuth auth = _getAuth(app);
    return auth.onAuthStateChanged.map<platform.PlatformUser>(_fromDartUser);
  }

  @override
  Future<void> verifyPhoneNumber(
    String app, {
    @required String phoneNumber,
    @required Duration timeout,
    int forceResendingToken,
    @required platform.PhoneVerificationCompleted verificationCompleted,
    @required platform.PhoneVerificationFailed verificationFailed,
    @required platform.PhoneCodeSent codeSent,
    @required platform.PhoneCodeAutoRetrievalTimeout codeAutoRetrievalTimeout,
  }) async {
    final dart.FirebaseAuth auth = _getAuth(app);
    try {
      final String verificationId = await auth.verifyPhoneNumber(
          phoneNumber: phoneNumber, presenter: presenter);

      codeSent(verificationId);
    } on dart.FirebaseAuthError catch (e) {
      String code = 'verifyPhoneNumberError';
      switch (e.code) {
        case 17056:
          code = 'captchaCheckFailed';
          break;
        case 17052:
          code = 'quotaExceeded';
          break;
        case 17042:
          code = 'invalidPhoneNumber';
          break;
        case 17041:
          code = 'missingPhoneNumber';
          break;
      }

      verificationFailed(platform.AuthException(code, e.message));
    }
  }

  @override
  Future<void> confirmPasswordReset(
    String app,
    String oobCode,
    String newPassword,
  ) {
    final dart.FirebaseAuth auth = _getAuth(app);
    return auth.confirmPasswordReset(
        oobCode: oobCode, newPassword: newPassword);
  }
}
