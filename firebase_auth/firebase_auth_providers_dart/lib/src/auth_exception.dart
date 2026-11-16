import 'package:firebase_app_dart/firebase_app_dart.dart';

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
/// | `requires-recent-login` | sign in again (`FirebaseUserAuth.reauthenticateWithEmailAndPassword`) and retry |
/// | `user-mismatch` | the reauthentication used the credentials of another account |
/// | `multi-factor-auth-required` | the account has a second factor; this package cannot finish that sign-in (a [FirebaseAuthMultiFactorException]) |
/// | `user-token-expired`, `invalid-refresh-token` | the session ended (account deleted, refresh token revoked); the user is signed out |
/// | `invalid-user-token` | the backend refused the ID token |
/// | `expired-action-code`, `invalid-action-code` | the code of an email link is used up, expired or wrong |
/// | `invalid-continue-uri`, `invalid-hosting-link-domain`, `missing-ios-bundle-id`, `missing-android-pkg-name` | an `ActionCodeSettings` value is empty |
/// | `null-user` | the operation needs a signed-in user and nobody is signed in |
/// | `cancelled` | a sign-in or a reauthentication was overtaken by another sign-in or a sign-out |
/// | `too-many-requests` | the backend throttles this client; try again later |
/// | `network-request-failed` | the request did not reach the backend |
/// | `invalid-api-key` | the API key is not valid |
/// | `internal-error` | the backend answered with something unexpected |
///
/// Any other code of the backend arrives in kebab case: `QUOTA_EXCEEDED` is `quota-exceeded`.
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
  const FirebaseAuthException({
    required String code,
    required String message,
    this.serverCode,
    this.httpStatus,
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
  factory FirebaseAuthException.fromServer(
    String serverMessage, {
    int? httpStatus,
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
    return FirebaseAuthException(
      code: code,
      message: detail ?? _messages[code] ?? serverMessage,
      serverCode: serverCode,
      httpStatus: httpStatus,
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

  /// Whether the session is no longer valid: the refresh token was revoked or the account is gone or disabled.
  /// The user is signed out when a token refresh fails with such an error.
  bool get invalidatesSession => const <String>{
    'user-token-expired',
    'invalid-refresh-token',
    'user-disabled',
    'user-not-found',
  }.contains(code);

  /// SERVER_ERROR_MAP of the JS SDK (packages/auth/src/api/errors.ts), the entries that the REST calls of this
  /// package can meet. Codes that are not listed map to their kebab case form.
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
    'ADMIN_ONLY_OPERATION': 'admin-restricted-operation',
    'INVALID_REQ_TYPE': 'invalid-req-type',
    // Not in the map of the JS SDK, which turns them into the same codes (kebab case); listed for clarity.
    'INVALID_EMAIL': 'invalid-email',
    'WEAK_PASSWORD': 'weak-password',
    'USER_DISABLED': 'user-disabled',
    'OPERATION_NOT_ALLOWED': 'operation-not-allowed',
    'INVALID_CUSTOM_TOKEN': 'invalid-custom-token',
    'INVALID_REFRESH_TOKEN': 'invalid-refresh-token',
  };

  static const Map<String, String> _messages = <String, String>{
    'email-already-in-use':
        'The email address is already in use by another account.',
    'user-not-found': 'There is no user record for this identifier.',
    'wrong-password': 'The password is invalid.',
    'invalid-credential':
        'The supplied credential is incorrect or has expired.',
    'invalid-email': 'The email address is badly formatted.',
    'weak-password': 'The password is too weak.',
    'user-disabled': 'The user account has been disabled.',
    'too-many-requests': 'Too many attempts. Try again later.',
    'operation-not-allowed':
        'This sign-in method is not enabled for the project.',
    'invalid-custom-token':
        'The custom token is malformed or its signature is invalid.',
    'custom-token-mismatch': 'The custom token belongs to another project.',
    'user-token-expired':
        'The credential of the user is no longer valid. Sign in again.',
    'invalid-refresh-token': 'The refresh token is invalid. Sign in again.',
    'invalid-api-key': 'The API key is not valid.',
    'expired-action-code': 'The action code has expired.',
    'invalid-action-code':
        'The action code is invalid. It may be malformed, expired, or already used.',
    'requires-recent-login':
        'This operation is sensitive and requires recent authentication. Sign in again.',
    'user-mismatch':
        'The supplied credentials do not correspond to the signed-in user.',
    'invalid-user-token': 'The credential of the user is no longer valid.',
  };

  @override
  String toString() => 'FirebaseAuthException(code: $code): $message';
}

/// Thrown by a sign-in or a reauthentication when the account has a second factor enrolled: the email address and
/// the password (or another first factor) were right, and the backend asks for the second factor before it issues
/// tokens. Its [code] is `multi-factor-auth-required`, like the JS SDK's `auth/multi-factor-auth-required`.
///
/// This package does not sign in with a second factor (there is no `MultiFactorResolver`): nobody is signed in
/// after this error, and the previous user, if any, stays signed in. The exception tells an app what happened and
/// which factors the account has ([hints]), and carries the [pendingCredential] for code that finishes the
/// sign-in over the REST API itself (`v2/accounts/mfaSignIn:start` and `:finalize` of the Identity Toolkit API).
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
/// }
/// ```
class FirebaseAuthMultiFactorException extends FirebaseAuthException {
  /// Creates the exception. The package creates them (see [fromResponse]); you need this only for tests.
  const FirebaseAuthMultiFactorException({
    required this.pendingCredential,
    required this.hints,
    super.message = defaultMessage,
    super.httpStatus,
  }) : super(code: 'multi-factor-auth-required');

  /// The [message] of the exceptions this package throws.
  static const String defaultMessage =
      'The account has a second factor (multi-factor authentication), and signing in with a second factor is '
      'not supported by this package yet.';

  /// The exception for an answer of a sign-in endpoint of the Identity Toolkit API (for example
  /// `accounts:signInWithPassword`) that asks for a second factor, or null when [response] is not such an answer.
  ///
  /// Such an answer has HTTP status 200, no `idToken`, an `mfaPendingCredential` and the enrolled factors in
  /// `mfaInfo` (see [MultiFactorInfo.fromResponse]); the JS SDK detects it the same way
  /// (`_performSignInRequest`). Entries of `mfaInfo` without an `mfaEnrollmentId` are left out.
  static FirebaseAuthMultiFactorException? fromResponse(
    Map<String, Object?> response, {
    int? httpStatus,
  }) {
    final Object? pending = response['mfaPendingCredential'];
    if (pending is! String || pending.isEmpty) {
      return null;
    }
    final Object? enrollments = response['mfaInfo'];
    return FirebaseAuthMultiFactorException(
      pendingCredential: pending,
      hints: List<MultiFactorInfo>.unmodifiable(<MultiFactorInfo>[
        if (enrollments is List)
          for (final Object? enrollment in enrollments)
            ?MultiFactorInfo.fromResponse(enrollment),
      ]),
      httpStatus: httpStatus,
    );
  }

  /// The `mfaPendingCredential` of the backend: proof that the first factor was right, which
  /// `v2/accounts/mfaSignIn:start` and `:finalize` take to finish the sign-in with a second factor. It expires
  /// after a few minutes.
  ///
  /// It is a credential: do not log it or send it anywhere but to the Identity Toolkit API. [toString] and
  /// [message] do not contain it.
  final String pendingCredential;

  /// The second factors enrolled on the account, as the backend lists them for the sign-in (`mfaInfo`); the
  /// phone numbers are masked. Pass the [MultiFactorInfo.uid] of one of them as `mfaEnrollmentId` to
  /// `mfaSignIn:start`.
  final List<MultiFactorInfo> hints;
}

/// A second factor enrolled on an account, as listed by [FirebaseAuthMultiFactorException.hints] (`MultiFactorInfo`
/// of the JS SDK and of FlutterFire, with the phone number of `PhoneMultiFactorInfo`).
class MultiFactorInfo {
  /// Creates the information. The package creates them; you need this only for tests.
  const MultiFactorInfo({
    required this.uid,
    required this.factorId,
    this.displayName,
    this.phoneNumber,
    this.enrollmentTime,
  });

  /// The [factorId] of an SMS second factor (`PhoneMultiFactorGenerator.FACTOR_ID` of the JS SDK).
  static const String phoneFactorId = 'phone';

  /// The [factorId] of a time-based one-time password (authenticator app) second factor
  /// (`TotpMultiFactorGenerator.FACTOR_ID` of the JS SDK).
  static const String totpFactorId = 'totp';

  /// The [factorId] of a factor this package does not know (neither `phoneInfo` nor `totpInfo` in the answer).
  static const String unknownFactorId = 'unknown';

  /// Reads one entry of the `mfaInfo` list of the Identity Toolkit API (`MfaEnrollment`), or returns null when
  /// [enrollment] is not an object with an `mfaEnrollmentId`.
  ///
  /// The factor is [phoneFactorId] when the entry has `phoneInfo`, [totpFactorId] when it has `totpInfo`, and
  /// [unknownFactorId] otherwise (the JS SDK fails with `internal-error` there). `enrolledAt` is read as an
  /// RFC 3339 timestamp (the REST API) or as milliseconds since the epoch.
  static MultiFactorInfo? fromResponse(Object? enrollment) {
    if (enrollment is! Map<String, Object?>) {
      return null;
    }
    final Object? id = enrollment['mfaEnrollmentId'];
    if (id is! String || id.isEmpty) {
      return null;
    }
    final Object? displayName = enrollment['displayName'];
    final Object? phone = enrollment['phoneInfo'];
    final Object? enrolledAt = enrollment['enrolledAt'];
    return MultiFactorInfo(
      uid: id,
      factorId: enrollment.containsKey('phoneInfo')
          ? phoneFactorId
          : enrollment.containsKey('totpInfo')
          ? totpFactorId
          : unknownFactorId,
      displayName: displayName is String && displayName.isNotEmpty
          ? displayName
          : null,
      phoneNumber: phone is String && phone.isNotEmpty ? phone : null,
      enrollmentTime: switch (enrolledAt) {
        final String text => DateTime.tryParse(text)?.toUtc(),
        final num millis => DateTime.fromMillisecondsSinceEpoch(
          millis.toInt(),
          isUtc: true,
        ),
        _ => null,
      },
    );
  }

  /// The id of the enrolment (`mfaEnrollmentId` of the REST API).
  final String uid;

  /// The kind of factor: [phoneFactorId], [totpFactorId] or [unknownFactorId].
  final String factorId;

  /// The name the user gave the factor, if any.
  final String? displayName;

  /// For a [phoneFactorId] factor, the phone number as the backend shows it during a sign-in: masked, for example
  /// `+*******1234`. Null for other factors.
  final String? phoneNumber;

  /// When the factor was enrolled (UTC), or null when the backend did not say.
  final DateTime? enrollmentTime;

  @override
  bool operator ==(Object other) =>
      other is MultiFactorInfo &&
      other.uid == uid &&
      other.factorId == factorId &&
      other.displayName == displayName &&
      other.phoneNumber == phoneNumber &&
      other.enrollmentTime == enrollmentTime;

  @override
  int get hashCode =>
      Object.hash(uid, factorId, displayName, phoneNumber, enrollmentTime);

  @override
  String toString() => 'MultiFactorInfo($factorId, $uid)';
}
