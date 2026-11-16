// File created by
// Lung Razvan <long1eu>
// on 16/09/2018

/// The base class of the errors thrown by the Firebase SDKs of this repository.
///
/// `FirestoreError` of `cloud_firestore_dart` extends it. The subclasses below come from the Android
/// SDK; of them, token providers use [FirebaseNoSignedInUserException] and
/// [FirebaseApiNotAvailableException] to tell Firestore to send a request without a token.
///
/// ```dart
/// import 'package:firebase_app_dart/firebase_app_dart.dart';
///
/// void main() {
///   try {
///     throw const FirebaseNetworkError('The network is down.');
///   } on FirebaseError catch (e) {
///     print(e); // FirebaseNetworkError: The network is down.
///   }
/// }
/// ```
class FirebaseException implements Error {
  /// Creates an error with a [message] and, optionally, the stack trace of its origin.
  const FirebaseException(this.message, [this.stackTrace]);

  /// A description of what went wrong.
  final String message;

  /// The stack trace captured where the error originated, if any.
  @override
  final StackTrace? stackTrace;

  @override
  String toString() => '$runtimeType: $message';
}

/// Thrown by `InternalTokenProvider.getAccessToken` when nobody is signed in.
///
/// Firestore catches it and sends the request without a token, so the security rules see no
/// user. Throw it from a token provider of your own in that case; any other error fails the
/// request with `unauthenticated`.
///
/// ```dart
/// import 'package:firebase_app_dart/firebase_app_dart.dart';
///
/// Future<GetTokenResult> tokenOf(String? idToken) async {
///   if (idToken == null) {
///     throw FirebaseNoSignedInUserError('No user is signed in.');
///   }
///   return GetTokenResult(idToken);
/// }
/// ```
class FirebaseNoSignedInUserException extends FirebaseException {
  /// Creates the error with a [message].
  FirebaseNoSignedInUserException(super.message);
}

/// Thrown when a Firebase service or feature that an operation needs is not available.
///
/// When an auth or App Check token provider throws it, Firestore sends the request without that
/// token and logs nothing above the debug level.
///
/// ```dart
/// import 'package:firebase_app_dart/firebase_app_dart.dart';
///
/// const FirebaseApiNotAvailableError error = FirebaseApiNotAvailableError(
///   'App Check is not available.',
/// );
/// ```
class FirebaseApiNotAvailableException extends FirebaseException {
  /// Creates the error with a [message].
  const FirebaseApiNotAvailableException(super.message);
}

/// A request to a Firebase service failed because of the network. Kept from the Android SDK; no
/// package of this repository throws it.
///
/// ```dart
/// import 'package:firebase_app_dart/firebase_app_dart.dart';
///
/// const FirebaseNetworkError error = FirebaseNetworkError('Offline.');
/// ```
class FirebaseNetworkError extends FirebaseException {
  /// Creates the error with a [message].
  const FirebaseNetworkError(super.message);
}

/// A request to a Firebase service was refused because the device sent too many requests. Kept from
/// the Android SDK; no package of this repository throws it.
///
/// ```dart
/// import 'package:firebase_app_dart/firebase_app_dart.dart';
///
/// const FirebaseTooManyRequestsError error = FirebaseTooManyRequestsError(
///   'Try again later.',
/// );
/// ```
class FirebaseTooManyRequestsError extends FirebaseException {
  /// Creates the error with a [message].
  const FirebaseTooManyRequestsError(super.message);
}

/// The numeric error codes of the Firebase Auth Android SDK (`17000` to `17499`). Kept from the
/// original project; no package of this repository uses them. `firebase_auth_providers_dart`
/// reports errors with string codes (`FirebaseAuthProviderException.code`) instead.
///
/// ```dart
/// import 'package:firebase_app_dart/firebase_app_dart.dart';
///
/// void main() {
///   print(FirebaseApiError.errorWrongPassword.errorCode); // 17009
/// }
/// ```
class FirebaseApiError {
  /// Creates an error with the given numeric code.
  const FirebaseApiError(this.errorCode);

  /// The numeric code of this error.
  final int errorCode;

  /// The custom token is malformed or its signature is invalid (17000).
  static const FirebaseApiError errorInvalidCustomToken = FirebaseApiError(
    17000,
  );

  /// The custom token belongs to a different project (17002).
  static const FirebaseApiError errorCustomTokenMismatch = FirebaseApiError(
    17002,
  );

  /// The credential is malformed or has expired (17004).
  static const FirebaseApiError errorInvalidCredential = FirebaseApiError(
    17004,
  );

  /// The user account has been disabled (17005).
  static const FirebaseApiError errorUserDisabled = FirebaseApiError(17005);

  /// The sign-in method is not enabled for the project (17006).
  static const FirebaseApiError errorOperationNotAllowed = FirebaseApiError(
    17006,
  );

  /// The email address is already used by another account (17007).
  static const FirebaseApiError errorEmailAlreadyInUse = FirebaseApiError(
    17007,
  );

  /// The email address is malformed (17008).
  static const FirebaseApiError errorInvalidEmail = FirebaseApiError(17008);

  /// The password is wrong (17009).
  static const FirebaseApiError errorWrongPassword = FirebaseApiError(17009);

  /// Too many requests were made; try again later (17010).
  static const FirebaseApiError errorTooManyRequests = FirebaseApiError(17010);

  /// There is no user with this identifier (17011).
  static const FirebaseApiError errorUserNotFound = FirebaseApiError(17011);

  /// An account exists with the same email address but another sign-in method (17012).
  static const FirebaseApiError errorAccountExistsWithDifferentCredential =
      FirebaseApiError(17012);

  /// The operation needs a recent sign-in (17014).
  static const FirebaseApiError errorRequiresRecentLogin = FirebaseApiError(
    17014,
  );

  /// The provider is already linked to the account (17015).
  static const FirebaseApiError errorProviderAlreadyLinked = FirebaseApiError(
    17015,
  );

  /// The provider is not linked to the account (17016).
  static const FirebaseApiError errorNoSuchProvider = FirebaseApiError(17016);

  /// The credential of the user is no longer valid (17017).
  static const FirebaseApiError errorInvalidUserToken = FirebaseApiError(17017);

  /// A network request failed (17020).
  static const FirebaseApiError errorNetworkRequestFailed = FirebaseApiError(
    17020,
  );

  /// The credential of the user has expired; sign in again (17021).
  static const FirebaseApiError errorUserTokenExpired = FirebaseApiError(17021);

  /// The API key is not valid (17023).
  static const FirebaseApiError errorInvalidApiKey = FirebaseApiError(17023);

  /// The credential belongs to another user than the signed-in one (17024).
  static const FirebaseApiError errorUserMismatch = FirebaseApiError(17024);

  /// The credential is already linked to another account (17025).
  static const FirebaseApiError errorCredentialAlreadyInUse = FirebaseApiError(
    17025,
  );

  /// The password is too weak (17026).
  static const FirebaseApiError errorWeakPassword = FirebaseApiError(17026);

  /// The app is not authorized to use the API key (17028).
  static const FirebaseApiError errorAppNotAuthorized = FirebaseApiError(17028);

  /// No user is signed in (17495).
  static const FirebaseApiError errorNoSignedInUser = FirebaseApiError(17495);

  /// An error of the backend (17499).
  static const FirebaseApiError errorInternalError = FirebaseApiError(17499);
}
