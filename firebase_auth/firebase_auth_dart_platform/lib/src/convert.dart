// ignore_for_file: invalid_use_of_protected_member
// The value classes of the platform interface have @protected constructors,
// meant for the implementations of the interface, which this package is.

import 'dart:async';

import 'package:firebase_app_dart/firebase_app_dart.dart' as dart_app;
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart'
    as dart_auth;

import 'multi_factor.dart';

/// The exception for a member of the interface that this package does not
/// implement, with the code `unimplemented`.
FirebaseAuthException unimplemented(String member, String why) =>
    FirebaseAuthException(
      code: 'unimplemented',
      message: '$member is not available in firebase_auth_dart_platform: $why',
    );

/// Why the phone members throw.
const String noPhone =
    'phone sign-in needs reCAPTCHA or the native app verification of Android '
    'and iOS, which a pure-Dart client does not have.';

/// Why the popup and redirect members throw.
const String noBrowserFlow =
    'popup and redirect flows exist only in a browser. Get the provider token '
    'yourself and use signInWithCredential.';

/// Why signInWithProvider and its link and reauthenticate variants throw.
const String noProviderFlow =
    'there is no OAuth flow for desktop yet. Get the provider token yourself '
    'and use signInWithCredential.';

/// Why the multi-factor members throw.
const String noMultiFactor =
    'multi-factor authentication is not supported yet.';

/// Runs [body] and rethrows the errors of `firebase_auth_providers_dart` as the
/// exceptions of the platform interface, with the same code.
Future<T> guard<T>(Future<T> Function() body) async {
  try {
    return await body();
  } on dart_auth.FirebaseAuthException catch (e, stackTrace) {
    Error.throwWithStackTrace(exceptionOf(e), stackTrace);
  } on dart_app.FirebaseNoSignedInUserException catch (_, stackTrace) {
    Error.throwWithStackTrace(noCurrentUser(), stackTrace);
  }
}

/// The exception of the native implementations when a user operation runs
/// while that user is no longer signed in.
FirebaseAuthException noCurrentUser() => FirebaseAuthException(
  code: 'no-current-user',
  message: 'No user currently signed in.',
);

/// [e] as an exception of the platform interface: the same code, message,
/// email, phone number, tenant and credential. A second-factor challenge
/// becomes a [FirebaseAuthMultiFactorExceptionPlatform] whose resolver cannot
/// finish the sign-in yet.
FirebaseAuthException exceptionOf(dart_auth.FirebaseAuthException e) {
  if (e is dart_auth.FirebaseAuthMultiFactorException) {
    return FirebaseAuthMultiFactorExceptionPlatform(
      code: e.code,
      message: e.message,
      email: e.email,
      phoneNumber: e.phoneNumber,
      tenantId: e.tenantId,
      credential: credentialOf(e.credential),
      resolver: DartMultiFactorResolver(<MultiFactorInfo>[
        for (final hint in e.hints) multiFactorInfoOf(hint),
      ], MultiFactorSession(e.pendingCredential)),
    );
  }
  return FirebaseAuthException(
    code: e.code,
    message: e.message,
    email: e.email,
    phoneNumber: e.phoneNumber,
    tenantId: e.tenantId,
    credential: credentialOf(e.credential),
  );
}

/// A second factor of the client as the interface lists it. The enrolment time
/// is in seconds since the epoch, as on Android; 0 when unknown.
MultiFactorInfo multiFactorInfoOf(dart_auth.MultiFactorInfo info) {
  final double enrolled =
      (info.enrollmentTime?.millisecondsSinceEpoch ?? 0) / 1000;
  return switch (info.factorId) {
    dart_auth.MultiFactorInfo.phoneFactorId => PhoneMultiFactorInfo(
      displayName: info.displayName,
      enrollmentTimestamp: enrolled,
      factorId: info.factorId,
      uid: info.uid,
      phoneNumber: info.phoneNumber ?? '',
    ),
    dart_auth.MultiFactorInfo.totpFactorId => TotpMultiFactorInfo(
      displayName: info.displayName,
      enrollmentTimestamp: enrolled,
      factorId: info.factorId,
      uid: info.uid,
    ),
    _ => MultiFactorInfo(
      displayName: info.displayName,
      enrollmentTimestamp: enrolled,
      factorId: info.factorId,
      uid: info.uid,
    ),
  };
}

/// An [OAuthCredential] of the interface that carries the credential of the
/// client it came from, so that a credential the backend returned (with a
/// pending token, which the interface has no field for) goes back unchanged,
/// for example in the recovery of `account-exists-with-different-credential`.
class DartOAuthCredential extends OAuthCredential {
  DartOAuthCredential(this.source)
    : super(
        providerId: source.providerId,
        signInMethod: source.signInMethod,
        accessToken: source.accessToken,
        idToken: source.idToken,
        secret: source.secret,
        rawNonce: source.rawNonce,
      );

  /// The credential of `firebase_auth_providers_dart`.
  final dart_auth.OAuthCredential source;
}

/// A credential of the client as the interface shows it, or null.
AuthCredential? credentialOf(
  dart_auth.AuthCredential? credential,
) => switch (credential) {
  dart_auth.OAuthCredential() => DartOAuthCredential(credential),
  dart_auth.EmailAuthCredential(:final String email, :final String password?) =>
    EmailAuthProvider.credential(email: email, password: password),
  dart_auth.EmailAuthCredential(
    :final String email,
    :final String emailLink?,
  ) =>
    EmailAuthProvider.credentialWithLink(email: email, emailLink: emailLink),
  _ => null,
};

/// A credential of the interface as the client takes it.
///
/// Throws `unimplemented` for phone, Play Games and Game Center credentials,
/// which need native SDKs, and `argument-error` for an OAuth credential
/// without a token or a credential of another implementation.
dart_auth.AuthCredential clientCredentialOf(AuthCredential credential) {
  switch (credential) {
    case DartOAuthCredential(:final dart_auth.OAuthCredential source):
      return source;
    case EmailAuthCredential(:final String email, :final String password?):
      return dart_auth.EmailAuthProvider.credential(
        email: email,
        password: password,
      );
    case EmailAuthCredential(:final String email, :final String emailLink?):
      return dart_auth.EmailAuthProvider.credentialWithLink(
        email: email,
        emailLink: emailLink,
      );
    case PhoneAuthCredential():
      throw unimplemented('A phone credential', noPhone);
    case OAuthCredential(providerId: 'playgames.google.com' || 'gc.apple.com'):
      throw unimplemented(
        'A ${credential.providerId} credential',
        'Play Games and Game Center sign-in need their native SDKs.',
      );
    case OAuthCredential(
      :final String providerId,
      :final String signInMethod,
      :final String? idToken,
      :final String? accessToken,
      :final String? secret,
      :final String? rawNonce,
    ):
      if ((idToken == null || idToken.isEmpty) &&
          (accessToken == null || accessToken.isEmpty)) {
        throw FirebaseAuthException(
          code: 'argument-error',
          message:
              'A credential of $providerId needs an ID token or an access '
              'token.',
        );
      }
      return dart_auth.OAuthCredential(
        providerId: providerId,
        signInMethod: signInMethod,
        idToken: idToken,
        accessToken: accessToken,
        secret: secret,
        rawNonce: rawNonce,
      );
    default:
      throw FirebaseAuthException(
        code: 'argument-error',
        message:
            'This credential (${credential.providerId}) cannot be used here: '
            'it was made by another implementation of firebase_auth.',
      );
  }
}

/// [settings] as the client takes them.
dart_auth.ActionCodeSettings? actionCodeSettingsOf(
  ActionCodeSettings? settings,
) {
  if (settings == null) {
    return null;
  }
  return dart_auth.ActionCodeSettings(
    url: settings.url,
    handleCodeInApp: settings.handleCodeInApp,
    iOSBundleId: settings.iOSBundleId,
    androidPackageName: settings.androidPackageName,
    androidInstallApp: settings.androidPackageName == null
        ? null
        : settings.androidInstallApp,
    androidMinimumVersion: settings.androidMinimumVersion,
    linkDomain: settings.linkDomain,
  );
}

/// The answer of `checkActionCode` as the interface returns it.
ActionCodeInfo actionCodeInfoOf(dart_auth.ActionCodeInfo info) =>
    ActionCodeInfo(
      operation: switch (info.operation) {
        dart_auth.ActionCodeOperation.passwordReset =>
          ActionCodeInfoOperation.passwordReset,
        dart_auth.ActionCodeOperation.verifyEmail =>
          ActionCodeInfoOperation.verifyEmail,
        dart_auth.ActionCodeOperation.recoverEmail =>
          ActionCodeInfoOperation.recoverEmail,
        dart_auth.ActionCodeOperation.emailSignIn =>
          ActionCodeInfoOperation.emailSignIn,
        dart_auth.ActionCodeOperation.verifyAndChangeEmail =>
          ActionCodeInfoOperation.verifyAndChangeEmail,
        dart_auth.ActionCodeOperation.revertSecondFactorAddition =>
          ActionCodeInfoOperation.revertSecondFactorAddition,
        dart_auth.ActionCodeOperation.unknown =>
          ActionCodeInfoOperation.unknown,
      },
      data: ActionCodeInfoData(
        email: info.email,
        previousEmail: info.previousEmail,
      ),
    );

/// The additional information of a sign-in as the interface returns it.
AdditionalUserInfo? additionalUserInfoOf(dart_auth.AdditionalUserInfo? info) =>
    info == null
    ? null
    : AdditionalUserInfo(
        isNewUser: info.isNewUser,
        providerId: info.providerId,
        profile: info.profile,
        username: info.username,
      );

/// [user] in the shape the interface's `UserPlatform` reads.
InternalUserDetails userDetailsOf(dart_auth.AuthUser user) =>
    InternalUserDetails(
      userInfo: InternalUserInfo(
        uid: user.uid,
        email: user.email,
        displayName: user.displayName,
        photoUrl: user.photoUrl,
        phoneNumber: user.phoneNumber,
        isAnonymous: user.isAnonymous,
        isEmailVerified: user.emailVerified,
        providerId: 'firebase',
        tenantId: user.tenantId,
        creationTimestamp: user.metadata.creationTime?.millisecondsSinceEpoch,
        lastSignInTimestamp:
            user.metadata.lastSignInTime?.millisecondsSinceEpoch,
      ),
      providerData: <Map<Object?, Object?>?>[
        for (final dart_auth.UserInfo info in user.providerData)
          <Object?, Object?>{
            'uid': info.uid,
            'email': info.email,
            'displayName': info.displayName,
            'photoUrl': info.photoUrl,
            'phoneNumber': info.phoneNumber,
            'providerId': info.providerId,
            'isAnonymous': false,
            'isEmailVerified': false,
          },
      ],
    );

/// The claims of an ID token as the interface returns them.
IdTokenResult idTokenResultOf(dart_app.GetTokenResult token) {
  final Map<String, dynamic> claims = token.claims;
  int? millis(String claim) {
    final Object? seconds = claims[claim];
    return seconds is num ? (seconds * 1000).round() : null;
  }

  final Object? firebase = claims['firebase'];
  String? fromFirebase(String key) {
    if (firebase is Map) {
      final Object? value = firebase[key];
      return value is String ? value : null;
    }
    return null;
  }

  return IdTokenResult(
    InternalIdTokenResult(
      token: token.token,
      claims: Map<String?, Object?>.of(claims),
      expirationTimestamp: millis('exp'),
      authTimestamp: millis('auth_time'),
      issuedAtTimestamp: millis('iat'),
      signInProvider: fromFirebase('sign_in_provider'),
      signInSecondFactor: fromFirebase('sign_in_second_factor'),
    ),
  );
}
