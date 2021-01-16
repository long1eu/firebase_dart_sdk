// Copyright 2020 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

part of firebase_auth_dart;

/// Dart delegate implementation of [platform.UserCredentialPlatform].
class UserCredentialDart extends platform.UserCredentialPlatform {
  /// Creates a new [UserCredentialDart] instance.
  UserCredentialDart._(platform.FirebaseAuthPlatform auth, dart.AuthResult authResult)
      : super(
          auth: auth,
          additionalUserInfo: convertDartAdditionalUserInfo(authResult.additionalUserInfo),
          credential: convertDartOAuthCredential(authResult.credential),
          user: UserDart._(auth, authResult.user),
        );
}
