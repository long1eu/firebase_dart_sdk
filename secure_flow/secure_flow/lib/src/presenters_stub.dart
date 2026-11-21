import 'dart:async';

import 'package:secure_flow/src/presenter.dart';

Never _unsupported() => throw UnsupportedError(
  'The presenters of secure_flow need dart:io (desktop and command line).',
);

/// Opens a URL in the system browser. Needs `dart:io`; on this platform it throws an
/// [UnsupportedError].
Future<void> openInSystemBrowser(Uri url) async => _unsupported();

/// Shows a flow in the system browser. Needs `dart:io`; on this platform [show] throws an
/// [UnsupportedError].
final class SystemBrowserPresenter extends LoopbackPresenter {
  /// See the `dart:io` implementation.
  const SystemBrowserPresenter({this.open = openInSystemBrowser});

  /// Opens the URL of the flow.
  final ShowUrl open;

  @override
  SecurePresenterKind get kind => SecurePresenterKind.systemBrowser;

  @override
  FutureOr<void> show(Uri url) => _unsupported();
}

/// A terminal. Needs `dart:io`; on this platform [show] and [prompt] throw an
/// [UnsupportedError].
final class ConsolePresenter extends LoopbackPresenter
    implements PromptPresenter {
  /// See the `dart:io` implementation.
  // The arguments are used by the dart:io implementation only; the signature must match it.
  // ignore: avoid_unused_constructor_parameters
  ConsolePresenter({StringSink? sink, Stream<String>? input});

  @override
  SecurePresenterKind get kind => SecurePresenterKind.console;

  @override
  FutureOr<void> show(Uri url) => _unsupported();

  @override
  Future<String> prompt(String prompt) async => _unsupported();
}

/// Shows a flow with a function the app supplies. Needs `dart:io` for the loopback server; on
/// this platform a flow run with it throws an [UnsupportedError].
final class CallbackPresenter extends LoopbackPresenter {
  /// See the `dart:io` implementation.
  CallbackPresenter(
    ShowUrl show, {
    this.kind = SecurePresenterKind.systemBrowser,
  }) : _show = show {
    if (kind == SecurePresenterKind.providerApp) {
      throw ArgumentError.value(
        kind,
        'kind',
        'a provider app does not show a URL',
      );
    }
  }

  final ShowUrl _show;

  @override
  final SecurePresenterKind kind;

  @override
  FutureOr<void> show(Uri url) => _show(url);
}
