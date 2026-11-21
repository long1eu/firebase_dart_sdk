import 'dart:async';

import 'package:secure_flow/secure_flow.dart';

import 'auth_exception.dart';
import 'secure_flow_errors.dart';

/// The proof that a phone request comes from a real app, sent with
/// `accounts:sendVerificationCode` and the start of an SMS second factor.
///
/// One of three shapes:
///
/// * [RecaptchaV2Verification]: a reCAPTCHA v2 token, from a `RecaptchaFlow` of
///   `package:secure_flow` ([AppVerification.recaptchaV2Loopback]: a page on localhost in a
///   browser, or the widget in the app's own page on the web) or from a source of yours
///   ([AppVerification.recaptchaV2]: a WebView, a backend step).
/// * [RecaptchaEnterpriseVerification]: a reCAPTCHA Enterprise token from a source of yours. The
///   same type is the Enterprise token source of a whole client (`FirebaseUserAuth`'s
///   `recaptchaEnterprise`), used where the project's reCAPTCHA configuration asks for a token.
/// * [NoAppVerification]: no proof, for the Auth emulator and the test phone numbers of a project.
///
/// The token sources receive a request object ([RecaptchaV2Request], [RecaptchaEnterpriseRequest])
/// rather than bare values, so that what the client learns later (the Enterprise site key of
/// `v2/recaptchaConfig`) can be handed to them without changing their type.
sealed class AppVerification {
  const AppVerification();

  /// A reCAPTCHA v2 token from [token], which is called once per request with the site key of the
  /// project. See [RecaptchaV2Verification].
  const factory AppVerification.recaptchaV2(RecaptchaV2TokenSource token) =
      RecaptchaV2Verification;

  /// A reCAPTCHA v2 token from a [RecaptchaFlow] of `package:secure_flow`: a page with the
  /// reCAPTCHA v2 checkbox served on `http://localhost:<port>`, which [presenter] shows (when null,
  /// the presenter of [environment] that the flow ranks best: on the web the widget in the app's
  /// own page (`InPageRecaptchaPresenter`), else a web view or in-app browser the app registered,
  /// the system browser on a desktop, the URL on stderr in a terminal). The site key and the
  /// language are those of the request.
  ///
  /// The token source throws a [FirebaseAuthException]: `timeout` when no token came back within
  /// [timeout], `operation-not-supported-in-this-environment` when the environment offers no
  /// presenter ([SecureFlowNoPresenter]), `argument-error` when the flow refuses [presenter]
  /// ([SecureFlowRefused]), each with the original error as [FirebaseAuthException.cause]
  /// (not for `timeout`). A `RecaptchaFailure` of the in-page widget becomes `internal-error`
  /// (Google's script did not load), `network-request-failed` (it did not load in time, or the
  /// widget reported an error) or `missing-app-credential` (no token). Another error of the
  /// presenter is rethrown as it is.
  factory AppVerification.recaptchaV2Loopback({
    SecurePresenter? presenter,
    SecureEnvironment? environment,
    Duration timeout = const Duration(minutes: 5),
  }) => RecaptchaV2Verification(
    (RecaptchaV2Request request) => runSecureFlow<String>(
      RecaptchaFlow(
        siteKey: request.siteKey,
        languageCode: request.languageCode,
      ),
      presenter: presenter,
      environment: environment,
      timeout: timeout,
      timeoutMessage:
          'No reCAPTCHA token came back within ${timeout.inSeconds} seconds.',
    ),
  );

  /// A reCAPTCHA Enterprise token from [token], made for [clientType]. See
  /// [RecaptchaEnterpriseVerification].
  const factory AppVerification.recaptchaEnterprise(
    RecaptchaEnterpriseTokenSource token, {
    RecaptchaClientType clientType,
  }) = RecaptchaEnterpriseVerification;

  /// No proof. See [NoAppVerification].
  const factory AppVerification.none() = NoAppVerification;
}

/// Returns a reCAPTCHA v2 token for [RecaptchaV2Request.siteKey].
typedef RecaptchaV2TokenSource =
    FutureOr<String> Function(RecaptchaV2Request request);

/// Returns a reCAPTCHA Enterprise token for [RecaptchaEnterpriseRequest.action].
typedef RecaptchaEnterpriseTokenSource =
    FutureOr<String> Function(RecaptchaEnterpriseRequest request);

/// A reCAPTCHA v2 token, sent as `recaptchaToken`.
///
/// [token] is called once for each request that needs a proof, with the site key that
/// `v1/recaptchaParams` returns for the project; a token is good for one request.
final class RecaptchaV2Verification extends AppVerification {
  /// A token from [token].
  const RecaptchaV2Verification(this.token);

  /// The source of the token.
  final RecaptchaV2TokenSource token;
}

/// A reCAPTCHA Enterprise token, sent as `captchaResponse` with `clientType` and
/// `recaptchaVersion: RECAPTCHA_ENTERPRISE`.
///
/// As the proof of a phone request, [token] is called once for each request that needs one, with
/// the action the token is for and the Enterprise site key when the client has read the project's
/// configuration (`FirebaseUserAuth.initializeRecaptchaConfig`); the token is sent as it is,
/// without a fallback to v2.
///
/// As the `recaptchaEnterprise` of a `FirebaseUserAuth`, it is the token source of the requests
/// that the project's reCAPTCHA configuration protects (password sign-in and sign-up, the emails
/// of a password reset and of an email link sign-in, the SMS requests), called with the site key
/// of that configuration.
final class RecaptchaEnterpriseVerification extends AppVerification {
  /// A token from [token], made for [clientType] (`CLIENT_TYPE_WEB` by default: a token from a
  /// web page or a WebView).
  const RecaptchaEnterpriseVerification(
    this.token, {
    this.clientType = RecaptchaClientType.web,
  });

  /// The source of the token.
  final RecaptchaEnterpriseTokenSource token;

  /// Where the token was made.
  final RecaptchaClientType clientType;
}

/// No proof: the request carries no app verification field, like the iOS SDK with
/// `isAppVerificationDisabledForTesting`.
///
/// For the Auth emulator, which ignores the proof, and for the test phone numbers of a real
/// project. Whether a real project accepts a request without a proof for a test number has not been
/// checked against Google; the JS SDK sends a random 50-character `recaptchaToken` instead
/// (`recaptcha_mock.ts`). Real numbers on a real project fail without a proof.
final class NoAppVerification extends AppVerification {
  /// No proof.
  const NoAppVerification();
}

/// Where a reCAPTCHA Enterprise token was made (`clientType` of the requests).
enum RecaptchaClientType {
  /// A web page or a WebView: `CLIENT_TYPE_WEB`.
  web('CLIENT_TYPE_WEB'),

  /// The reCAPTCHA Enterprise SDK for Android: `CLIENT_TYPE_ANDROID`.
  android('CLIENT_TYPE_ANDROID'),

  /// The reCAPTCHA Enterprise SDK for iOS: `CLIENT_TYPE_IOS`.
  ios('CLIENT_TYPE_IOS');

  const RecaptchaClientType(this.value);

  /// The value on the wire.
  final String value;
}

/// The request a proof is for: the action of a reCAPTCHA Enterprise token.
enum RecaptchaAction {
  /// `accounts:sendVerificationCode` (phone sign-in, link, reauthentication).
  sendVerificationCode('sendVerificationCode'),

  /// `accounts/mfaEnrollment:start` for an SMS second factor.
  mfaSmsEnrollment('mfaSmsEnrollment'),

  /// `accounts/mfaSignIn:start` for an SMS second factor.
  mfaSmsSignIn('mfaSmsSignIn'),

  /// `accounts:signInWithPassword` (sign-in and reauthentication with a password).
  signInWithPassword('signInWithPassword'),

  /// `accounts:signUp` with a password (a new account, or a password linked to the user).
  signUpPassword('signUpPassword'),

  /// `accounts:sendOobCode` for a password reset or an email link sign-in.
  getOobCode('getOobCode');

  const RecaptchaAction(this.value);

  /// The action name of the JS SDK (`RecaptchaActionName`).
  final String value;
}

/// What a [RecaptchaV2TokenSource] is called with.
final class RecaptchaV2Request {
  /// Made by the client.
  const RecaptchaV2Request({
    required this.siteKey,
    required this.action,
    this.languageCode,
  });

  /// The reCAPTCHA v2 site key of the project (`v1/recaptchaParams`).
  final String siteKey;

  /// The request the token is for.
  final RecaptchaAction action;

  /// The language of the client (`FirebaseUserAuth.languageCode`), for the widget's `hl`.
  final String? languageCode;

  @override
  String toString() => 'RecaptchaV2Request(action: ${action.value})';
}

/// What a [RecaptchaEnterpriseTokenSource] is called with.
final class RecaptchaEnterpriseRequest {
  /// Made by the client.
  const RecaptchaEnterpriseRequest({
    required this.action,
    this.siteKey,
    this.languageCode,
  });

  /// The request the token is for: pass [RecaptchaAction.value] as the `action` of
  /// `grecaptcha.enterprise.execute`.
  final RecaptchaAction action;

  /// The reCAPTCHA Enterprise site key of the project or tenant (from `v2/recaptchaConfig`), or
  /// null when the client has not read the configuration: only for an
  /// [AppVerification.recaptchaEnterprise] proof passed to a phone request before
  /// `initializeRecaptchaConfig`. The client's own `recaptchaEnterprise` source always gets one.
  final String? siteKey;

  /// The language of the client (`FirebaseUserAuth.languageCode`), for the widget's `hl`.
  final String? languageCode;

  @override
  String toString() => 'RecaptchaEnterpriseRequest(action: ${action.value})';
}

/// The fields of [verification] for the body of [action]: at the top level of
/// `accounts:sendVerificationCode`, inside `phoneEnrollmentInfo` of `accounts/mfaEnrollment:start`
/// and inside `phoneSignInInfo` of `accounts/mfaSignIn:start` (JS `api/authentication/sms.ts`,
/// `api/account_management/mfa.ts`, `api/authentication/mfa.ts`).
///
/// * v2: `{recaptchaToken}`. [siteKey] is called first (`v1/recaptchaParams`).
/// * Enterprise: `{captchaResponse, clientType, recaptchaVersion: RECAPTCHA_ENTERPRISE}`.
/// * none: `{}`. To send the JS SDK's shape instead, return
///   `{'recaptchaToken': <50 random alphanumeric characters>}` in that one case.
///
/// Throws a [FirebaseAuthException] `missing-app-credential` when a source returns an empty token;
/// the errors of `package:secure_flow` that a source throws become a [FirebaseAuthException]
/// ([secureFlowErrorsToAuth]); other errors of the sources and of [siteKey] are rethrown as they
/// are. [enterpriseSiteKey] is the Enterprise site key the client knows, or null. Not exported: the
/// phone calls use it.
Future<Map<String, Object?>> appVerificationFields(
  AppVerification verification, {
  required RecaptchaAction action,
  required Future<String> Function() siteKey,
  String? enterpriseSiteKey,
  String? languageCode,
}) async {
  switch (verification) {
    case RecaptchaV2Verification(:final RecaptchaV2TokenSource token):
      final RecaptchaV2Request request = RecaptchaV2Request(
        siteKey: await siteKey(),
        action: action,
        languageCode: languageCode,
      );
      return <String, Object?>{
        'recaptchaToken': _checked(
          await secureFlowErrorsToAuth(() async => token(request)),
        ),
      };
    case RecaptchaEnterpriseVerification(
      :final RecaptchaEnterpriseTokenSource token,
      :final RecaptchaClientType clientType,
    ):
      final RecaptchaEnterpriseRequest request = RecaptchaEnterpriseRequest(
        action: action,
        siteKey: enterpriseSiteKey,
        languageCode: languageCode,
      );
      final String response = _checked(
        await secureFlowErrorsToAuth(() async => token(request)),
      );
      return <String, Object?>{
        'captchaResponse': response,
        'clientType': clientType.value,
        'recaptchaVersion': 'RECAPTCHA_ENTERPRISE',
      };
    case NoAppVerification():
      return const <String, Object?>{};
  }
}

String _checked(String token) {
  if (token.isEmpty) {
    throw const FirebaseAuthException(
      code: 'missing-app-credential',
      message: 'The app verification source returned an empty token.',
    );
  }
  return token;
}
