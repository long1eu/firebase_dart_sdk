// File created by
// Lung Razvan <long1eu>
// on 16/09/2018

class FirebaseError extends Error {
  FirebaseError(this.message) : assert(message != null, 'Detail message must not be empty.');

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Internal use only, indicates that no signed-in user and operations like
/// [InternalTokenProvider.getAccessToken] will fail.
class FirebaseNoSignedInUserError extends FirebaseError {
  FirebaseNoSignedInUserError(String message) : super(message);
}

class FirebaseApiNotAvailableError extends FirebaseError {
  FirebaseApiNotAvailableError(String message) : super(message);
}

/// Exception thrown when a request to a Firebase service has failed due to a
/// network error. Inspect the device's network connectivity state or retry
/// later to resolve.
class FirebaseNetworkError extends FirebaseError {
  FirebaseNetworkError(String message) : super(message);
}

/// Exception thrown when a request to a Firebase service has been blocked due
/// to having received too many consecutive requests from the same device. Retry
/// the request later to resolve.
class FirebaseTooManyRequestsError extends FirebaseError {
  FirebaseTooManyRequestsError(String message) : super(message);
}

/// Represents API errors. This is for internal usage only and we don't expose
/// externally.
class FirebaseApiError extends Error {
  FirebaseApiError(this.errorCode);

  final int errorCode;

  /// Firebase auth specific error codes.
  /// bring your own auth error codes.
  static final FirebaseApiError errorInvalidCustomToken = FirebaseApiError(17000);

  static final FirebaseApiError errorCustomTokenMismatch = FirebaseApiError(17002);

  /// sign in with credential error codes.
  static final FirebaseApiError errorInvalidCredential = FirebaseApiError(17004);

  static final FirebaseApiError errorUserDisabled = FirebaseApiError(17005);

  /// set account info error codes.
  static final FirebaseApiError errorOperationNotAllowed = FirebaseApiError(17006);

  static final FirebaseApiError errorEmailAlreadyInUse = FirebaseApiError(17007);

  /* sign in with password error codes*/
  static final FirebaseApiError errorInvalidEmail = FirebaseApiError(17008);

  static final FirebaseApiError errorWrongPassword = FirebaseApiError(17009);

  static final FirebaseApiError errorTooManyRequests = FirebaseApiError(17010);

  /// send password request email error codes
  static final FirebaseApiError errorUserNotFound = FirebaseApiError(17011);

  /// sign in with credential error codes.
  static final FirebaseApiError errorAccountExistsWithDifferentCredential = FirebaseApiError(17012);

  /// set account info error codes.
  static final FirebaseApiError errorRequiresRecentLogin = FirebaseApiError(17014);

  /// link credential error codes
  static final FirebaseApiError errorProviderAlreadyLinked = FirebaseApiError(17015);

  /// unlink credential
  static final FirebaseApiError errorNoSuchProvider = FirebaseApiError(17016);

  /// STS codes, any request with STS id token
  static final FirebaseApiError errorInvalidUserToken = FirebaseApiError(17017);

  /// network request failed
  static final FirebaseApiError errorNetworkRequestFailed = FirebaseApiError(17020);

  /// STS code
  static final FirebaseApiError errorUserTokenExpired = FirebaseApiError(17021);

  /// For GmsCore implementation on physical device, Droid Guard takes care of
  /// mapping api key. So for now, we are not handling this (2016 v3 release)
  static final FirebaseApiError errorInvalidApiKey = FirebaseApiError(17023);

  /// re-auth error codes
  static final FirebaseApiError errorUserMismatch = FirebaseApiError(17024);

  /// setAccountInfo(...) error codes.
  static final FirebaseApiError errorCredentialAlreadyInUse = FirebaseApiError(17025);

  /// weak passwords
  static final FirebaseApiError errorWeakPassword = FirebaseApiError(17026);

  /// For GmsCore implementation on physical device, Droid Guard takes care of
  /// mapping api key. So for now, we are not handling this (2016 v3 release)
  static final FirebaseApiError errorAppNotAuthorized = FirebaseApiError(17028);

  /// Internal api usage error codes (no signed-in user, and getAccessToken is
  /// called). This will map to ApiNotAvailableException and please
  /// DO NOT REUSE.
  static final FirebaseApiError errorNoSignedInUser = FirebaseApiError(17495);

  /// General backend error.
  static final FirebaseApiError errorInternalError = FirebaseApiError(17499);
}
