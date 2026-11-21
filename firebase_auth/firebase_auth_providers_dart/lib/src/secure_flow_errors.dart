// How the errors of secure_flow become the errors of this package. Not exported.

import 'package:secure_flow/secure_flow.dart';

import 'auth_exception.dart';

/// Runs [flow] with [presenter] (or the best presenter of [environment] when null, see
/// [SecureFlow.run]) and turns a
/// timeout into a [FirebaseAuthException] `timeout` with [timeoutMessage] (plus the presenter's
/// hint), and a cancel into `user-cancelled`. Other errors are rethrown as they are.
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
  }
}
