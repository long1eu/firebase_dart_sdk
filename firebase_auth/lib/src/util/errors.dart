part of firebase_auth;

class FirebaseAuthError extends FirebaseError {
  factory FirebaseAuthError(String name, String message) {
    switch (name) {
      case 'ERROR_INVALID_CUSTOM_TOKEN':
        return invalidCustomToken;
      case 'ERROR_CUSTOM_TOKEN_MISMATCH':
        return customTokenMismatch;
      case 'ERROR_INVALID_CREDENTIAL':
        return invalidCredential;
      case 'ERROR_USER_DISABLED':
        return userDisabled;
      case 'ERROR_OPERATION_NOT_ALLOWED':
        return operationNotAllowed;
      case 'ERROR_EMAIL_ALREADY_IN_USE':
        return emailAlreadyInUse;
      case 'ERROR_INVALID_EMAIL':
        return invalidEmail;
      case 'ERROR_WRONG_PASSWORD':
        return wrongPassword;
      case 'ERROR_TOO_MANY_REQUESTS':
        return tooManyRequests;
      case 'ERROR_USER_NOT_FOUND':
        return userNotFound;
      case 'ERROR_ACCOUNT_EXISTS_WITH_DIFFERENT_CREDENTIAL':
        return accountExistsWithDifferentCredential;
      case 'ERROR_REQUIRES_RECENT_LOGIN':
        return requiresRecentLogin;
      case 'ERROR_PROVIDER_ALREADY_LINKED':
        return providerAlreadyLinked;
      case 'ERROR_NO_SUCH_PROVIDER':
        return noSuchProvider;
      case 'ERROR_INVALID_USER_TOKEN':
        return invalidUserToken;
      case 'ERROR_NETWORK_REQUEST_FAILED':
        return networkError;
      case 'ERROR_USER_TOKEN_EXPIRED':
        return userTokenExpired;
      case 'ERROR_INVALID_API_KEY':
        return invalidAPIKey;
      case 'ERROR_USER_MISMATCH':
        return userMismatch;
      case 'ERROR_CREDENTIAL_ALREADY_IN_USE':
        return credentialAlreadyInUse;
      case 'ERROR_WEAK_PASSWORD':
        return weakPassword;
      case 'ERROR_APP_NOT_AUTHORIZED':
        return appNotAuthorized;
      case 'ERROR_EXPIRED_ACTION_CODE':
        return expiredActionCode;
      case 'ERROR_INVALID_ACTION_CODE':
        return invalidActionCode;
      case 'ERROR_INVALID_MESSAGE_PAYLOAD':
        return invalidMessagePayload;
      case 'ERROR_INVALID_SENDER':
        return invalidSender;
      case 'ERROR_INVALID_RECIPIENT_EMAIL':
        return invalidRecipientEmail;
      case 'ERROR_MISSING_EMAIL':
        return missingEmail;
      case 'ERROR_MISSING_IOS_BUNDLE_ID':
        return missingIosBundleID;
      case 'ERROR_MISSING_ANDROID_PKG_NAME':
        return missingAndroidPackageName;
      case 'ERROR_UNAUTHORIZED_DOMAIN':
        return unauthorizedDomain;
      case 'ERROR_INVALID_CONTINUE_URI':
        return invalidContinueURI;
      case 'ERROR_MISSING_CONTINUE_URI':
        return missingContinueURI;
      case 'ERROR_MISSING_PHONE_NUMBER':
        return missingPhoneNumber;
      case 'ERROR_INVALID_PHONE_NUMBER':
        return invalidPhoneNumber;
      case 'ERROR_MISSING_VERIFICATION_CODE':
        return missingVerificationCode;
      case 'ERROR_INVALID_VERIFICATION_CODE':
        return invalidVerificationCode;
      case 'ERROR_MISSING_VERIFICATION_ID':
        return missingVerificationID;
      case 'ERROR_INVALID_VERIFICATION_ID':
        return invalidVerificationID;
      case 'MISSING_APP_CREDENTIAL':
        return missingAppCredential;
      case 'INVALID_APP_CREDENTIAL':
        return invalidAppCredential;
      case 'ERROR_SESSION_EXPIRED':
        return sessionExpired;
      case 'ERROR_QUOTA_EXCEEDED':
        return quotaExceeded;
      case 'ERROR_MISSING_APP_TOKEN':
        return missingAppToken;
      case 'ERROR_NOTIFICATION_NOT_FORWARDED':
        return notificationNotForwarded;
      case 'ERROR_APP_NOT_VERIFIED':
        return appNotVerified;
      case 'ERROR_CAPTCHA_CHECK_FAILED':
        return captchaCheckFailed;
      case 'ERROR_WEB_CONTEXT_ALREADY_PRESENTED':
        return webContextAlreadyPresented;
      case 'ERROR_WEB_CONTEXT_CANCELLED':
        return webContextCancelled;
      case 'ERROR_APP_VERIFICATION_FAILED':
        return appVerificationUserInteractionFailure;
      case 'ERROR_INVALID_CLIENT_ID':
        return invalidClientID;
      case 'ERROR_WEB_NETWORK_REQUEST_FAILED':
        return webNetworkRequestFailed;
      case 'ERROR_WEB_INTERNAL_ERROR':
        return webInternalError;
      case 'ERROR_WEB_USER_INTERACTION_FAILURE':
        return webSignInUserInteractionFailure;
      case 'ERROR_LOCAL_PLAYER_NOT_AUTHENTICATED':
        return localPlayerNotAuthenticated;
      case 'ERROR_NULL_USER':
        return nullUser;
      case 'ERROR_DYNAMIC_LINK_NOT_ACTIVATED':
        return dynamicLinkNotActivated;
      case 'ERROR_INVALID_PROVIDER_ID':
        return invalidProviderID;
      case 'ERROR_INVALID_DYNAMIC_LINK_DOMAIN':
        return invalidDynamicLinkDomain;
      case 'ERROR_REJECTED_CREDENTIAL':
        return rejectedCredential;
      case 'ERROR_GAME_KIT_NOT_LINKED':
        return gameKitNotLinked;
      case 'ERROR_MISSING_OR_INVALID_NONCE':
        return missingOrInvalidNonce;
      case 'EMAIL_EXISTS':
        return emailExists;
      case 'ERROR_MISSING_CLIENT_IDENTIFIER':
        return missingClientIdentifier;
      case 'ERROR_KEYCHAIN_ERROR':
        return keychainError;
      case 'ERROR_INTERNAL_ERROR':
        return internalError;
      case 'ERROR_MALFORMED_JWT':
        return malformedJWT;
      default:
        return FirebaseAuthError._(-1, '$name${message.isEmpty ? '' : ' : $message'}');
    }
  }

  const FirebaseAuthError._(this.code, String message)
      : assert(code != null),
        super(message);

  final int code;

  /// Indicates a validation error with the custom token.
  static const FirebaseAuthError invalidCustomToken = FirebaseAuthError._(
    17000,
    'The custom token format is incorrect. Please check the documentation.',
  );

  /// Indicates the service account and the API key belong to different projects.
  static const FirebaseAuthError customTokenMismatch = FirebaseAuthError._(
    17002,
    'The custom token corresponds to a different audience.',
  );

  /// Indicates the IDP token or requestUri is invalid.
  static const FirebaseAuthError invalidCredential = FirebaseAuthError._(
    17004,
    'The supplied auth credential is malformed or has expired.',
  );

  /// Indicates the user's account is disabled on the server.
  static const FirebaseAuthError userDisabled = FirebaseAuthError._(
    17005,
    'The user account has been disabled by an administrator.',
  );

  /// Indicates the administrator disabled sign in with the specified identity provider.
  static const FirebaseAuthError operationNotAllowed = FirebaseAuthError._(
    17006,
    'The given sign-in provider is disabled for this Firebase project. Enable it in the Firebase console, under the sign-in method tab of the Auth section.',
  );

  /// Indicates the email used to attempt a sign up is already in use.
  static const FirebaseAuthError emailAlreadyInUse = FirebaseAuthError._(
    17007,
    'The email address is already in use by another account.',
  );

  /// Indicates the email is invalid.
  static const FirebaseAuthError invalidEmail = FirebaseAuthError._(
    17008,
    'The email address is badly formatted.',
  );

  /// Indicates the user attempted sign in with a wrong password.
  static const FirebaseAuthError wrongPassword = FirebaseAuthError._(
    17009,
    'The password is invalid or the user does not have a password.',
  );

  /// Indicates that too many requests were made to a server method.
  static const FirebaseAuthError tooManyRequests = FirebaseAuthError._(
    17010,
    'We have blocked all requests from this device due to unusual activity. Try again later.',
  );

  /// Indicates the user account was not found.
  static const FirebaseAuthError userNotFound = FirebaseAuthError._(
    17011,
    'There is no user record corresponding to this identifier. The user may have been deleted.',
  );

  /// Indicates account linking is required.
  static const FirebaseAuthError accountExistsWithDifferentCredential = FirebaseAuthError._(
    17012,
    'An account already exists with the same email address but different sign-in credentials. Sign in using a provider associated with this email address.',
  );

  /// Indicates the user has attempted to change email or password more than 5 minutes after signing in.
  static const FirebaseAuthError requiresRecentLogin = FirebaseAuthError._(
    17014,
    'This operation is sensitive and requires recent authentication. Log in again before retrying this request.',
  );

  /// Indicates an attempt to link a provider to which the account is already linked.
  static const FirebaseAuthError providerAlreadyLinked = FirebaseAuthError._(
    17015,
    '[ERROR_PROVIDER_ALREADY_LINKED] - User can only be linked to one identity for the given provider.',
  );

  /// Indicates an attempt to unlink a provider that is not linked.
  static const FirebaseAuthError noSuchProvider = FirebaseAuthError._(
    17016,
    'User was not linked to an account with the given provider.',
  );

  /// Indicates user's saved auth credential is invalid, the user needs to sign in again.
  static const FirebaseAuthError invalidUserToken = FirebaseAuthError._(
    17017,
    'This user\'s credential isn\'t valid for this project. This can happen if the user\'s token has been tampered with, or if the user doesn’t belong to the project associated with the API key used in your request.',
  );

  /// Indicates a network error occurred (such as a timeout, interrupted connection, or unreachable host). These types of errors are often recoverable with a retry. The `NSUnderlyingError` field in the `NSError.userInfo` dictionary will contain the error encountered.
  static const FirebaseAuthError networkError = FirebaseAuthError._(
    17020,
    'Network error (such as timeout, interrupted connection or unreachable host) has occurred.',
  );

  /// Indicates the saved token has expired, for example, the user may have changed account password on another device. The user needs to sign in again on the device that made this request.
  static const FirebaseAuthError userTokenExpired = FirebaseAuthError._(
    17021,
    'The user\'s credential is no longer valid. The user must sign in again.',
  );

  /// Indicates an invalid API key was supplied in the request.
  static const FirebaseAuthError invalidAPIKey = FirebaseAuthError._(
    17023,
    'An invalid API Key was supplied in the request.',
  );

  /// Indicates that an attempt was made to reauthenticate with a user which is not the current user.
  static const FirebaseAuthError userMismatch = FirebaseAuthError._(
    17024,
    'The supplied credentials do not correspond to the previously signed in user.',
  );

  /// Indicates an attempt to link with a credential that has already been linked with a different Firebase account
  static const FirebaseAuthError credentialAlreadyInUse = FirebaseAuthError._(
    17025,
    'This credential is already associated with a different user account.',
  );

  /// Indicates an attempt to set a password that is considered too weak.
  static const FirebaseAuthError weakPassword = FirebaseAuthError._(
    17026,
    'The password must be 6 characters long or more.',
  );

  /// Indicates the App is not authorized to use Firebase Authentication with the provided API Key.
  static const FirebaseAuthError appNotAuthorized = FirebaseAuthError._(
    17028,
    'This app is not authorized to use Firebase Authentication with the provided API key. Review your key configuration in the Google API console and ensure that it accepts requests from your app\'s bundle ID.',
  );

  /// Indicates the OOB code is expired.
  static const FirebaseAuthError expiredActionCode = FirebaseAuthError._(
    17029,
    'The action code has expired.',
  );

  /// Indicates the OOB code is invalid.
  static const FirebaseAuthError invalidActionCode = FirebaseAuthError._(
    17030,
    'The action code is invalid. This can happen if the code is malformed, expired, or has already been used.',
  );

  /// Indicates that there are invalid parameters in the payload during a "send password reset email" attempt.
  static const FirebaseAuthError invalidMessagePayload = FirebaseAuthError._(
    17031,
    'The action code is invalid. This can happen if the code is malformed, expired, or has already been used.',
  );

  /// Indicates that the sender email is invalid during a "send password reset email" attempt.
  static const FirebaseAuthError invalidSender = FirebaseAuthError._(
    17032,
    'The email template corresponding to this action contains invalid characters in its message. Please fix by going to the Auth email templates section in the Firebase Console.',
  );

  /// Indicates that the recipient email is invalid.
  static const FirebaseAuthError invalidRecipientEmail = FirebaseAuthError._(
    17033,
    'The action code is invalid. This can happen if the code is malformed, expired, or has already been used.',
  );

  /// Indicates that an email address was expected but one was not provided.
  static const FirebaseAuthError missingEmail = FirebaseAuthError._(
    17034,
    'An email address must be provided.',
  );

  /// Indicates that the iOS bundle ID is missing when a iOS App Store ID is provided.
  static const FirebaseAuthError missingIosBundleID = FirebaseAuthError._(
    17036,
    'An iOS Bundle ID must be provided if an App Store ID is provided.',
  );

  /// Indicates that the android package name is missing when the `androidInstallApp` flag is set to true.
  static const FirebaseAuthError missingAndroidPackageName = FirebaseAuthError._(
    17037,
    'An Android Package Name must be provided if the Android App is required to be installed.',
  );

  /// Indicates that the domain specified in the continue URL is not whitelisted in the Firebase console.
  static const FirebaseAuthError unauthorizedDomain = FirebaseAuthError._(
    17038,
    'The domain of the continue URL is not whitelisted. Please whitelist the domain in the Firebase console.',
  );

  /// Indicates that the domain specified in the continue URI is not valid.
  static const FirebaseAuthError invalidContinueURI = FirebaseAuthError._(
    17039,
    'The continue URL provided in the request is invalid.',
  );

  /// Indicates that a continue URI was not provided in a request to the backend which requires one.
  static const FirebaseAuthError missingContinueURI = FirebaseAuthError._(
    17040,
    'A continue URL must be provided in the request.',
  );

  /// Indicates that a phone number was not provided in a call to `verifyPhoneNumber:completion:`.
  static const FirebaseAuthError missingPhoneNumber = FirebaseAuthError._(
    17041,
    'To send verification codes, provide a phone number for the recipient.',
  );

  /// Indicates that an invalid phone number was provided in a call to `verifyPhoneNumber:completion:`.
  static const FirebaseAuthError invalidPhoneNumber = FirebaseAuthError._(
    17042,
    'The format of the phone number provided is incorrect. Please enter the phone number in a format that can be parsed into E.164 format. E.164 phone numbers are written in the format [+][country code][subscriber number including area code].',
  );

  /// Indicates that the phone auth credential was created with an empty verification code.
  static const FirebaseAuthError missingVerificationCode = FirebaseAuthError._(
    17043,
    'The phone auth credential was created with an empty SMS verification Code.',
  );

  /// Indicates that an invalid verification code was used in the verifyPhoneNumber request.
  static const FirebaseAuthError invalidVerificationCode = FirebaseAuthError._(
    17044,
    'The SMS verification code used to create the phone auth credential is invalid. Please resend the verification code SMS and be sure to use the verification code provided by the user.',
  );

  /// Indicates that the phone auth credential was created with an empty verification ID.
  static const FirebaseAuthError missingVerificationID = FirebaseAuthError._(
    17045,
    'The phone auth credential was created with an empty verification ID.',
  );

  /// Indicates that an invalid verification ID was used in the verifyPhoneNumber request.
  static const FirebaseAuthError invalidVerificationID = FirebaseAuthError._(
    17046,
    'The verification ID used to create the phone auth credential is invalid.',
  );

  /// Indicates that the APNS device token is missing in the verifyClient request.
  static const FirebaseAuthError missingAppCredential = FirebaseAuthError._(
    17047,
    'The phone verification request is missing an APNs Device token. Firebase Auth automatically detects APNs Device Tokens, however, if method swizzling is disabled, the APNs token must be set via the APNSToken property on FIRAuth or by calling setAPNSToken:type on FIRAuth.',
  );

  /// Indicates that an invalid APNS device token was used in the verifyClient request.
  static const FirebaseAuthError invalidAppCredential = FirebaseAuthError._(
    17048,
    'The APNs device token provided is either incorrect or does not match the private certificate uploaded to the Firebase Console.',
  );

  /// Indicates that the SMS code has expired.
  static const FirebaseAuthError sessionExpired = FirebaseAuthError._(
    17051,
    'The SMS code has expired. Please re-send the verification code to try again.',
  );

  /// Indicates that the quota of SMS messages for a given project has been exceeded.
  static const FirebaseAuthError quotaExceeded = FirebaseAuthError._(
    17052,
    'The phone verification quota for this project has been exceeded.',
  );

  /// Indicates that the APNs device token could not be obtained. The app may not have set up remote notification correctly, or may fail to forward the APNs device token to FIRAuth if app delegate swizzling is disabled.
  static const FirebaseAuthError missingAppToken = FirebaseAuthError._(
    17053,
    'There seems to be a problem with your project\'s Firebase phone number authentication set-up, please make sure to follow the instructions found at https://firebase.google.com/docs/auth/ios/phone-auth',
  );

  /// Indicates that the app fails to forward remote notification to FIRAuth.
  static const FirebaseAuthError notificationNotForwarded = FirebaseAuthError._(
    17054,
    'If app delegate swizzling is disabled, remote notifications received by UIApplicationDelegate need to be forwarded to FIRAuth\'s canHandleNotificaton: method.',
  );

  /// Indicates that the app could not be verified by Firebase during phone number authentication.
  static const FirebaseAuthError appNotVerified = FirebaseAuthError._(
    17055,
    'Firebase could not retrieve the silent push notification and therefore could not verify your app. Ensure that you configured your app correctly to receive push notifications.',
  );

  /// Indicates that the reCAPTCHA token is not valid.
  static const FirebaseAuthError captchaCheckFailed = FirebaseAuthError._(
    17056,
    'The reCAPTCHA response token provided is either invalid, expired or already',
  );

  /// Indicates that an attempt was made to present a new web context while one was already being presented.
  static const FirebaseAuthError webContextAlreadyPresented = FirebaseAuthError._(
    17057,
    'User interaction is still ongoing, another view cannot be presented.',
  );

  /// Indicates that the URL presentation was cancelled prematurely by the user.
  static const FirebaseAuthError webContextCancelled = FirebaseAuthError._(
    17058,
    'The interaction was cancelled by the user.',
  );

  /// Indicates a general failure during the app verification flow.
  static const FirebaseAuthError appVerificationUserInteractionFailure = FirebaseAuthError._(
    17059,
    'The app verification process has failed, print and inspect the error details for more information',
  );

  /// Indicates that the clientID used to invoke a web flow is invalid.
  static const FirebaseAuthError invalidClientID = FirebaseAuthError._(
    17060,
    'The OAuth client ID provided is either invalid or does not match the specified API key.',
  );

  /// Indicates that a network request within a SFSafariViewController or WKWebView failed.
  static const FirebaseAuthError webNetworkRequestFailed = FirebaseAuthError._(
    17061,
    'null',
  );

  /// Indicates that an internal error occurred within a SFSafariViewController or WKWebView.
  static const FirebaseAuthError webInternalError = FirebaseAuthError._(
    17062,
    'An internal error has occurred within the SFSafariViewController or WKWebView.',
  );

  /// Indicates a general failure during a web sign-in flow.
  static const FirebaseAuthError webSignInUserInteractionFailure = FirebaseAuthError._(
    17063,
    'null',
  );

  /// Indicates that the local player was not authenticated prior to attempting Game Center signin.
  static const FirebaseAuthError localPlayerNotAuthenticated = FirebaseAuthError._(
    17066,
    'The local player is not authenticated. Please log the local player in to Game Center.',
  );

  /// Indicates that a non-null user was expected as an argmument to the operation but a null user was provided.
  static const FirebaseAuthError nullUser = FirebaseAuthError._(
    17067,
    'A null user object was provided as the argument for an operation which requires a non-null user object.',
  );

  /// Indicates that a Firebase Dynamic Link is not activated.
  static const FirebaseAuthError dynamicLinkNotActivated = FirebaseAuthError._(
    17068,
    'Please activate Dynamic Links in the Firebase Console and agree to the terms and conditions.',
  );

  /// Represents the error code for when the given provider id for a web operation is invalid.
  static const FirebaseAuthError invalidProviderID = FirebaseAuthError._(
    17071,
    'The provider ID provided for the attempted web operation is invalid.',
  );

  /// Indicates that the Firebase Dynamic Link domain used is either not configured or is unauthorized for the current project.
  static const FirebaseAuthError invalidDynamicLinkDomain = FirebaseAuthError._(
    17074,
    'The Firebase Dynamic Link domain used is either not configured or is unauthorized for the current project.',
  );

  /// Indicates that the credential is rejected because it's misformed or mismatching.
  static const FirebaseAuthError rejectedCredential = FirebaseAuthError._(
    17075,
    'The request contains malformed or mismatching credentials.',
  );

  /// Indicates that the GameKit framework is not linked prior to attempting Game Center signin.
  static const FirebaseAuthError gameKitNotLinked = FirebaseAuthError._(
    17076,
    'The GameKit framework is not linked. Please turn on the Game Center capability.',
  );

  /// Indicates that the nonce is missing or invalid.
  static const FirebaseAuthError missingOrInvalidNonce = FirebaseAuthError._(
    17094,
    'The request contains malformed or mismatched credentials.',
  );

  /// Indicates the email used to attempt a sign up is already in use.
  static const FirebaseAuthError emailExists = FirebaseAuthError._(
    17992,
    'The email address is already in use, try to login.',
  );

  /// Indicates an error for when the client identifier is missing.
  static const FirebaseAuthError missingClientIdentifier = FirebaseAuthError._(
    17993,
    'The request does not contain any client identifier.',
  );

  /// Indicates an error occurred while attempting to access the keychain.
  static const FirebaseAuthError keychainError = FirebaseAuthError._(
    17995,
    'An error occurred when accessing the keychain. The @c NSLocalizedFailureReasonErrorKey field in the @c NSError.userInfo dictionary will contain more information about the error encountered',
  );

  /// Indicates an internal error occurred.
  static const FirebaseAuthError internalError = FirebaseAuthError._(
    17999,
    'An internal error has occurred, print and inspect the error details for more information.',
  );

  /// Raised when a JWT fails to parse correctly. May be accompanied by an underlying error describing which step of the JWT parsing process failed.
  static const FirebaseAuthError malformedJWT = FirebaseAuthError._(
    18000,
    'Failed to parse JWT. Check the userInfo dictionary for the full token.',
  );

  @override
  String toString() => 'FirebaseAuthError($code, $message)';
}
