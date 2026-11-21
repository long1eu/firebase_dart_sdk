import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:secure_flow/src/browser_command.dart';
import 'package:secure_flow/src/flow.dart';
import 'package:secure_flow/src/errors.dart';
import 'package:secure_flow/src/presenter.dart';

/// Opens [url] in the default browser of the desktop: `open` on macOS, `xdg-open` on Linux,
/// `rundll32 url.dll,FileProtocolHandler` on Windows. The URL is passed as one argument, without a
/// shell. It only opens the URL; `SystemBrowserPresenter` runs a whole flow.
///
/// Throws an [UnsupportedError] on other systems (Android, iOS, Fuchsia) and on the web, and a
/// [StateError] when the command fails. The message does not contain the URL.
Future<void> openInSystemBrowser(Uri url) async {
  final ({String executable, List<String> arguments})? command = browserCommand(
    Platform.operatingSystem,
    url,
  );
  if (command == null) {
    throw UnsupportedError(
      'openInSystemBrowser works on macOS, Linux and Windows, not on '
      '${Platform.operatingSystem}: pass a presenter that can show a URL there.',
    );
  }
  final ProcessResult result;
  try {
    result = await Process.run(command.executable, command.arguments);
  } on ProcessException catch (e) {
    throw StateError(
      'Could not open the browser with ${command.executable}: ${e.message}',
    );
  }
  if (result.exitCode != 0) {
    throw StateError(
      'Could not open the browser: ${command.executable} exited with ${result.exitCode}.',
    );
  }
}

/// Shows a flow in the system browser: opens its URL with [open] ([openInSystemBrowser] by
/// default); the answer comes back over the loopback server. Kind
/// [SecurePresenterKind.systemBrowser]; in the environment when there is a display.
///
/// What it protects against: the answer is taken only from the loopback interface, on the flow's
/// path, with the flow's `Host` (no DNS rebinding), with the state of this run (compared in
/// constant time, good once), before the timeout; nothing of the flow is logged. What it does not
/// protect against: another program of the same user (it can read the URL from the list of
/// processes while the browser starts, or drive the browser), and a browser that is not the
/// person's.
final class SystemBrowserPresenter extends LoopbackPresenter {
  /// A presenter that opens URLs with [open]; replace it only in tests.
  const SystemBrowserPresenter({this.open = openInSystemBrowser});

  /// Opens the URL of the flow.
  final ShowUrl open;

  @override
  SecurePresenterKind get kind => SecurePresenterKind.systemBrowser;

  @override
  FutureOr<void> show(Uri url) => open(url);
}

/// A terminal. Kind [SecurePresenterKind.console]; in the environment when stdin and stderr are
/// terminals.
///
/// * As a [LoopbackPresenter] it writes the URL of a flow, and nothing else, as one line to the
///   sink (stderr by default), for the person to open in a browser on the same machine. It is
///   only a URL on a terminal: anyone who sees the terminal sees it (it carries the state of the
///   run), and the answer can only come from a browser that reaches this machine's loopback
///   interface. Over SSH that needs a port forward (`ssh -L <port>:<host>:<port>`, while the flow
///   waits); without it the run ends with a [SecureFlowTimeout] whose message says so.
/// * As a [PromptPresenter] (a `CodeEntryFlow`) it writes the prompt to the sink and reads one line
///   from the input (stdin by default): no browser at all. What is typed is visible on the
///   terminal.
final class ConsolePresenter extends LoopbackPresenter
    implements PromptPresenter {
  /// A presenter that writes to [sink] (stderr when null) and reads lines from [input] (the lines
  /// of stdin when null). Each prompt takes the next line of [input]; pass a broadcast stream to
  /// prompt more than once.
  ConsolePresenter({StringSink? sink, Stream<String>? input})
    : _sink = sink,
      _input = input;

  final StringSink? _sink;
  final Stream<String>? _input;

  /// The lines of stdin, read once for the whole program.
  static final Stream<String> _stdinLines = stdin
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .asBroadcastStream();

  @override
  SecurePresenterKind get kind => SecurePresenterKind.console;

  @override
  void show(Uri url) => (_sink ?? stderr).writeln(url);

  @override
  String timeoutHint(SecureFlowSession session) =>
      'If the browser runs on another machine (an SSH session), forward the port while the flow '
      'waits: ssh -L ${session.port}:${session.host.hostName}:${session.port} <this machine>, '
      'then open the URL again.';

  @override
  Future<String> prompt(String prompt) async {
    (_sink ?? stderr).write('$prompt: ');
    final String? line = await (_input ?? _stdinLines)
        .cast<String?>()
        .firstWhere((String? _) => true, orElse: () => null);
    if (line == null) {
      throw StateError('The input ended before a line was typed.');
    }
    return line;
  }
}

/// Shows a flow with a function the app supplies ([show]: `url_launcher`, a browser tab of a
/// plugin, a window or a web view of the app); the answer comes back over the loopback server.
///
/// [kind] says what [show] displays: [SecurePresenterKind.systemBrowser] by default (an external
/// browser, as `url_launcher` opens it on a desktop), [SecurePresenterKind.inAppBrowser],
/// [SecurePresenterKind.embeddedWebView] (an OAuth flow refuses it), [SecurePresenterKind.console] or
/// [SecurePresenterKind.other]. A wrong kind defeats the ranking: a web view declared as a system
/// browser would be used for OAuth.
final class CallbackPresenter extends LoopbackPresenter {
  /// A presenter that shows URLs with [show]. [kind] cannot be
  /// [SecurePresenterKind.providerApp] or [SecurePresenterKind.inPage], which return results
  /// without the loopback server.
  CallbackPresenter(
    ShowUrl show, {
    this.kind = SecurePresenterKind.systemBrowser,
  }) : _show = show {
    if (kind == SecurePresenterKind.providerApp ||
        kind == SecurePresenterKind.inPage) {
      throw ArgumentError.value(
        kind,
        'kind',
        'a provider app or an in-page presenter does not show a URL',
      );
    }
  }

  final ShowUrl _show;

  @override
  final SecurePresenterKind kind;

  @override
  FutureOr<void> show(Uri url) => _show(url);
}
