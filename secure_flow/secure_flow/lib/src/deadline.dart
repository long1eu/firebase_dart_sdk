import 'dart:async';

import 'package:secure_flow/src/errors.dart';

/// The timeout error of a flow that waited [timeout], with [hint] when there is one.
SecureFlowTimeout timeoutError(
  Duration timeout,
  String? hint,
) => SecureFlowTimeout(
  'No answer came back within ${_describe(timeout)}.${hint == null ? '' : ' $hint'}',
  timeout: timeout,
  hint: hint,
);

String _describe(Duration timeout) => timeout.inSeconds >= 1
    ? '${timeout.inSeconds} seconds'
    : '${timeout.inMilliseconds} milliseconds';

/// [work], or a [SecureFlowTimeout] after [timeout], or a [SecureFlowCancelled] when [cancel]
/// completes first. [work] itself is not stopped (an SDK call cannot be); its late result is
/// dropped.
Future<T> withDeadline<T>(
  Future<T> work, {
  required Duration timeout,
  Future<void>? cancel,
}) {
  final Completer<T> result = Completer<T>();
  void fail(Object error, StackTrace stackTrace) {
    if (!result.isCompleted) {
      result.completeError(error, stackTrace);
    }
  }

  final Timer timer = Timer(
    timeout,
    () => fail(timeoutError(timeout, null), StackTrace.current),
  );
  if (cancel != null) {
    void cancelled([Object? _]) =>
        fail(const SecureFlowCancelled(), StackTrace.current);
    unawaited(cancel.then<void>(cancelled, onError: cancelled));
  }
  work.then<void>((T value) {
    if (!result.isCompleted) {
      result.complete(value);
    }
  }, onError: fail);
  return result.future.whenComplete(timer.cancel);
}
