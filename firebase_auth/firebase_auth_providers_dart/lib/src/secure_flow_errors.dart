// How the errors of secure_flow become the errors of this package. Not exported.

import 'package:secure_flow/secure_flow.dart';

import 'auth_exception.dart';

/// Runs [flow] with [presenter] (or the best presenter of [environment] when null, see
/// [SecureFlow.run]) and turns the errors of `secure_flow` into a [FirebaseAuthException]
/// ([secureFlowErrorsToAuth] with [timeoutMessage]).
Future<T> runSecureFlow<T>(
  SecureFlow<T> flow, {
  required SecurePresenter? presenter,
  required SecureEnvironment? environment,
  required Duration timeout,
  required String timeoutMessage,
  Future<void>? cancel,
}) => secureFlowErrorsToAuth(
  () => flow.run(
    presenter: presenter,
    environment: environment,
    timeout: timeout,
    cancel: cancel,
  ),
  timeoutMessage: timeoutMessage,
);

/// Runs [body] and turns the errors of `secure_flow` into a [FirebaseAuthException]:
///
/// * a timeout into `timeout`, with [timeoutMessage] (plus the presenter's hint);
/// * a cancel into `user-cancelled`;
/// * a [SecureFlowNoPresenter] (no presenter of the environment fits the flow) into
///   `operation-not-supported-in-this-environment`, the code of the JS SDK for an operation the
///   environment cannot run;
/// * a [SecureFlowRefused] (the flow does not accept the presenter it was given) into
///   `argument-error`, the code of the JS SDK for an argument of the wrong kind (a provider that
///   is not an OAuth provider passed to `signInWithPopup`): the presenter is an argument of the
///   caller;
/// * a [RecaptchaFailure] of an in-page widget into the codes of the JS SDK's reCAPTCHA loader:
///   `internal-error` when Google's script did not load, `network-request-failed` when it did not
///   load in time or the widget reported an error, `missing-app-credential` for no token, and
///   `cancelled` for a check that a newer one of the same presenter replaced.
///
/// The last three keep the original error as [FirebaseAuthException.cause]. Other errors (of the
/// presenter itself) are rethrown as they are.
Future<T> secureFlowErrorsToAuth<T>(
  Future<T> Function() body, {
  String timeoutMessage = 'No reCAPTCHA token came back in time.',
}) async {
  try {
    return await body();
  } on SecureFlowTimeout catch (e) {
    final String? hint = e.hint;
    throw FirebaseAuthException(
      code: 'timeout',
      message: hint == null ? timeoutMessage : '$timeoutMessage $hint',
    );
  } on SecureFlowCancelled {
    throw const FirebaseAuthException(
      code: 'user-cancelled',
      message: 'The app cancelled the browser flow.',
    );
  } on SecureFlowNoPresenter catch (e, stackTrace) {
    _rethrowAs(
      'operation-not-supported-in-this-environment',
      e.message,
      e,
      stackTrace,
    );
  } on SecureFlowRefused catch (e, stackTrace) {
    _rethrowAs('argument-error', e.message, e, stackTrace);
  } on RecaptchaFailure catch (e, stackTrace) {
    final String code = switch (e.reason) {
      RecaptchaFailureReason.scriptLoad => 'internal-error',
      RecaptchaFailureReason.loadTimeout ||
      RecaptchaFailureReason.widget => 'network-request-failed',
      RecaptchaFailureReason.noToken => 'missing-app-credential',
      RecaptchaFailureReason.superseded => 'cancelled',
    };
    _rethrowAs(code, e.message, e, stackTrace);
  }
}

Never _rethrowAs(
  String code,
  String message,
  Object cause,
  StackTrace stackTrace,
) => Error.throwWithStackTrace(
  FirebaseAuthException(code: code, message: message, cause: cause),
  stackTrace,
);
