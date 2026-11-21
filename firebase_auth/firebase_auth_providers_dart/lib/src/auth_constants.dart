// The string constants of the JS SDK's ProviderId, SignInMethod, FactorId and AuthErrorCodes
// (`packages/auth/src/model/enum_maps.ts`, `packages/auth/src/core/errors.ts`).

import 'auth_credential.dart';
import 'auth_exception.dart';
import 'auth_user.dart';
import 'firebase_user_auth.dart';
import 'multi_factor.dart';

/// The ids of the providers ([AuthCredential.providerId], [UserInfo.providerId]) of the sign-in methods this client
/// supports, plus `phone`, which accounts made with the other SDKs can have (`ProviderId` of the JS SDK, which has
/// Facebook, GitHub, Google, password, phone and Twitter).
abstract final class ProviderId {
  /// `apple.com`.
  static const String apple = 'apple.com';

  /// `facebook.com`.
  static const String facebook = 'facebook.com';

  /// `github.com`.
  static const String github = 'github.com';

  /// `google.com`.
  static const String google = 'google.com';

  /// `microsoft.com`.
  static const String microsoft = 'microsoft.com';

  /// `password`: email and password, and email link.
  static const String password = 'password';

  /// `phone`. This client cannot sign in with a phone number; the id appears in the provider data of accounts
  /// that did elsewhere.
  static const String phone = 'phone';

  /// `twitter.com`.
  static const String twitter = 'twitter.com';

  /// `yahoo.com`.
  static const String yahoo = 'yahoo.com';
}

/// The sign-in methods ([AuthCredential.signInMethod], [FirebaseUserAuth.fetchSignInMethodsForEmail]) (`SignInMethod`
/// of the JS SDK). For a provider of [ProviderId] the method is the provider id; email and password differ.
abstract final class SignInMethod {
  /// `apple.com`.
  static const String apple = 'apple.com';

  /// `emailLink`: an email link of [FirebaseUserAuth.sendSignInLinkToEmail].
  static const String emailLink = 'emailLink';

  /// `password`: an email and a password.
  static const String emailPassword = 'password';

  /// `facebook.com`.
  static const String facebook = 'facebook.com';

  /// `github.com`.
  static const String github = 'github.com';

  /// `google.com`.
  static const String google = 'google.com';

  /// `microsoft.com`.
  static const String microsoft = 'microsoft.com';

  /// `phone`.
  static const String phone = 'phone';

  /// `twitter.com`.
  static const String twitter = 'twitter.com';

  /// `yahoo.com`.
  static const String yahoo = 'yahoo.com';
}

/// The kinds of second factor ([MultiFactorInfo.factorId]) (`FactorId` of the JS SDK).
abstract final class FactorId {
  /// `phone`: an SMS code.
  static const String phone = 'phone';

  /// `totp`: an authenticator app.
  static const String totp = 'totp';
}

/// The values of [FirebaseAuthException.code], as constants, so that a typo is a compile error
/// (`AuthErrorCodes` of the JS SDK, without the `auth/` prefix).
///
/// The first group is every code of the JS SDK, from `AUTH_ERROR_CODES_MAP_DO_NOT_USE_INTERNALLY` of
/// `packages/auth/src/core/errors.ts`; this client emits only part of them (the browser, phone and reCAPTCHA ones
/// never). The second group is the codes only this client has.
///
/// ```dart
/// try {
///   await auth.signInWithEmailAndPassword(email: email, password: password);
/// } on FirebaseAuthException catch (e) {
///   if (e.code == AuthErrorCode.invalidCredential) {
///     print('Wrong email or password.');
///   }
/// }
/// ```
abstract final class AuthErrorCode {
  /// `account-exists-with-different-credential`.
  static const String accountExistsWithDifferentCredential =
      'account-exists-with-different-credential';

  /// `admin-restricted-operation`.
  static const String adminRestrictedOperation = 'admin-restricted-operation';

  /// `already-initialized`.
  static const String alreadyInitialized = 'already-initialized';

  /// `app-deleted`.
  static const String appDeleted = 'app-deleted';

  /// `app-not-authorized`.
  static const String appNotAuthorized = 'app-not-authorized';

  /// `app-not-installed`.
  static const String appNotInstalled = 'app-not-installed';

  /// `argument-error`.
  static const String argumentError = 'argument-error';

  /// `auth-domain-config-required`.
  static const String authDomainConfigRequired = 'auth-domain-config-required';

  /// `cancelled-popup-request`.
  static const String cancelledPopupRequest = 'cancelled-popup-request';

  /// `captcha-check-failed`.
  static const String captchaCheckFailed = 'captcha-check-failed';

  /// `code-expired`.
  static const String codeExpired = 'code-expired';

  /// `cordova-not-ready`.
  static const String cordovaNotReady = 'cordova-not-ready';

  /// `cors-unsupported`.
  static const String corsUnsupported = 'cors-unsupported';

  /// `credential-already-in-use`.
  static const String credentialAlreadyInUse = 'credential-already-in-use';

  /// `custom-token-mismatch`.
  static const String customTokenMismatch = 'custom-token-mismatch';

  /// `dependent-sdk-initialized-before-auth`.
  static const String dependentSdkInitializedBeforeAuth =
      'dependent-sdk-initialized-before-auth';

  /// `dynamic-link-not-activated`.
  static const String dynamicLinkNotActivated = 'dynamic-link-not-activated';

  /// `email-already-in-use`.
  static const String emailAlreadyInUse = 'email-already-in-use';

  /// `email-change-needs-verification`.
  static const String emailChangeNeedsVerification =
      'email-change-needs-verification';

  /// `emulator-config-failed`.
  static const String emulatorConfigFailed = 'emulator-config-failed';

  /// `expired-action-code`.
  static const String expiredActionCode = 'expired-action-code';

  /// `internal-error`.
  static const String internalError = 'internal-error';

  /// `invalid-action-code`.
  static const String invalidActionCode = 'invalid-action-code';

  /// `invalid-api-key`.
  static const String invalidApiKey = 'invalid-api-key';

  /// `invalid-app-credential`.
  static const String invalidAppCredential = 'invalid-app-credential';

  /// `invalid-app-id`.
  static const String invalidAppId = 'invalid-app-id';

  /// `invalid-auth-event`.
  static const String invalidAuthEvent = 'invalid-auth-event';

  /// `invalid-cert-hash`.
  static const String invalidCertHash = 'invalid-cert-hash';

  /// `invalid-continue-uri`.
  static const String invalidContinueUri = 'invalid-continue-uri';

  /// `invalid-cordova-configuration`.
  static const String invalidCordovaConfiguration =
      'invalid-cordova-configuration';

  /// `invalid-credential`.
  static const String invalidCredential = 'invalid-credential';

  /// `invalid-custom-token`.
  static const String invalidCustomToken = 'invalid-custom-token';

  /// `invalid-dynamic-link-domain`.
  static const String invalidDynamicLinkDomain = 'invalid-dynamic-link-domain';

  /// `invalid-email`.
  static const String invalidEmail = 'invalid-email';

  /// `invalid-emulator-scheme`.
  static const String invalidEmulatorScheme = 'invalid-emulator-scheme';

  /// `invalid-hosting-link-domain`.
  static const String invalidHostingLinkDomain = 'invalid-hosting-link-domain';

  /// `invalid-message-payload`.
  static const String invalidMessagePayload = 'invalid-message-payload';

  /// `invalid-multi-factor-session`.
  static const String invalidMultiFactorSession =
      'invalid-multi-factor-session';

  /// `invalid-oauth-client-id`.
  static const String invalidOauthClientId = 'invalid-oauth-client-id';

  /// `invalid-oauth-provider`.
  static const String invalidOauthProvider = 'invalid-oauth-provider';

  /// `invalid-persistence-type`.
  static const String invalidPersistenceType = 'invalid-persistence-type';

  /// `invalid-phone-number`.
  static const String invalidPhoneNumber = 'invalid-phone-number';

  /// `invalid-provider-id`.
  static const String invalidProviderId = 'invalid-provider-id';

  /// `invalid-recaptcha-action`.
  static const String invalidRecaptchaAction = 'invalid-recaptcha-action';

  /// `invalid-recaptcha-token`.
  static const String invalidRecaptchaToken = 'invalid-recaptcha-token';

  /// `invalid-recaptcha-version`.
  static const String invalidRecaptchaVersion = 'invalid-recaptcha-version';

  /// `invalid-recipient-email`.
  static const String invalidRecipientEmail = 'invalid-recipient-email';

  /// `invalid-req-type`.
  static const String invalidReqType = 'invalid-req-type';

  /// `invalid-sender`.
  static const String invalidSender = 'invalid-sender';

  /// `invalid-tenant-id`.
  static const String invalidTenantId = 'invalid-tenant-id';

  /// `invalid-user-token`.
  static const String invalidUserToken = 'invalid-user-token';

  /// `invalid-verification-code`.
  static const String invalidVerificationCode = 'invalid-verification-code';

  /// `invalid-verification-id`.
  static const String invalidVerificationId = 'invalid-verification-id';

  /// `maximum-second-factor-count-exceeded`.
  static const String maximumSecondFactorCountExceeded =
      'maximum-second-factor-count-exceeded';

  /// `missing-android-pkg-name`.
  static const String missingAndroidPkgName = 'missing-android-pkg-name';

  /// `missing-app-credential`.
  static const String missingAppCredential = 'missing-app-credential';

  /// `missing-client-type`.
  static const String missingClientType = 'missing-client-type';

  /// `missing-continue-uri`.
  static const String missingContinueUri = 'missing-continue-uri';

  /// `missing-iframe-start`.
  static const String missingIframeStart = 'missing-iframe-start';

  /// `missing-ios-bundle-id`.
  static const String missingIosBundleId = 'missing-ios-bundle-id';

  /// `missing-multi-factor-info`.
  static const String missingMultiFactorInfo = 'missing-multi-factor-info';

  /// `missing-multi-factor-session`.
  static const String missingMultiFactorSession =
      'missing-multi-factor-session';

  /// `missing-or-invalid-nonce`.
  static const String missingOrInvalidNonce = 'missing-or-invalid-nonce';

  /// `missing-password`.
  static const String missingPassword = 'missing-password';

  /// `missing-phone-number`.
  static const String missingPhoneNumber = 'missing-phone-number';

  /// `missing-recaptcha-token`.
  static const String missingRecaptchaToken = 'missing-recaptcha-token';

  /// `missing-recaptcha-version`.
  static const String missingRecaptchaVersion = 'missing-recaptcha-version';

  /// `missing-verification-code`.
  static const String missingVerificationCode = 'missing-verification-code';

  /// `missing-verification-id`.
  static const String missingVerificationId = 'missing-verification-id';

  /// `multi-factor-auth-required`.
  static const String multiFactorAuthRequired = 'multi-factor-auth-required';

  /// `multi-factor-info-not-found`.
  static const String multiFactorInfoNotFound = 'multi-factor-info-not-found';

  /// `network-request-failed`.
  static const String networkRequestFailed = 'network-request-failed';

  /// `no-auth-event`.
  static const String noAuthEvent = 'no-auth-event';

  /// `no-such-provider`.
  static const String noSuchProvider = 'no-such-provider';

  /// `null-user`.
  static const String nullUser = 'null-user';

  /// `operation-not-allowed`.
  static const String operationNotAllowed = 'operation-not-allowed';

  /// `operation-not-supported-in-this-environment`.
  static const String operationNotSupportedInThisEnvironment =
      'operation-not-supported-in-this-environment';

  /// `popup-blocked`.
  static const String popupBlocked = 'popup-blocked';

  /// `popup-closed-by-user`.
  static const String popupClosedByUser = 'popup-closed-by-user';

  /// `provider-already-linked`.
  static const String providerAlreadyLinked = 'provider-already-linked';

  /// `quota-exceeded`.
  static const String quotaExceeded = 'quota-exceeded';

  /// `recaptcha-not-enabled`.
  static const String recaptchaNotEnabled = 'recaptcha-not-enabled';

  /// `redirect-cancelled-by-user`.
  static const String redirectCancelledByUser = 'redirect-cancelled-by-user';

  /// `redirect-operation-pending`.
  static const String redirectOperationPending = 'redirect-operation-pending';

  /// `rejected-credential`.
  static const String rejectedCredential = 'rejected-credential';

  /// `requires-recent-login`.
  static const String requiresRecentLogin = 'requires-recent-login';

  /// `second-factor-already-in-use`.
  static const String secondFactorAlreadyInUse = 'second-factor-already-in-use';

  /// `tenant-id-mismatch`.
  static const String tenantIdMismatch = 'tenant-id-mismatch';

  /// `timeout`.
  static const String timeout = 'timeout';

  /// `too-many-requests`.
  static const String tooManyRequests = 'too-many-requests';

  /// `unauthorized-continue-uri`.
  static const String unauthorizedContinueUri = 'unauthorized-continue-uri';

  /// `unauthorized-domain`.
  static const String unauthorizedDomain = 'unauthorized-domain';

  /// `unsupported-first-factor`.
  static const String unsupportedFirstFactor = 'unsupported-first-factor';

  /// `unsupported-persistence-type`.
  static const String unsupportedPersistenceType =
      'unsupported-persistence-type';

  /// `unsupported-tenant-operation`.
  static const String unsupportedTenantOperation =
      'unsupported-tenant-operation';

  /// `unverified-email`.
  static const String unverifiedEmail = 'unverified-email';

  /// `user-cancelled`.
  static const String userCancelled = 'user-cancelled';

  /// `user-disabled`.
  static const String userDisabled = 'user-disabled';

  /// `user-mismatch`.
  static const String userMismatch = 'user-mismatch';

  /// `user-not-found`.
  static const String userNotFound = 'user-not-found';

  /// `user-signed-out`.
  static const String userSignedOut = 'user-signed-out';

  /// `user-token-expired`.
  static const String userTokenExpired = 'user-token-expired';

  /// `weak-password`.
  static const String weakPassword = 'weak-password';

  /// `web-storage-unsupported`.
  static const String webStorageUnsupported = 'web-storage-unsupported';

  /// `wrong-password`.
  static const String wrongPassword = 'wrong-password';

  // Codes of this client that the JS SDK does not have.

  /// `cancelled`: An operation that a later sign-in or a sign-out overtook.
  static const String cancelled = 'cancelled';

  /// `invalid-oauth-response`: The OAuth provider answered the loopback flow with something unusable.
  static const String invalidOauthResponse = 'invalid-oauth-response';

  /// `login-blocked`: A `beforeAuthStateChanged` callback refused the new user.
  static const String loginBlocked = 'login-blocked';

  /// `password-does-not-meet-requirements`: The password does not meet the password policy of the project.
  static const String passwordDoesNotMeetRequirements =
      'password-does-not-meet-requirements';

  /// `unsupported-password-policy-schema-version`: The project's password policy has a schema this client does not know.
  static const String unsupportedPasswordPolicySchemaVersion =
      'unsupported-password-policy-schema-version';
}
