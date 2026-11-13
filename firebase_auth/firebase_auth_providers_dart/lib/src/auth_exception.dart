/// Thrown when a Firebase Auth request fails.
class FirebaseAuthProviderException implements Exception {
  /// Creates an exception with the SDK style [code] (for example `wrong-password`).
  const FirebaseAuthProviderException(
    this.code,
    this.message, {
    this.serverCode,
    this.httpStatus,
  });

  /// Maps the error message of the Identity Toolkit or Secure Token API ([serverMessage], for example
  /// `EMAIL_EXISTS` or `WEAK_PASSWORD : Password should be at least 6 characters`) to an exception.
  factory FirebaseAuthProviderException.fromServer(
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
    final String code =
        _codes[serverCode] ??
        (serverCode.contains('API key not valid') ||
                serverCode.contains('API_KEY_INVALID')
            ? 'invalid-api-key'
            : 'internal-error');
    return FirebaseAuthProviderException(
      code,
      detail ?? _messages[code] ?? serverMessage,
      serverCode: serverCode,
      httpStatus: httpStatus,
    );
  }

  /// The error code in the style of the Firebase SDKs: `wrong-password`, `email-already-in-use`,
  /// `network-request-failed`, `internal-error`, ...
  final String code;

  /// A description of the error. It never contains a token or a password.
  final String message;

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

  static const Map<String, String> _codes = <String, String>{
    'EMAIL_EXISTS': 'email-already-in-use',
    'EMAIL_NOT_FOUND': 'user-not-found',
    'USER_NOT_FOUND': 'user-not-found',
    'INVALID_PASSWORD': 'wrong-password',
    'INVALID_LOGIN_CREDENTIALS': 'invalid-credential',
    'INVALID_EMAIL': 'invalid-email',
    'MISSING_EMAIL': 'missing-email',
    'MISSING_PASSWORD': 'missing-password',
    'WEAK_PASSWORD': 'weak-password',
    'USER_DISABLED': 'user-disabled',
    'TOO_MANY_ATTEMPTS_TRY_LATER': 'too-many-requests',
    'OPERATION_NOT_ALLOWED': 'operation-not-allowed',
    'ADMIN_ONLY_OPERATION': 'admin-restricted-operation',
    'INVALID_CUSTOM_TOKEN': 'invalid-custom-token',
    'MISSING_CUSTOM_TOKEN': 'invalid-custom-token',
    'CREDENTIAL_MISMATCH': 'custom-token-mismatch',
    'TOKEN_EXPIRED': 'user-token-expired',
    'INVALID_REFRESH_TOKEN': 'invalid-refresh-token',
    'MISSING_REFRESH_TOKEN': 'invalid-refresh-token',
    'INVALID_GRANT_TYPE': 'internal-error',
    'PROJECT_NOT_FOUND': 'project-not-found',
    'CONFIGURATION_NOT_FOUND': 'configuration-not-found',
    'QUOTA_EXCEEDED': 'quota-exceeded',
    'CREDENTIAL_TOO_OLD_LOGIN_AGAIN': 'requires-recent-login',
    'INVALID_ID_TOKEN': 'invalid-user-token',
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
  };

  @override
  String toString() => 'FirebaseAuthProviderException($code): $message';
}
