// How the errors of secure_flow become the errors of this package. Not exported.

import 'package:secure_flow/secure_flow.dart';

import 'auth_exception.dart';

/// Runs [flow] with [presenter] (or the best presenter of [environment] when null, see
/// [SecureFlow.run]) and turns the errors of `secure_flow` into a [FirebaseAuthException]:
///
/// * a timeout into `timeout`, with [timeoutMessage] (plus the presenter's hint);
/// * a cancel into `user-cancelled`;
/// * a [SecureFlowNoPresenter] (no presenter of the environment fits the flow) into
///   `operation-not-supported-in-this-environment`, the code of the JS SDK for an operation the
///   environment cannot run;
/// * a [SecureFlowRefused] (the flow does not accept the presenter it was given) into
///   `argument-error`, the code of the JS SDK for an argument of the wrong kind (a provider that
///   is not an OAuth provider passed to `signInWithPopup`): the presenter is an argument of the
///   caller.
///
/// The last two keep the original error as [FirebaseAuthException.cause]. Other errors (of the
/// presenter itself) are rethrown as they are.
Future<T> runSecureFlow<T>(
  SecureFlow<T> flow, {
  required SecurePresenter? presenter,
  required SecureEnvironment? environment,
  required Duration timeout,
  required String timeoutMessage,
  Future<void>? cancel,
}) async {
  try {
    return await flow.run(
      presenter: presenter,
      environment: environment,
      timeout: timeout,
      cancel: cancel,
    );
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
    Error.throwWithStackTrace(
      FirebaseAuthException(
        code: 'operation-not-supported-in-this-environment',
        message: e.message,
        cause: e,
      ),
      stackTrace,
    );
  } on SecureFlowRefused catch (e, stackTrace) {
    Error.throwWithStackTrace(
      FirebaseAuthException(
        code: 'argument-error',
        message: e.message,
        cause: e,
      ),
      stackTrace,
    );
  }
}
