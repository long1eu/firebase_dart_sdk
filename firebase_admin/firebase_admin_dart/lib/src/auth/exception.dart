import '../exception.dart';

/// Thrown when an admin call of `FirebaseAuthAdmin` fails.
///
/// It extends [FirebaseAdminException] (and so `FirebaseException` of `firebase_app_dart`) with the [plugin]
/// `auth`: it prints as `[auth/user-not-found] ...`.
///
/// [code] is the code of the Firebase Admin SDK for Node.js without its `auth/` prefix: `user-not-found`, not
/// `USER_NOT_FOUND` (the code of the REST API, kept in [serverCode]) and not `auth/user-not-found`. Errors of
/// the backend are mapped with the table of the Node SDK; a backend code that is not in it becomes
/// `internal-error`, with the code of the backend in [serverCode]. [message] never contains a token, a password
/// or a key.
///
/// The codes you are most likely to meet:
///
/// | Code | Meaning |
/// | --- | --- |
/// | `user-not-found` | no user has this uid (or email) |
/// | `uid-already-exists`, `email-already-exists`, `phone-number-already-exists` | `createUser` or `updateUser` with a value another user has |
/// | `invalid-uid`, `invalid-email`, `invalid-password`, `invalid-phone-number`, `invalid-photo-url`, `invalid-display-name` | an argument was refused before any request |
/// | `argument-error` | an argument was refused (a uid or claims of `createCustomToken`), or the ID token is malformed, has a wrong `aud`, `iss` or signature |
/// | `forbidden-claim`, `claims-too-large`, `invalid-claims` | the claims of `setCustomUserClaims` use a reserved name, exceed 1000 bytes, or are not JSON |
/// | `id-token-expired` | the ID token has expired |
/// | `id-token-revoked` | `checkRevoked`: the tokens of the user were revoked after this one was issued |
/// | `user-disabled` | `checkRevoked`: the account is disabled |
/// | `invalid-credential` | no access token could be obtained, or no service account email for signing |
/// | `insufficient-permission` | the credential lacks a permission (for example `iam.serviceAccounts.signBlob`) |
/// | `project-not-found`, `quota-exceeded` | the backend refused the project or throttles it |
/// | `network-error` | the request did not reach the backend |
/// | `internal-error` | the backend answered with something unexpected |
///
/// ```dart
/// import 'package:firebase_admin_dart/auth.dart';
///
/// Future<AdminUser?> userOrNull(FirebaseAuthAdmin admin, String uid) async {
///   try {
///     return await admin.getUser(uid);
///   } on FirebaseAuthAdminException catch (e) {
///     if (e.code == 'user-not-found') {
///       return null;
///     }
///     rethrow;
///   }
/// }
/// ```
class FirebaseAuthAdminException extends FirebaseAdminException {
  /// Creates an exception with the Admin SDK style [code] (for example `user-not-found`) and a [message]. The
  /// package creates them; you need this only for tests.
  const FirebaseAuthAdminException({
    required super.code,
    required super.message,
    super.serverCode,
    super.httpStatus,
  }) : super(plugin: 'auth');

  /// Maps the error message of the Identity Toolkit API ([serverMessage], for example `USER_NOT_FOUND` or
  /// `INVALID_EMAIL : bad address`) to an exception, like the Node Admin SDK does.
  ///
  /// ```dart
  /// final FirebaseAuthAdminException e = FirebaseAuthAdminException.fromServer(
  ///   'DUPLICATE_LOCAL_ID',
  ///   httpStatus: 400,
  /// );
  /// print(e.code); // uid-already-exists
  /// ```
  factory FirebaseAuthAdminException.fromServer(
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
    final String? code = _codes[serverCode];
    return FirebaseAuthAdminException(
      code: code ?? 'internal-error',
      message:
          detail ??
          (code == null
              ? 'The backend answered with the error $serverCode.'
              : _messages[code] ?? 'The backend answered with $serverCode.'),
      serverCode: serverCode,
      httpStatus: httpStatus,
    );
  }

  /// AUTH_SERVER_TO_CLIENT_CODE of the Node Admin SDK (src/utils/error.ts), the entries the calls of this package
  /// can meet.
  static const Map<String, String> _codes = <String, String>{
    'BILLING_NOT_ENABLED': 'billing-not-enabled',
    'CLAIMS_TOO_LARGE': 'claims-too-large',
    'DUPLICATE_EMAIL': 'email-already-exists',
    'DUPLICATE_LOCAL_ID': 'uid-already-exists',
    'EMAIL_EXISTS': 'email-already-exists',
    'EMAIL_NOT_FOUND': 'email-not-found',
    'FORBIDDEN_CLAIM': 'forbidden-claim',
    'INSUFFICIENT_PERMISSION': 'insufficient-permission',
    'INVALID_CLAIMS': 'invalid-claims',
    'INVALID_DISPLAY_NAME': 'invalid-display-name',
    'INVALID_EMAIL': 'invalid-email',
    'INVALID_ID_TOKEN': 'invalid-id-token',
    'INVALID_PAGE_SELECTION': 'invalid-page-token',
    'INVALID_PHONE_NUMBER': 'invalid-phone-number',
    'INVALID_PHOTO_URL': 'invalid-photo-url',
    'INVALID_PROJECT_ID': 'invalid-project-id',
    'INVALID_SERVICE_ACCOUNT': 'invalid-service-account',
    'INVALID_TENANT_ID': 'invalid-tenant-id',
    'MISSING_LOCAL_ID': 'missing-uid',
    'MISSING_USER_ACCOUNT': 'missing-uid',
    'OPERATION_NOT_ALLOWED': 'operation-not-allowed',
    'PERMISSION_DENIED': 'insufficient-permission',
    'PHONE_NUMBER_EXISTS': 'phone-number-already-exists',
    'PROJECT_NOT_FOUND': 'project-not-found',
    'QUOTA_EXCEEDED': 'quota-exceeded',
    'TENANT_NOT_FOUND': 'tenant-not-found',
    'TENANT_ID_MISMATCH': 'mismatching-tenant-id',
    'TOKEN_EXPIRED': 'id-token-expired',
    'UNAUTHORIZED_DOMAIN': 'unauthorized-continue-uri',
    'USER_DISABLED': 'user-disabled',
    'USER_NOT_FOUND': 'user-not-found',
    'WEAK_PASSWORD': 'invalid-password',
  };

  static const Map<String, String> _messages = <String, String>{
    'user-not-found':
        'There is no user record corresponding to the provided identifier.',
    'uid-already-exists': 'The user with the provided uid already exists.',
    'email-already-exists':
        'The email address is already in use by another account.',
    'phone-number-already-exists':
        'The user with the provided phone number already exists.',
    'invalid-password':
        'The password must be a string with at least 6 characters.',
    'insufficient-permission':
        'The credential used to authenticate the request lacks a permission.',
    'project-not-found': 'No Firebase project was found for the credential.',
    'claims-too-large':
        'The developer claims exceed the maximum size of 1000 bytes.',
    'forbidden-claim': 'The developer claims use a reserved claim name.',
    'user-disabled': 'The user account has been disabled.',
    'id-token-expired': 'The Firebase ID token has expired.',
  };
}
