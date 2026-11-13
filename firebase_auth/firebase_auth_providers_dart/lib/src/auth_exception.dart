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
    // Like the JS SDK (_performFetchWithErrorHandling): the codes of SERVER_ERROR_MAP, and any other code of the
    // backend in kebab case (`QUOTA_EXCEEDED` is `quota-exceeded`).
    final String code =
        _codes[serverCode] ??
        (serverCode.contains('API key not valid') ||
                serverCode.contains('API_KEY_INVALID')
            ? 'invalid-api-key'
            : serverCode.toLowerCase().replaceAll(RegExp(r'[_\s]+'), '-'));
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
  String toString() => 'FirebaseAuthProviderException($code): $message';
}
