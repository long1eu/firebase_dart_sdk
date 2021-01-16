// Copyright 2020 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

part of firebase_auth_dart;

/// The dart delegate implementation for [platform.ConfirmationResultPlatform].
class ConfirmationResultDart extends platform.ConfirmationResultPlatform {
  /// Creates a new [ConfirmationResultDart] instance.
  ConfirmationResultDart._(this._auth, this._dartAuth, String verificationId) : super(verificationId);

  final platform.FirebaseAuthPlatform _auth;
  final dart.FirebaseAuth _dartAuth;

  @override
  Future<platform.UserCredentialPlatform> confirm(String verificationCode) async {
    try {
      final dart.AuthCredential credential =
      dart.PhoneAuthProvider.credential(verificationId: verificationId, verificationCode: verificationCode);
      final dart.AuthResult result = await _dartAuth.signInWithCredential(credential);

      return UserCredentialDart._(_auth, result);
    } catch (e) {
      throw convertDartFirebaseAuthError(e);
    }
  }
}
