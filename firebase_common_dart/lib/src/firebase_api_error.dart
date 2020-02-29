// File created by
// Lung Razvan <long1eu>
// on 16/09/2018

/// Represents API errors. This is for internal usage only and we don't expose
/// externally.

class FirebaseApiError {
  const FirebaseApiError(this.errorCode);

  final int errorCode;

  /// Firebase auth specific error codes.
  /// bring your own auth error codes.
  static const FirebaseApiError errorInvalidCustomToken = FirebaseApiError(17000);

  static const FirebaseApiError errorCustomTokenMismatch = FirebaseApiError(17002);

  /// sign in with credential error codes.
  static const FirebaseApiError errorInvalidCredential = FirebaseApiError(17004);

  static const FirebaseApiError errorUserDisabled = FirebaseApiError(17005);

  /// set account info error codes.
  static const FirebaseApiError errorOperationNotAllowed = FirebaseApiError(17006);

  static const FirebaseApiError errorEmailAlreadyInUse = FirebaseApiError(17007);

  /* sign in with password error codes*/
  static const FirebaseApiError errorInvalidEmail = FirebaseApiError(17008);

  static const FirebaseApiError errorWrongPassword = FirebaseApiError(17009);

  static const FirebaseApiError errorTooManyRequests = FirebaseApiError(17010);

  /// send password request email error codes
  static const FirebaseApiError errorUserNotFound = FirebaseApiError(17011);

  /// sign in with credential error codes.
  static const FirebaseApiError errorAccountExistsWithDifferentCredential = FirebaseApiError(17012);

  /// set account info error codes.
  static const FirebaseApiError errorRequiresRecentLogin = FirebaseApiError(17014);

  /// link credential error codes
  static const FirebaseApiError errorProviderAlreadyLinked = FirebaseApiError(17015);

  /// unlink credential
  static const FirebaseApiError errorNoSuchProvider = FirebaseApiError(17016);

  /// STS codes, any request with STS id token
  static const FirebaseApiError errorInvalidUserToken = FirebaseApiError(17017);

  /// network request failed
  static const FirebaseApiError errorNetworkRequestFailed = FirebaseApiError(17020);

  /// STS code
  static const FirebaseApiError errorUserTokenExpired = FirebaseApiError(17021);

  /// For GmsCore implementation on physical device, Droid Guard takes care of
  /// mapping api key. So for now, we are not handling this (2016 v3 release)
  static const FirebaseApiError errorInvalidApiKey = FirebaseApiError(17023);

  /// re-auth error codes
  static const FirebaseApiError errorUserMismatch = FirebaseApiError(17024);

  /// setAccountInfo(...) error codes.
  static const FirebaseApiError errorCredentialAlreadyInUse = FirebaseApiError(17025);

  /// weak passwords
  static const FirebaseApiError errorWeakPassword = FirebaseApiError(17026);

  /// For GmsCore implementation on physical device, Droid Guard takes care of
  /// mapping api key. So for now, we are not handling this (2016 v3 release)
  static const FirebaseApiError errorAppNotAuthorized = FirebaseApiError(17028);

  /// Internal api usage error codes (no signed-in user, and getAccessToken is
  /// called). This will map to ApiNotAvailableException and please
  /// DO NOT REUSE.
  static const FirebaseApiError errorNoSignedInUser = FirebaseApiError(17495);

  /// General backend error.
  static const FirebaseApiError errorInternalError = FirebaseApiError(17499);
}
