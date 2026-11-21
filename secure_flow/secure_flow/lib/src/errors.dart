/// Why a flow did not return a result. A flow's own errors (thrown by its parser) are rethrown as
/// they are; these are the presenter's.
///
/// The messages never contain the state, the path, a token or a site key of the flow.
sealed class SecureFlowException implements Exception {
  const SecureFlowException(this.message);

  /// What happened, for a person.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// No answer came back within the timeout of `SecureFlow.run`.
final class SecureFlowTimeout extends SecureFlowException {
  /// A timeout after [timeout]; [hint] says what may help (for example an `ssh -L` forward).
  const SecureFlowTimeout(super.message, {required this.timeout, this.hint});

  /// How long the presenter waited.
  final Duration timeout;

  /// What may help next time, or null. Already part of [message].
  final String? hint;
}

/// The `cancel` future given to `SecureFlow.run` completed before an answer came back.
final class SecureFlowCancelled extends SecureFlowException {
  /// A cancelled flow.
  const SecureFlowCancelled([super.message = 'The app cancelled the flow.']);
}

/// The flow does not accept the presenter it was given: its kind is not one the flow ranks (a web
/// view for OAuth, which RFC 8252 forbids), or the flow cannot drive it (a provider app for another
/// provider). The caller decides what to do; nothing falls
/// back on its own.
final class SecureFlowRefused extends SecureFlowException {
  /// A refusal.
  const SecureFlowRefused(super.message);
}

/// No presenter of the environment fits the flow (see `SecureFlow.choosePresenter`): pass one.
final class SecureFlowNoPresenter extends SecureFlowException {
  /// No default presenter.
  const SecureFlowNoPresenter(super.message);
}
