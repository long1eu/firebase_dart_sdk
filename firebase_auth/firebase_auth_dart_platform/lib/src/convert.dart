// ignore_for_file: invalid_use_of_protected_member
// The value classes of the platform interface have @protected constructors,
// meant for the implementations of the interface, which this package is.

import 'dart:async';

import 'package:firebase_app_dart/firebase_app_dart.dart' as dart_app;
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart'
    as dart_auth;

import 'firebase_auth.dart';
import 'multi_factor.dart';
import 'storage.dart' show isFileSystemException;

/// The exception for a member of the interface that this package does not
/// implement, with the code `unimplemented`.
FirebaseAuthException unimplemented(String member, String why) =>
    FirebaseAuthException(
      code: 'unimplemented',
      message: '$member is not available in firebase_auth_dart_platform: $why',
    );

/// Why `initializeRecaptchaConfig` throws.
const String noRecaptchaConfig =
    'the reCAPTCHA Enterprise configuration of the project is not read here. '
    'Phone requests carry the proof of the AppVerification passed to '
    'FirebaseAuthDart.use.';

/// Why the popup and redirect members throw.
const String noBrowserFlow =
    'popup and redirect flows exist only in a browser. Get the provider token '
    'yourself and use signInWithCredential.';

/// Runs [body] and rethrows its errors as the exceptions of the platform
/// interface, so that an app always gets a [FirebaseAuthException]: the
/// errors of `firebase_auth_providers_dart` with the same code (a
/// second-factor challenge with a resolver that signs in to [auth]), an
/// [ArgumentError] as `argument-error`, an [UnsupportedError] (a flow the
/// platform does not have, such as the loopback flow on the web) as
/// `unimplemented`, a call after the client was disposed (its app was
/// deleted) as `app-deleted`, another [StateError] and a failed file
/// operation as `internal-error`.
Future<T> guard<T>(DartFirebaseAuth auth, Future<T> Function() body) async {
  try {
    return await body();
  } on dart_auth.FirebaseAuthException catch (e, stackTrace) {
    Error.throwWithStackTrace(exceptionOf(e, auth), stackTrace);
  } on dart_app.FirebaseNoSignedInUserException catch (_, stackTrace) {
    Error.throwWithStackTrace(noCurrentUser(), stackTrace);
  } on ArgumentError catch (e, stackTrace) {
    Error.throwWithStackTrace(
      FirebaseAuthException(code: 'argument-error', message: '${e.message}'),
      stackTrace,
    );
  } on dart_auth.FirebaseUserAuthDisposedError catch (e, stackTrace) {
    Error.throwWithStackTrace(
      FirebaseAuthException(code: 'app-deleted', message: e.message),
      stackTrace,
    );
  } on UnsupportedError catch (e, stackTrace) {
    Error.throwWithStackTrace(
      FirebaseAuthException(
        code: 'unimplemented',
        message: 'Not available on this platform: ${e.message}',
      ),
      stackTrace,
    );
  } on StateError catch (e, stackTrace) {
    Error.throwWithStackTrace(
      FirebaseAuthException(code: 'internal-error', message: e.message),
      stackTrace,
    );
  } on Exception catch (e, stackTrace) {
    if (!isFileSystemException(e)) {
      rethrow;
    }
    Error.throwWithStackTrace(
      FirebaseAuthException(code: 'internal-error', message: '$e'),
      stackTrace,
    );
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
/// becomes a [FirebaseAuthMultiFactorExceptionPlatform] whose resolver
/// finishes it with a TOTP or SMS code, through the client's resolver, and returns
/// the result as a credential of [auth].
FirebaseAuthException exceptionOf(
  dart_auth.FirebaseAuthException e,
  DartFirebaseAuth auth,
) {
  if (e is dart_auth.FirebaseAuthMultiFactorException) {
    return FirebaseAuthMultiFactorExceptionPlatform(
      code: e.code,
      message: e.message,
      email: e.email,
      phoneNumber: e.phoneNumber,
      tenantId: e.tenantId,
      credential: credentialOf(e.credential),
      resolver: DartMultiFactorResolver(
        <MultiFactorInfo>[for (final hint in e.hints) multiFactorInfoOf(hint)],
        DartMultiFactorSignInSession(e.resolver),
        auth: auth,
        source: e.resolver,
      ),
    );
  }
  return DartFirebaseAuthException(
    code: e.code,
    message: e.message,
    email: e.email,
    phoneNumber: e.phoneNumber,
    tenantId: e.tenantId,
    credential: credentialOf(e.credential),
    serverCode: e.serverCode,
    httpStatus: e.httpStatus,
  );
}

/// A [FirebaseAuthException] of the platform interface that also keeps what
/// the server answered, for logs: `firebase_auth` passes it to the app as it
/// is, so `catch (e)` can test `e is DartFirebaseAuthException`.
class DartFirebaseAuthException extends FirebaseAuthException {
  /// Creates the exception; [exceptionOf] creates them.
  DartFirebaseAuthException({
    required super.code,
    super.message,
    super.email,
    super.credential,
    super.phoneNumber,
    super.tenantId,
    this.serverCode,
    this.httpStatus,
  });

  /// The error code of the server before mapping (`EMAIL_EXISTS`), or null
  /// when the error did not come from the server.
  final String? serverCode;

  /// The HTTP status of the response, or null when there was none.
  final int? httpStatus;
}

/// The result of `validatePassword` of the client as the interface's
/// [PasswordValidationStatus], with a [PasswordPolicy] built from the same
/// policy.
PasswordValidationStatus passwordValidationStatusOf(
  dart_auth.PasswordValidationStatus status,
) {
  final dart_auth.PasswordPolicy policy = status.passwordPolicy;
  final PasswordPolicy interfacePolicy = PasswordPolicy(<String, dynamic>{
    'customStrengthOptions': <String, dynamic>{
      'minPasswordLength': policy.minPasswordLength,
      'maxPasswordLength': ?policy.maxPasswordLength,
      'containsLowercaseCharacter': ?policy.containsLowercaseCharacter,
      'containsUppercaseCharacter': ?policy.containsUppercaseCharacter,
      'containsNumericCharacter': ?policy.containsNumericCharacter,
      'containsNonAlphanumericCharacter':
          ?policy.containsNonAlphanumericCharacter,
    },
    'allowedNonAlphanumericCharacters': policy.allowedNonAlphanumericCharacters,
    'enforcementState': policy.enforcementState,
    'schemaVersion': policy.schemaVersion,
  });
  return PasswordValidationStatus(status.isValid, interfacePolicy)
    ..meetsMinPasswordLength = status.meetsMinPasswordLength
    ..meetsMaxPasswordLength = status.meetsMaxPasswordLength
    ..meetsLowercaseRequirement = status.meetsLowercaseRequirement
    ..meetsUppercaseRequirement = status.meetsUppercaseRequirement
    ..meetsDigitsRequirement = status.meetsDigitsRequirement
    ..meetsSymbolsRequirement = status.meetsSymbolsRequirement;
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
        appleFullPersonName: _nameOf(source.appleFullPersonName),
      );

  /// The credential of `firebase_auth_providers_dart`.
  final dart_auth.OAuthCredential source;
}

/// The Apple name of a credential of the client, as the interface has it.
AppleFullPersonName? _nameOf(dart_auth.AppleFullPersonName? name) =>
    name == null
    ? null
    : AppleFullPersonName(
        givenName: name.givenName,
        familyName: name.familyName,
        middleName: name.middleName,
        nickname: name.nickname,
        namePrefix: name.namePrefix,
        nameSuffix: name.nameSuffix,
      );

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
  dart_auth.PhoneAuthCredential(:final String temporaryProof?) =>
    temporaryProof.isEmpty ? null : DartPhoneProofCredential(credential),
  _ => null,
};

/// The phone credential of a `credential-already-in-use` error: a temporary
/// proof of a verified number, which `signInWithCredential` takes back to sign
/// in to the account that has the number. FlutterFire's `PhoneAuthCredential`
/// has no field for a proof (and no public constructor), so this is a plain
/// [AuthCredential] of the phone provider that carries the client's credential.
/// Its `toString` and `asMap` show no proof and no number.
class DartPhoneProofCredential extends AuthCredential {
  DartPhoneProofCredential(this.source)
    : super(providerId: 'phone', signInMethod: 'phone');

  /// The credential of `firebase_auth_providers_dart`.
  final dart_auth.PhoneAuthCredential source;
}

/// A phone credential of the interface (a verification id and an SMS code) as
/// the client takes it. Throws `argument-error` for one made with the
/// Android-only `PhoneAuthProvider.credentialFromToken`.
dart_auth.PhoneAuthCredential clientPhoneCredentialOf(
  PhoneAuthCredential credential,
) {
  final String? verificationId = credential.verificationId;
  final String? smsCode = credential.smsCode;
  if (verificationId == null || smsCode == null) {
    throw FirebaseAuthException(
      code: 'argument-error',
      message:
          'A phone credential needs a verification id and an SMS code '
          '(PhoneAuthProvider.credential); credentialFromToken is Android '
          'only.',
    );
  }
  return dart_auth.PhoneAuthProvider.credential(
    verificationId: verificationId,
    verificationCode: smsCode,
  );
}

/// A credential of the interface as the client takes it.
///
/// Throws `unimplemented` for Play Games and Game Center credentials, which
/// need native SDKs, and `argument-error` for an OAuth credential without a
/// token, a phone credential without a verification id or SMS code (the
/// Android-only `PhoneAuthProvider.credentialFromToken`), or a credential of
/// another implementation.
dart_auth.AuthCredential clientCredentialOf(AuthCredential credential) {
  switch (credential) {
    case DartOAuthCredential(:final dart_auth.OAuthCredential source):
      return source;
    case DartPhoneProofCredential(:final dart_auth.PhoneAuthCredential source):
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
      return clientPhoneCredentialOf(credential);
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
      :final AppleFullPersonName? appleFullPersonName,
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
        appleFullPersonName: appleFullPersonName == null
            ? null
            : dart_auth.AppleFullPersonName(
                givenName: appleFullPersonName.givenName,
                familyName: appleFullPersonName.familyName,
                middleName: appleFullPersonName.middleName,
                nickname: appleFullPersonName.nickname,
                namePrefix: appleFullPersonName.namePrefix,
                nameSuffix: appleFullPersonName.nameSuffix,
              ),
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
