/// Browser round trips for desktop apps and command line tools: a flow opens a URL for the person
/// (or asks at the terminal, or hands over to the provider's app) and returns a typed result.
///
/// * A [SecureFlow] is self-contained: what to open or serve, which request answers it, how that
///   request becomes a result, and which presenter kinds fit it, best first. Built in:
///   [OAuthFlow] (an OAuth sign-in: the redirect of a code request, or the tokens of a provider
///   app), [RecaptchaFlow] (a reCAPTCHA v2 token) and [CodeEntryFlow] (a code the person types).
/// * A [SecurePresenter] is a way to show a flow and collect its answer, with a
///   [SecurePresenterKind]: [SystemBrowserPresenter], [ConsolePresenter], [CallbackPresenter], or
///   a [ProviderAppPresenter] of your own.
/// * [SecureFlow.run] picks the best presenter of the [SecureEnvironment] for the flow, or checks
///   the one you pass.
///
/// ```dart
/// import 'package:secure_flow/secure_flow.dart';
///
/// Future<void> main() async {
///   final String code = await const CodeEntryFlow(prompt: 'The code from the email').run();
///   print(code.length);
/// }
/// ```
///
/// The library compiles on the web, where the presenters and the loopback server throw an
/// [UnsupportedError].
library;

import 'package:secure_flow/src/environment.dart';
import 'package:secure_flow/src/flow.dart';
import 'package:secure_flow/src/flows/code_entry_flow.dart';
import 'package:secure_flow/src/flows/oauth_flow.dart';
import 'package:secure_flow/src/flows/recaptcha_flow.dart';
import 'package:secure_flow/src/presenter.dart';
import 'package:secure_flow/src/presenters_stub.dart'
    if (dart.library.io) 'package:secure_flow/src/presenters_io.dart';

export 'package:secure_flow/src/environment.dart';
export 'package:secure_flow/src/errors.dart';
export 'package:secure_flow/src/flow.dart';
export 'package:secure_flow/src/flows/code_entry_flow.dart';
export 'package:secure_flow/src/flows/oauth_flow.dart';
export 'package:secure_flow/src/flows/recaptcha_flow.dart';
export 'package:secure_flow/src/presenter.dart';
export 'package:secure_flow/src/presenters_stub.dart'
    if (dart.library.io) 'package:secure_flow/src/presenters_io.dart';
