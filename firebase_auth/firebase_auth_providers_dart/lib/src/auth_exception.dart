import 'dart:collection';

import 'package:firebase_app_dart/firebase_app_dart.dart';

import 'auth_credential.dart';
import 'firebase_user_auth.dart';
import 'multi_factor.dart';
import 'user_record.dart' show credentialFromResponse;

/// Thrown when a Firebase Auth request, or a token request of an `OAuthTokenProvider`, fails.
///
/// It extends [FirebaseException] with the [plugin] `firebase_auth`, like FlutterFire's
/// `FirebaseAuthException`, so `on FirebaseException catch (e)` catches it too.
///
/// Branch on [code]; [message] is for people, and [serverCode] and [httpStatus] are for logs. None of them
/// contains a token, a password or the API key.
///
/// The codes are those of the Firebase JS SDK. The ones you are most likely to meet:
///
/// | Code | Meaning |
/// | --- | --- |
/// | `wrong-password`, `invalid-credential` | the email and password do not match (projects with email enumeration protection answer `invalid-credential` instead of `wrong-password` and `user-not-found`) |
/// | `user-not-found` | no account has this email address |
/// | `email-already-in-use` | sign-up with an address that has an account |
/// | `weak-password`, `missing-password`, `invalid-email` | the input was refused |
/// | `user-disabled` | the account is disabled |
/// | `operation-not-allowed` | the sign-in method is not enabled for the project |
/// | `admin-restricted-operation` | the project allows this operation to administrators only (for example sign-up) |
/// | `invalid-custom-token`, `custom-token-mismatch` | the custom token is malformed or for another project |
/// | `requires-recent-login` | sign in again (`FirebaseUserAuth.reauthenticateWithCredential`) and retry |
/// | `user-mismatch` | the reauthentication used the credentials of another account |
/// | `account-exists-with-different-credential` | a federated sign-in found an account of the same email address with another method: sign in with it and link [credential] |
/// | `credential-already-in-use`, `provider-already-linked`, `no-such-provider` | a link or unlink that cannot be done |
/// | `tenant-id-mismatch` | the user or the email link belongs to another tenant than `FirebaseUserAuth.tenantId` |
/// | `login-blocked` | a `beforeAuthStateChanged` callback refused the change |
/// | `password-does-not-meet-requirements` | the password fails the project's policy (`FirebaseUserAuth.validatePassword`) |
/// | `argument-error` | an argument the backend was not asked about is wrong (an email link that is not one) |
/// | `multi-factor-auth-required` | the account has a second factor: finish with a code of an authenticator app (a [FirebaseAuthMultiFactorException] with a [FirebaseAuthMultiFactorException.resolver]) |
/// | `multi-factor-info-not-found` | the second factor is not one this package can use (SMS), or the account has no such factor |
/// | `user-token-expired`, `invalid-refresh-token` | the session ended (account deleted, refresh token revoked); the user is signed out |
/// | `invalid-user-token` | the backend refused the ID token |
/// | `expired-action-code`, `invalid-action-code` | the code of an email link is used up, expired or wrong |
/// | `invalid-continue-uri`, `invalid-hosting-link-domain`, `missing-ios-bundle-id`, `missing-android-pkg-name` | an `ActionCodeSettings` value is empty |
/// | `null-user` | the operation needs a signed-in user and nobody is signed in |
/// | `cancelled` | a sign-in, a reauthentication or an operation of the signed-in user was overtaken by another sign-in or a sign-out |
/// | `too-many-requests` | the backend throttles this client; try again later |
/// | `network-request-failed` | the request did not reach the backend |
/// | `invalid-api-key` | the API key is not valid |
/// | `internal-error` | the backend answered with something unexpected |
///
/// The backend's codes are mapped with the complete `SERVER_ERROR_MAP` of the JS SDK; any other code arrives in kebab
/// case: `QUOTA_EXCEEDED` is `quota-exceeded`.
/// `OAuthTokenProvider.serviceAccount` throws `invalid-credential` when the token endpoint refuses the key
/// (`invalid_grant`), and `network-request-failed` or `internal-error` otherwise.
///
/// ```dart
/// try {
///   await auth.signInWithEmailAndPassword(email: email, password: password);
/// } on FirebaseAuthException catch (e) {
///   switch (e.code) {
///     case 'wrong-password' || 'invalid-credential' || 'user-not-found':
///       print('The email address or the password is wrong.');
///     case 'too-many-requests':
///       print('Too many attempts. Try again later.');
///     default:
///       print('Sign-in failed: ${e.message}');
///   }
/// }
/// ```
class FirebaseAuthException extends FirebaseException {
  /// Creates an exception with the SDK style [code] (for example `wrong-password`) and a [message]. The
  /// package creates them; you need this only for tests and token providers of your own.
  ///
  /// [email], [phoneNumber] and [tenantId] are those of FlutterFire's `FirebaseAuthException`: the account an
  /// error is about, when the backend names it.
  const FirebaseAuthException({
    required String code,
    required String message,
    this.serverCode,
    this.httpStatus,
    this.email,
    this.phoneNumber,
    this.tenantId,
    this.credential,
    this.serverResponse,
  }) : super(plugin: 'firebase_auth', code: code, message: message);

  /// Maps the error message of the Identity Toolkit or Secure Token API ([serverMessage], for example
  /// `EMAIL_EXISTS` or `WEAK_PASSWORD : Password should be at least 6 characters`) to an exception.
  ///
  /// The part before ` : ` becomes [serverCode] and, mapped like the JS SDK does, [code]; the part after it (or a
  /// standard text) becomes [message].
  ///
  /// ```dart
  /// final FirebaseAuthException e = FirebaseAuthException.fromServer(
  ///   'EMAIL_EXISTS',
  ///   httpStatus: 400,
  /// );
  /// print(e.code); // email-already-in-use
  /// ```
  ///
  /// [response] is the decoded body of the answer. For the errors the JS SDK tags with the answer
  /// (`credential-already-in-use`, `email-already-in-use`, `user-disabled`) its `email`, `phoneNumber` and
  /// `tenantId` become those of the exception, the message is the standard one, and the answer is kept as
  /// [serverResponse].
  factory FirebaseAuthException.fromServer(
    String serverMessage, {
    int? httpStatus,
    Map<String, Object?>? response,
  }) {
    final int separator = serverMessage.indexOf(' : ');
    final String serverCode =
        (separator < 0 ? serverMessage : serverMessage.substring(0, separator))
            .trim();
    final String? detail = separator < 0
        ? null
        : serverMessage.substring(separator + 3).trim();
    // Like the JS SDK (_performFetchWithErrorHandling): the codes of SERVER_ERROR_MAP, and any other code of the
    // backend in kebab case (`QUOTA_EXCEEDED` is `quota-exceeded`).
    final String code =
        _codes[serverCode] ??
        (serverCode.contains('API key not valid') ||
                serverCode.contains('API_KEY_INVALID')
            ? 'invalid-api-key'
            : serverCode.toLowerCase().replaceAll(RegExp(r'[_\s]+'), '-'));
    // _performFetchWithErrorHandling: these three are thrown with the answer attached (_makeTaggedError).
    final bool tagged = const <String>{
      'FEDERATED_USER_ID_ALREADY_LINKED',
      'EMAIL_EXISTS',
      'USER_DISABLED',
    }.contains(serverCode);
    String? text(String key) {
      final Object? value = response?[key];
      return value is String && value.isNotEmpty ? value : null;
    }

    return FirebaseAuthException(
      code: code,
      message: tagged
          ? _messages[code]!
          : detail ?? _messages[code] ?? serverMessage,
      serverCode: serverCode,
      httpStatus: httpStatus,
      email: tagged ? text('email') : null,
      phoneNumber: tagged ? text('phoneNumber') : null,
      tenantId: tagged ? text('tenantId') : null,
      credential: tagged ? credentialFromResponse(response) : null,
      serverResponse: tagged ? _ServerResponse.of(response) : null,
    );
  }

  /// The exception for an answer of the Identity Toolkit API with `needConfirmation` (the JS SDK checks it before
  /// anything else): the account of the email address of a federated credential exists and was created with
  /// another sign-in method. The code is `account-exists-with-different-credential`; [email] is the address.
  factory FirebaseAuthException.needConfirmation(
    Map<String, Object?> response, {
    int? httpStatus,
  }) {
    String? text(String key) {
      final Object? value = response[key];
      return value is String && value.isNotEmpty ? value : null;
    }

    return FirebaseAuthException(
      code: 'account-exists-with-different-credential',
      message: _messages['account-exists-with-different-credential']!,
      httpStatus: httpStatus,
      email: text('email'),
      phoneNumber: text('phoneNumber'),
      tenantId: text('tenantId'),
      credential: credentialFromResponse(response),
      serverResponse: _ServerResponse.of(response),
    );
  }

  /// The error code in the style of the Firebase SDKs: `wrong-password`, `email-already-in-use`,
  /// `network-request-failed`, `internal-error`, ... (see the table of [FirebaseAuthException]).
  @override
  String get code => super.code;

  /// A description of the error. It never contains a token or a password.
  @override
  String get message => super.message!;

  /// The code the backend returned (for example `INVALID_PASSWORD`), when the error came from the backend.
  final String? serverCode;

  /// The HTTP status of the response, when there was one.
  final int? httpStatus;

  /// The email address of the account the error is about, when the backend named it (for example with
  /// `account-exists-with-different-credential`).
  final String? email;

  /// The phone number of the account the error is about, when the backend named it.
  final String? phoneNumber;

  /// The tenant of the account the error is about, when the backend named it.
  final String? tenantId;

  /// The provider's credential of a failed federated sign-in or link, when the backend returned it
  /// (FlutterFire's `credential`, the JS SDK's `credentialFromError`): with
  /// `account-exists-with-different-credential`, sign in with a method of [email], then link this credential.
  /// It holds tokens: [toString] and [message] leave it out.
  final AuthCredential? credential;

  /// The answer of the backend that came with the error, for the errors the JS SDK tags with it
  /// (`account-exists-with-different-credential`, `credential-already-in-use`, `email-already-in-use`,
  /// `user-disabled`): the JS SDK's `customData._tokenResponse`. Null for the other errors.
  ///
  /// It can hold tokens (`idToken`, `refreshToken`, `oauthAccessToken`, ...): it is unmodifiable, its [toString]
  /// lists only its keys, and the [toString] of the exception leaves it out. Do not send it anywhere but to your
  /// own code.
  final Map<String, Object?>? serverResponse;

  /// Whether the session is no longer valid: the backend rejected the request with HTTP 400 because the refresh
  /// token was revoked or the account is gone or disabled. The user is signed out when a token refresh fails with
  /// such an error. The same code with another status (a 5xx of an overloaded backend) does not end the session.
  bool get invalidatesSession =>
      httpStatus == 400 &&
      const <String>{
        'user-token-expired',
        'invalid-refresh-token',
        'user-disabled',
        'user-not-found',
      }.contains(code);

  /// `SERVER_ERROR_MAP` of the JS SDK (`packages/auth/src/api/errors.ts` of `@firebase/auth` 1.13.10), complete.
  /// Codes that are not listed map to their kebab case form, as in the JS SDK.
  static const Map<String, String> _codes = <String, String>{
    // Custom token.
    'CREDENTIAL_MISMATCH': 'custom-token-mismatch',
    'MISSING_CUSTOM_TOKEN': 'internal-error',
    // createAuthUri.
    'INVALID_IDENTIFIER': 'invalid-email',
    'MISSING_CONTINUE_URI': 'internal-error',
    // Email and password.
    'INVALID_PASSWORD': 'wrong-password',
    'MISSING_PASSWORD': 'missing-password',
    'INVALID_LOGIN_CREDENTIALS': 'invalid-credential',
    'EMAIL_EXISTS': 'email-already-in-use',
    'PASSWORD_LOGIN_DISABLED': 'operation-not-allowed',
    // signInWithIdp.
    'INVALID_IDP_RESPONSE': 'invalid-credential',
    'INVALID_PENDING_TOKEN': 'invalid-credential',
    'FEDERATED_USER_ID_ALREADY_LINKED': 'credential-already-in-use',
    'MISSING_REQ_TYPE': 'internal-error',
    // Password reset and action codes.
    'EMAIL_NOT_FOUND': 'user-not-found',
    'RESET_PASSWORD_EXCEED_LIMIT': 'too-many-requests',
    'EXPIRED_OOB_CODE': 'expired-action-code',
    'INVALID_OOB_CODE': 'invalid-action-code',
    'MISSING_OOB_CODE': 'internal-error',
    // Requests with an ID token.
    'CREDENTIAL_TOO_OLD_LOGIN_AGAIN': 'requires-recent-login',
    'INVALID_ID_TOKEN': 'invalid-user-token',
    'TOKEN_EXPIRED': 'user-token-expired',
    'USER_NOT_FOUND': 'user-token-expired',
    // Others.
    'TOO_MANY_ATTEMPTS_TRY_LATER': 'too-many-requests',
    'PASSWORD_DOES_NOT_MEET_REQUIREMENTS':
        'password-does-not-meet-requirements',
    // Phone.
    'INVALID_CODE': 'invalid-verification-code',
    'INVALID_SESSION_INFO': 'invalid-verification-id',
    'INVALID_TEMPORARY_PROOF': 'invalid-credential',
    'MISSING_SESSION_INFO': 'missing-verification-id',
    'SESSION_EXPIRED': 'code-expired',
    // Action code settings.
    'MISSING_ANDROID_PACKAGE_NAME': 'missing-android-pkg-name',
    'UNAUTHORIZED_DOMAIN': 'unauthorized-continue-uri',
    // getProjectConfig with a client id.
    'INVALID_OAUTH_CLIENT_ID': 'invalid-oauth-client-id',
    // Sign-up or deletion restricted to administrators.
    'ADMIN_ONLY_OPERATION': 'admin-restricted-operation',
    // Multi-factor.
    'INVALID_MFA_PENDING_CREDENTIAL': 'invalid-multi-factor-session',
    'MFA_ENROLLMENT_NOT_FOUND': 'multi-factor-info-not-found',
    'MISSING_MFA_ENROLLMENT_ID': 'missing-multi-factor-info',
    'MISSING_MFA_PENDING_CREDENTIAL': 'missing-multi-factor-session',
    'SECOND_FACTOR_EXISTS': 'second-factor-already-in-use',
    'SECOND_FACTOR_LIMIT_EXCEEDED': 'maximum-second-factor-count-exceeded',
    // Blocking functions.
    'BLOCKING_FUNCTION_ERROR_RESPONSE': 'internal-error',
    // reCAPTCHA.
    'RECAPTCHA_NOT_ENABLED': 'recaptcha-not-enabled',
    'MISSING_RECAPTCHA_TOKEN': 'missing-recaptcha-token',
    'INVALID_RECAPTCHA_TOKEN': 'invalid-recaptcha-token',
    'INVALID_RECAPTCHA_ACTION': 'invalid-recaptcha-action',
    'MISSING_CLIENT_TYPE': 'missing-client-type',
    'MISSING_RECAPTCHA_VERSION': 'missing-recaptcha-version',
    'INVALID_RECAPTCHA_VERSION': 'invalid-recaptcha-version',
    'INVALID_REQ_TYPE': 'invalid-req-type',
  };

  /// The messages of the JS SDK (`_debugErrorMap` of `packages/auth/src/core/errors.ts`) for the codes the backend
  /// can produce, shortened where the original addresses a web page.
  static const Map<String, String> _messages = <String, String>{
    'account-exists-with-different-credential':
        'An account already exists with the same email address but different sign-in credentials. Sign in '
        'using a provider associated with this email address.',
    'admin-restricted-operation':
        'This operation is restricted to administrators only.',
    'captcha-check-failed':
        'The reCAPTCHA response token provided is either invalid, expired, already used or the domain associated '
        'with it does not match the list of allowed domains.',
    'code-expired':
        'The SMS code has expired. Re-send the verification code to try again.',
    'credential-already-in-use':
        'This credential is already associated with a different user account.',
    'custom-token-mismatch': 'The custom token belongs to another project.',
    'dynamic-link-not-activated':
        'Activate Dynamic Links in the Firebase Console and agree to the terms and conditions.',
    'email-already-in-use':
        'The email address is already in use by another account.',
    'email-change-needs-verification':
        'Multi-factor users must always have a verified email.',
    'expired-action-code': 'The action code has expired.',
    'internal-error': 'An internal error has occurred.',
    'invalid-api-key': 'The API key is not valid.',
    'invalid-app-credential':
        'The phone verification request contains an invalid application verifier. The reCAPTCHA token response '
        'is either invalid or expired.',
    'invalid-app-id':
        'The mobile app identifier is not registered for the current project.',
    'invalid-cert-hash': 'The SHA-1 certificate hash provided is invalid.',
    'invalid-continue-uri':
        'The continue URL provided in the request is invalid.',
    'invalid-credential':
        'The supplied credential is incorrect or has expired.',
    'invalid-custom-token':
        'The custom token is malformed or its signature is invalid.',
    'invalid-dynamic-link-domain':
        'The provided dynamic link domain is not configured or authorized for the current project.',
    'invalid-email': 'The email address is badly formatted.',
    'invalid-hosting-link-domain':
        'The provided Hosting link domain is not configured in Firebase Hosting or is not owned by the current '
        'project.',
    'invalid-message-payload':
        'The email template corresponding to this action contains invalid characters in its message.',
    'invalid-multi-factor-session':
        'The request does not contain a valid proof of first factor successful sign-in.',
    'invalid-oauth-client-id':
        'The OAuth client ID provided is either invalid or does not match the specified API key.',
    'invalid-phone-number':
        'The format of the phone number provided is incorrect (expected E.164: +[country code][number]).',
    'invalid-provider-id': 'The specified provider ID is invalid.',
    'invalid-recipient-email':
        'The email corresponding to this action failed to send as the provided recipient email address is '
        'invalid.',
    'invalid-req-type': 'Invalid request parameters.',
    'invalid-sender':
        'The email template corresponding to this action contains an invalid sender email or name.',
    'invalid-tenant-id': 'The tenant ID is invalid.',
    'invalid-user-token': 'The credential of the user is no longer valid.',
    'invalid-verification-code':
        'The SMS verification code used to create the phone auth credential is invalid.',
    'invalid-verification-id':
        'The verification ID used to create the phone auth credential is invalid.',
    'maximum-second-factor-count-exceeded':
        'The maximum allowed number of second factors on a user has been exceeded.',
    'missing-android-pkg-name':
        'An Android package name must be provided if the Android app is required to be installed.',
    'missing-ios-bundle-id':
        'An iOS bundle ID must be provided if an App Store ID is provided.',
    'missing-multi-factor-info': 'No second factor identifier is provided.',
    'missing-multi-factor-session':
        'The request is missing proof of first factor successful sign-in.',
    'missing-or-invalid-nonce':
        'The request does not contain a valid nonce. This can occur if the SHA-256 hash of the provided raw nonce '
        'does not match the hashed nonce in the ID token payload.',
    'missing-password': 'A non-empty password must be provided.',
    'missing-verification-id':
        'The phone auth credential was created with an empty verification ID.',
    'multi-factor-info-not-found':
        'The user does not have a second factor matching the identifier provided.',
    'operation-not-allowed':
        'This sign-in method is not enabled for the project.',
    'password-does-not-meet-requirements':
        'The password does not meet the requirements.',
    'quota-exceeded':
        "The project's quota for this operation has been exceeded.",
    'recaptcha-not-enabled':
        'reCAPTCHA Enterprise integration is not enabled for this project.',
    'missing-recaptcha-token':
        'The reCAPTCHA token is missing when sending request to the backend.',
    'invalid-recaptcha-token':
        'The reCAPTCHA token is invalid when sending request to the backend.',
    'invalid-recaptcha-action':
        'The reCAPTCHA action is invalid when sending request to the backend.',
    'missing-client-type':
        'The reCAPTCHA client type is missing when sending request to the backend.',
    'missing-recaptcha-version':
        'The reCAPTCHA version is missing when sending request to the backend.',
    'invalid-recaptcha-version':
        'The reCAPTCHA version is invalid when sending request to the backend.',
    'rejected-credential':
        'The request contains malformed or mismatching credentials.',
    'requires-recent-login':
        'This operation is sensitive and requires recent authentication. Sign in again.',
    'second-factor-already-in-use':
        'The second factor is already enrolled on this account.',
    'tenant-id-mismatch':
        "The provided tenant ID does not match the Auth instance's tenant ID.",
    'too-many-requests': 'Too many attempts. Try again later.',
    'unauthorized-continue-uri':
        'The domain of the continue URL is not allowed. Add it to the authorized domains of the project.',
    'unsupported-first-factor':
        'Enrolling a second factor or signing in with a multi-factor account requires sign-in with a supported '
        'first factor.',
    'unsupported-tenant-operation':
        'This operation is not supported in a multi-tenant context.',
    'unverified-email': 'The operation requires a verified email.',
    'user-cancelled':
        'The user did not grant your application the permissions it requested.',
    'user-disabled': 'The user account has been disabled.',
    'user-mismatch':
        'The supplied credentials do not correspond to the signed-in user.',
    'user-not-found': 'There is no user record for this identifier.',
    'user-token-expired':
        'The credential of the user is no longer valid. Sign in again.',
    'invalid-refresh-token': 'The refresh token is invalid. Sign in again.',
    'invalid-action-code':
        'The action code is invalid. It may be malformed, expired, or already used.',
    'weak-password': 'The password is too weak.',
    'wrong-password': 'The password is invalid.',
  };

  @override
  String toString() => 'FirebaseAuthException(code: $code): $message';
}

/// The answer of [FirebaseAuthException.serverResponse]: unmodifiable, and printed without its values.
class _ServerResponse extends UnmodifiableMapView<String, Object?> {
  _ServerResponse(super.map);

  static _ServerResponse? of(Map<String, Object?>? response) => response == null
      ? null
      : _ServerResponse(Map<String, Object?>.of(response));

  @override
  String toString() =>
      '{${keys.map((String key) => '$key: <redacted>').join(', ')}}';
}

/// Thrown by a sign-in or a reauthentication when the account has a second factor enrolled: the email address and
/// the password (or another first factor) were right, and the backend asks for the second factor before it issues
/// tokens. Its [code] is `multi-factor-auth-required`, like the JS SDK's `auth/multi-factor-auth-required`.
///
/// Nobody is signed in by the first factor alone, and the previous user, if any, stays signed in. [resolver]
/// finishes the sign-in with a code of an authenticator app (TOTP); [hints] lists the account's factors. SMS second
/// factors are listed but cannot be used by this package: when they are the only factors of the account, [message]
/// says so and the resolver throws `multi-factor-info-not-found`.
///
/// It is a [FirebaseAuthException], so `on FirebaseAuthException catch (e)` with `e.code` keeps working.
///
/// ```dart
/// try {
///   await auth.signInWithEmailAndPassword(email: email, password: password);
/// } on FirebaseAuthMultiFactorException catch (e) {
///   for (final MultiFactorInfo hint in e.hints) {
///     print('${hint.factorId}: ${hint.displayName ?? hint.phoneNumber ?? hint.uid}');
///   }
///   final UserCredential result = await e.resolver!.resolveSignInWithTotp(codeFromTheApp);
/// }
/// ```
class FirebaseAuthMultiFactorException extends FirebaseAuthException {
  /// Creates the exception. The package creates them (see [fromResponse]); you need this only for tests.
  const FirebaseAuthMultiFactorException({
    required this.pendingCredential,
    required this.hints,
    super.message = defaultMessage,
    super.httpStatus,
    this.resolver,
  }) : super(code: 'multi-factor-auth-required');

  /// The [message] when the account has an authenticator app (TOTP) factor, or when it lists none.
  static const String defaultMessage =
      'The account has a second factor (multi-factor authentication): finish the sign-in with a code of the '
      'authenticator app (FirebaseAuthMultiFactorException.resolver).';

  /// The [message] when the account's second factors are all of a kind this package cannot use (SMS).
  static const String unsupportedFactorsMessage =
      'The account has a second factor (multi-factor authentication) that this package cannot use: its second '
      'factors are SMS only, which needs reCAPTCHA or a native Firebase SDK. Sign in with an official Firebase SDK, '
      'or enrol an authenticator app (TOTP) factor on the account.';

  /// The exception for an answer of a sign-in endpoint of the Identity Toolkit API (for example
  /// `accounts:signInWithPassword`) that asks for a second factor, or null when [response] is not such an answer.
  /// It has no [resolver]: [FirebaseUserAuth] adds one to the exceptions it throws.
  ///
  /// Such an answer has HTTP status 200, no `idToken`, an `mfaPendingCredential` and the enrolled factors in
  /// `mfaInfo` (see [MultiFactorInfo.fromResponse]); the JS SDK detects it the same way
  /// (`_performSignInRequest`). Entries of `mfaInfo` without an `mfaEnrollmentId` are left out. The [message] is
  /// [unsupportedFactorsMessage] when the factors are listed and none is an authenticator app factor, and
  /// [defaultMessage] otherwise.
  static FirebaseAuthMultiFactorException? fromResponse(
    Map<String, Object?> response, {
    int? httpStatus,
  }) {
    final Object? pending = response['mfaPendingCredential'];
    if (pending is! String || pending.isEmpty) {
      return null;
    }
    final Object? enrollments = response['mfaInfo'];
    final List<MultiFactorInfo> hints =
        List<MultiFactorInfo>.unmodifiable(<MultiFactorInfo>[
          if (enrollments is List)
            for (final Object? enrollment in enrollments)
              ?MultiFactorInfo.fromResponse(enrollment),
        ]);
    return FirebaseAuthMultiFactorException(
      pendingCredential: pending,
      hints: hints,
      message:
          hints.isNotEmpty &&
              !hints.any(
                (MultiFactorInfo h) =>
                    h.factorId == MultiFactorInfo.totpFactorId,
              )
          ? unsupportedFactorsMessage
          : defaultMessage,
      httpStatus: httpStatus,
    );
  }

  /// The `mfaPendingCredential` of the backend: proof that the first factor was right, which
  /// `v2/accounts/mfaSignIn:finalize` takes to finish the sign-in with a second factor ([resolver] does that). It
  /// expires after a few minutes.
  ///
  /// It is a credential: do not log it or send it anywhere but to the Identity Toolkit API. [toString] and
  /// [message] do not contain it.
  final String pendingCredential;

  /// The second factors enrolled on the account, as the backend lists them for the sign-in (`mfaInfo`); the
  /// phone numbers are masked.
  final List<MultiFactorInfo> hints;

  /// Finishes the sign-in or the reauthentication with a second factor. Set on every exception a sign-in or a
  /// reauthentication of [FirebaseUserAuth] throws; null on one created by hand, and on one thrown by
  /// [FirebaseUserAuth.linkWithCredential] (a link cannot be finished with a second factor, as in the JS SDK).
  final MultiFactorResolver? resolver;
}

/// Thrown by a call on a `FirebaseUserAuth` after its `dispose` (the `app-deleted` condition of the JS SDK).
///
/// A [StateError], since using a disposed object is a programming error; `firebase_auth_dart_platform` reports it
/// as a `FirebaseAuthException` with the code `app-deleted`.
class FirebaseUserAuthDisposedError extends StateError {
  /// Creates the error.
  FirebaseUserAuthDisposedError()
    : super('This FirebaseUserAuth was disposed.');
}
