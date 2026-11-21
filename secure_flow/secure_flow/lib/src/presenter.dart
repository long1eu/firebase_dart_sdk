import 'dart:async';

import 'package:secure_flow/src/flow.dart';

/// What kind of surface a presenter shows a flow on. A flow ranks the kinds it accepts
/// ([SecureFlow.presenterKinds]) without looking at the class of a presenter.
enum SecurePresenterKind {
  /// The provider's own app or SDK (the Facebook app through Facebook's SDK, Google Credential
  /// Manager on Android, the Sign in with Apple sheet). It returns the result itself, without the
  /// loopback server.
  providerApp,

  /// The system's default browser, outside the app.
  systemBrowser,

  /// A browser tab inside the app that the app cannot read (SFSafariViewController, Custom Tabs).
  inAppBrowser,

  /// A web view the app controls and can read. Never used for OAuth (RFC 8252, section 8.12).
  embeddedWebView,

  /// A terminal: a URL printed on it, or a line typed into it.
  console,

  /// A presenter of a third party that fits none of the kinds above.
  other,
}

/// Shows a URL to the person: opens it, prints it, or hands it to a plugin. It may return before
/// the person is done; the flow waits for the answer.
typedef ShowUrl = FutureOr<void> Function(Uri url);

/// A way to show a flow to the person and to collect its answer. Flows choose and drive
/// presenters ([SecureFlow.run]); what a presenter can do is told by the interfaces it implements:
///
/// * [LoopbackPresenter]: shows a URL; the answer comes back over the loopback server.
/// * [PromptPresenter]: asks for a line of text and returns it (a terminal).
/// * `ProviderAppPresenter`: signs in through the provider's app or SDK and returns the result.
abstract interface class SecurePresenter {
  /// The kind of surface, for the ranking of the flows.
  SecurePresenterKind get kind;
}

/// A presenter that shows the URL of a flow; the answer comes back over the one-shot server on
/// the loopback interface, which the flow runs and closes.
abstract class LoopbackPresenter implements SecurePresenter {
  /// For subclasses.
  const LoopbackPresenter();

  /// Shows [url]. Its errors end the flow and are rethrown by [SecureFlow.run].
  FutureOr<void> show(Uri url);

  /// What may help when no answer came back in time (for example an `ssh -L` forward), or null
  /// (the default). It must not contain the state or the path of [session].
  String? timeoutHint(SecureFlowSession session) => null;
}

/// A presenter that asks the person for one line of text, without a browser.
abstract interface class PromptPresenter implements SecurePresenter {
  /// Shows [prompt] and returns the line the person typed.
  Future<String> prompt(String prompt);
}
