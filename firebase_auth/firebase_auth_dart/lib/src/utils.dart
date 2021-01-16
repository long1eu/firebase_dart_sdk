// Copyright 2020, the Chromium project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of firebase_auth_dart;

/// Given a Dart error, a [FirebaseAuthException] is returned.
platform.FirebaseAuthException convertDartFirebaseAuthError(Object exception) {
  if (exception is dart.FirebaseAuthError) {
    if (exception is dart.FirebaseAuthCredentialAlreadyInUseError) {
      return platform.FirebaseAuthException(
        code: exception.codeName,
        message: exception.message,
        email: exception.email,
        credential: convertDartCredential(exception.credential),
      );
    } else {
      return platform.FirebaseAuthException(code: exception.codeName, message: exception.message);
    }
  } else {
    return platform.FirebaseAuthException(code: 'unknown', message: 'An unknown error occurred.');
  }
}

/// Converts a [dart.ActionCodeInfo] into a [ActionCodeInfo].
platform.ActionCodeInfo convertDartActionCodeInfo(dart.ActionCodeInfo info) {
  if (info == null) {
    return null;
  }

  return platform.ActionCodeInfo(
    operation: covertDartActionCodeOperation(info.operation),
    data: <String, dynamic>{
      'email': info.email,
      'previousEmail': info.forEmail,
    },
  );
}

/// Converts a [dart.AdditionalUserInfo] into a [AdditionalUserInfo].
platform.AdditionalUserInfo convertDartAdditionalUserInfo(dart.AdditionalUserInfo userInfo) {
  if (userInfo == null) {
    return null;
  }

  return platform.AdditionalUserInfo(
    isNewUser: userInfo.isNewUser,
    profile: userInfo.profile,
    providerId: userInfo.providerId,
    username: userInfo.username,
  );
}

/// Converts a [dart.GetTokenResult] into a [IdTokenResult].
platform.IdTokenResult convertDartIdTokenResult(dart.GetTokenResult result) {
  return platform.IdTokenResult(<String, dynamic>{
    'claims': result.claims,
    'expirationTimestamp': result.expirationTimestamp.millisecondsSinceEpoch,
    'issuedAtTimestamp': result.issuedAtTimestamp.millisecondsSinceEpoch,
    'signInProvider': result.signInProvider,
    'signInSecondFactor': null,
    'token': result.token,
  });
}

/// Converts a [ActionCodeSettings] into a [dart.ActionCodeSettings].
dart.ActionCodeSettings convertPlatformActionCodeSettings(platform.ActionCodeSettings settings) {
  if (settings == null) {
    return null;
  }

  return dart.ActionCodeSettings(
    continueUrl: settings.url,
    handleCodeInApp: settings.handleCodeInApp,
    dynamicLinkDomain: settings.dynamicLinkDomain,
    androidPackageName: settings.android != null ? settings.android['packageName'] : null,
    androidMinimumVersion: settings.android != null ? settings.android['minimumVersion'] : null,
    androidInstallIfNotAvailable: settings.android != null ? settings.android['installApp'] : null,
    iOSBundleId: settings.iOS != null ? settings.iOS['bundleId'] : null,
  );
}

/// Converts a [Persistence] enum into a web string persistence value.
String convertPlatformPersistence(platform.Persistence persistence) {
  switch (persistence) {
    case platform.Persistence.SESSION:
      return 'session';
    case platform.Persistence.NONE:
      return 'none';
    case platform.Persistence.LOCAL:
    default:
      return 'local';
  }
}

/// Converts a [AuthProvider] into a [dart.AuthProvider].
dart.AuthProvider convertPlatformAuthProvider(platform.AuthProvider authProvider) {
  if (authProvider is platform.EmailAuthProvider) {
    return const dart.EmailAuthProvider();
  } else if (authProvider is platform.FacebookAuthProvider) {
    return dart.FacebookAuthProvider(
      scopes: <String>[
        if (authProvider.scopes != null) ...authProvider.scopes,
      ],
      parameters: <dynamic, dynamic>{
        if (authProvider.parameters != null) ...authProvider.parameters,
      },
    );
  } else if (authProvider is platform.GithubAuthProvider) {
    return dart.GithubAuthProvider(
      scopes: <String>[
        if (authProvider.scopes != null) ...authProvider.scopes,
      ],
      parameters: <dynamic, dynamic>{
        if (authProvider.parameters != null) ...authProvider.parameters,
      },
    );
  } else if (authProvider is platform.GoogleAuthProvider) {
    return dart.GoogleAuthProvider(
      scopes: <String>[
        if (authProvider.scopes != null) ...authProvider.scopes,
      ],
      parameters: <dynamic, dynamic>{
        if (authProvider.parameters != null) ...authProvider.parameters,
      },
    );
  } else if (authProvider is platform.OAuthProvider) {
    return dart.OAuthProvider(
      authProvider.providerId,
      scopes: <String>[
        if (authProvider.scopes != null) ...authProvider.scopes,
      ],
      parameters: <dynamic, dynamic>{
        if (authProvider.parameters != null) ...authProvider.parameters,
      },
    );
  } else if (authProvider is platform.PhoneAuthProvider) {
    return const dart.PhoneAuthProvider();
  } else if (authProvider is platform.TwitterAuthProvider) {
    return dart.TwitterAuthProvider(
      parameters: <dynamic, dynamic>{
        if (authProvider.parameters != null) ...authProvider.parameters,
      },
    );
  } else {
    throw FallThroughError();
  }
}

/// Converts a [dart.OAuthCredential] into a [AuthCredential].
platform.AuthCredential convertDartOAuthCredential(dart.OAuthCredential dartCredentials) {
  if (dartCredentials == null) {
    return null;
  }

  final platform.OAuthProvider credential = platform.OAuthProvider(dartCredentials.providerId);

  if (dartCredentials.scopes != null) {
    dartCredentials.scopes.forEach(credential.addScope);
  }

  if (dartCredentials.customParameters != null) {
    credential.setCustomParameters(dartCredentials.customParameters);
  }

  return credential.credential(
    accessToken: dartCredentials.accessToken,
    idToken: dartCredentials.idToken,
    rawNonce: dartCredentials.nonce,
  );
}

/// Converts a [AuthCredential] into a [dart.OAuthCredential].
dart.AuthCredential convertPlatformCredential(platform.AuthCredential credential) {
  if (credential is platform.EmailAuthCredential) {
    if (credential.emailLink != null) {
      if (dart.kIsWeb) {
        throw UnimplementedError('EmailAuthProvider.credentialWithLink() is not supported on web');
      }
      return dart.EmailAuthProvider.credentialWithLink(email: credential.email, link: credential.password);
    }
    return dart.EmailAuthProvider.credential(email: credential.email, password: credential.password);
  } else if (credential is platform.FacebookAuthCredential) {
    return dart.FacebookAuthProvider.credential(credential.accessToken);
  } else if (credential is platform.GithubAuthCredential) {
    return dart.GithubAuthProvider.credential(credential.accessToken);
  } else if (credential is platform.GoogleAuthCredential) {
    return dart.GoogleAuthProvider.credential(idToken: credential.idToken, accessToken: credential.accessToken);
  } else if (credential is platform.OAuthCredential) {
    return dart.OAuthProvider.credentialWithAccessToken(
      providerId: credential.providerId,
      accessToken: credential.accessToken,
      idToken: credential.idToken,
    );
  } else if (credential is platform.PhoneAuthCredential) {
    return dart.PhoneAuthProvider.credential(
        verificationId: credential.verificationId, verificationCode: credential.smsCode);
  } else if (credential is platform.TwitterAuthCredential) {
    return dart.TwitterAuthProvider.credential(authToken: credential.accessToken, authTokenSecret: credential.secret);
  } else {
    throw FallThroughError();
  }
}

platform.AuthCredential convertDartCredential(dart.AuthCredential credential) {
  if (credential is dart.EmailPasswordAuthCredential) {
    return platform.EmailAuthProvider.credential(email: credential.email, password: credential.password);
  } else if (credential is dart.FacebookAuthCredential) {
    return platform.FacebookAuthProvider.credential(credential.accessToken);
  } else if (credential is dart.GameCenterAuthCredential) {
    throw UnimplementedError(
        'GameCenterAuth is not supported on by the firebase_auth plugin. You can use the firebase_auth_vm for it.');
  } else if (credential is dart.GithubAuthCredential) {
    return platform.GithubAuthProvider.credential(credential.token);
  } else if (credential is dart.GoogleAuthCredential) {
    return platform.GoogleAuthProvider.credential(idToken: credential.idToken, accessToken: credential.accessToken);
  } else if (credential is dart.OAuthCredential) {
    return platform.OAuthCredential(
      providerId: credential.providerId,
      signInMethod: credential.signInMethod,
      accessToken: credential.accessToken,
      idToken: credential.idToken,
      secret: credential.secret,
      rawNonce: credential.nonce,
    );
  } else if (credential is dart.PhoneAuthCredential) {
    return platform.PhoneAuthProvider.credential(
        verificationId: credential.verificationId, smsCode: credential.verificationCode);
  } else if (credential is dart.TwitterAuthCredential) {
    return platform.TwitterAuthProvider.credential(
        accessToken: credential.authToken, secret: credential.authTokenSecret);
  } else {
    throw FallThroughError();
  }
}

int covertDartActionCodeOperation(dart.ActionCodeOperation operation) {
  switch (operation) {
    case dart.ActionCodeOperation.passwordReset:
      return 1;
    case dart.ActionCodeOperation.verifyEmail:
      return 2;
    case dart.ActionCodeOperation.recoverEmail:
      return 3;
    case dart.ActionCodeOperation.emailSignIn:
      return 4;
    case dart.ActionCodeOperation.verifyAndChangeEmail:
      return 5;
    case dart.ActionCodeOperation.revertSecondFactorAddition:
      return 6;
    default:
      throw FallThroughError();
  }
}
