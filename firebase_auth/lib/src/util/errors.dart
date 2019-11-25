// File created by
// Lung Razvan <long1eu>
// on 23/11/2019

import 'package:firebase_internal/firebase_internal.dart';

/// The corresponding provider is disabled for this project.
class AdminOnlyOperation extends FirebaseAuthError {
  AdminOnlyOperation(int code, String message) : super(code, message);
}

/// The custom token corresponds to a different Firebase project.
class CredentialMismatch extends FirebaseAuthError {
  CredentialMismatch(int code, String message) : super(code, message);
}

/// The user's credential is no longer valid. The user must sign in again.
class CredentialTooOldLoginAgain extends FirebaseAuthError {
  CredentialTooOldLoginAgain(int code, String message) : super(code, message);
}

/// The email address is already in use by another account.
class EmailExists extends FirebaseAuthError {
  EmailExists(int code, String message) : super(code, message);
}

/// There is no user record corresponding to this identifier. The user may have been deleted.
class EmailNotFound extends FirebaseAuthError {
  EmailNotFound(int code, String message) : super(code, message);
}

/// The action code has expired.
class ExpiredOobCode extends FirebaseAuthError {
  ExpiredOobCode(int code, String message) : super(code, message);
}

/// This credential is already associated with a different user account.
class FederatedUserIdAlreadyLinked extends FirebaseAuthError {
  FederatedUserIdAlreadyLinked(int code, String message) : super(code, message);
}

/// The custom token format is incorrect or the token is invalid for some reason (e.g. expired, invalid signature etc.)
class InvalidCustomToken extends FirebaseAuthError {
  InvalidCustomToken(int code, String message) : super(code, message);
}

/// The email address is badly formatted.
class InvalidEmail extends FirebaseAuthError {
  InvalidEmail(int code, String message) : super(code, message);
}

/// the grant type specified is invalid.
class InvalidGrantType extends FirebaseAuthError {
  InvalidGrantType(int code, String message) : super(code, message);
}

/// The supplied auth credential is malformed or has expired.
class InvalidIdpResponse extends FirebaseAuthError {
  InvalidIdpResponse(int code, String message) : super(code, message);
}

/// The user's credential is no longer valid. The user must sign in again.
class InvalidIdToken extends FirebaseAuthError {
  InvalidIdToken(int code, String message) : super(code, message);
}

/// The action code is invalid. This can happen if the code is malformed, expired, or has already been used.
class InvalidOobCode extends FirebaseAuthError {
  InvalidOobCode(int code, String message) : super(code, message);
}

/// The password is invalid or the user does not have a password.
class InvalidPassword extends FirebaseAuthError {
  InvalidPassword(int code, String message) : super(code, message);
}

/// An invalid refresh token is provided.
class InvalidRefreshToken extends FirebaseAuthError {
  InvalidRefreshToken(int code, String message) : super(code, message);
}

/// No email provided.
class MissingEmail extends FirebaseAuthError {
  MissingEmail(int code, String message) : super(code, message);
}

/// No idToken provided.
class MissingIdToken extends FirebaseAuthError {
  MissingIdToken(int code, String message) : super(code, message);
}

/// No refresh token provided.
class MissingRefreshToken extends FirebaseAuthError {
  MissingRefreshToken(int code, String message) : super(code, message);
}

/// The corresponding provider is disabled for this project.
class OperationNotAllowed extends FirebaseAuthError {
  OperationNotAllowed(int code, String message) : super(code, message);
}

/// The user's credential is no longer valid. The user must sign in again.
class TokenExpired extends FirebaseAuthError {
  TokenExpired(int code, String message) : super(code, message);
}

/// We have blocked all requests from this device due to unusual activity. Try again later.
class TooManyAttemptsTryLater extends FirebaseAuthError {
  TooManyAttemptsTryLater(int code, String message) : super(code, message);
}

/// The user account has been disabled by an administrator.
class UserDisabled extends FirebaseAuthError {
  UserDisabled(int code, String message) : super(code, message);
}

/// There is no user record corresponding to this identifier. The user may have been deleted.
class UserNotFound extends FirebaseAuthError {
  UserNotFound(int code, String message) : super(code, message);
}

/// The password must be 6 characters long or more.
class WeakPassword extends FirebaseAuthError {
  WeakPassword(int code, String message) : super(code, message);
}

FirebaseAuthError getErrorFor(String errorName, int code, String message) {
  switch (errorName) {
    case 'ADMIN_ONLY_OPERATION':
      return AdminOnlyOperation(code, message);

    case 'CREDENTIAL_MISMATCH':
      return CredentialMismatch(code, message);

    case 'CREDENTIAL_TOO_OLD_LOGIN_AGAIN':
      return CredentialTooOldLoginAgain(code, message);

    case 'EMAIL_EXISTS':
      return EmailExists(code, message);

    case 'EMAIL_NOT_FOUND':
      return EmailNotFound(code, message);

    case 'EXPIRED_OOB_CODE':
      return ExpiredOobCode(code, message);

    case 'FEDERATED_USER_ID_ALREADY_LINKED':
      return FederatedUserIdAlreadyLinked(code, message);

    case 'INVALID_CUSTOM_TOKEN':
      return InvalidCustomToken(code, message);

    case 'INVALID_EMAIL':
      return InvalidEmail(code, message);

    case 'INVALID_GRANT_TYPE':
      return InvalidGrantType(code, message);

    case 'INVALID_IDP_RESPONSE':
      return InvalidIdpResponse(code, message);

    case 'INVALID_ID_TOKEN':
      return InvalidIdToken(code, message);

    case 'INVALID_OOB_CODE':
      return InvalidOobCode(code, message);

    case 'INVALID_PASSWORD':
      return InvalidPassword(code, message);

    case 'INVALID_REFRESH_TOKEN':
      return InvalidRefreshToken(code, message);

    case 'MISSING_EMAIL':
      return MissingEmail(code, message);

    case 'MISSING_ID_TOKEN':
      return MissingIdToken(code, message);

    case 'MISSING_REFRESH_TOKEN':
      return MissingRefreshToken(code, message);

    case 'OPERATION_NOT_ALLOWED':
      return OperationNotAllowed(code, message);

    case 'TOKEN_EXPIRED':
      return TokenExpired(code, message);

    case 'TOO_MANY_ATTEMPTS_TRY_LATER':
      return TooManyAttemptsTryLater(code, message);

    case 'USER_DISABLED':
      return UserDisabled(code, message);

    case 'USER_NOT_FOUND':
      return UserNotFound(code, message);

    case 'WEAK_PASSWORD':
      return WeakPassword(code, message);
  }

  return FirebaseAuthError(code, message);
}
