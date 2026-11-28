import '../exception.dart';

/// Thrown when `FirebaseAppCheckAdmin.verifyToken` refuses a token or cannot check it.
///
/// It extends [FirebaseAdminException] with the [plugin] `app-check`: it prints as
/// `[app-check/app-check-token-expired] ...`. The codes are those of the Firebase Admin SDK for Node.js:
///
/// | Code | Meaning |
/// | --- | --- |
/// | `invalid-argument` | the token is malformed, unsigned, signed with another algorithm or an unknown key, has a wrong signature, or a wrong `aud`, `iss` or `sub` |
/// | `app-check-token-expired` | the token has expired |
/// | `internal-error` | the public keys could not be fetched or read |
///
/// [message] never contains the token.
class FirebaseAppCheckAdminException extends FirebaseAdminException {
  /// Creates an exception with [code] and [message]. The package creates them; you need this only in tests.
  const FirebaseAppCheckAdminException({
    required super.code,
    required super.message,
    super.httpStatus,
  }) : super(plugin: 'app-check');
}
