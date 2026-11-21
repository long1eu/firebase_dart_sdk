# secure_flow

Browser round trips for Dart desktop apps and command line tools: a flow opens a URL for the
person (or asks at the terminal, or hands over to the provider's app), takes the answer, and
returns a typed result.

```dart
import 'package:secure_flow/secure_flow.dart';

Future<void> main() async {
  final String code = await const CodeEntryFlow(prompt: 'The code from the email').run();
  print('${code.length} characters');
}
```

Pure Dart, no dependencies. The library compiles on the web, where the presenters and the loopback
server throw an `UnsupportedError`. It is used by `firebase_auth_providers_dart` for its OAuth
sign-in and its reCAPTCHA page.

## Flows choose their presenters

A **flow** (`SecureFlow<T>`) is self-contained: what to open or serve, which request answers it
(method, path, query or form), the host the browser uses, how the answer becomes a `T`, and the
**presenter kinds** it accepts, best first. `flow.run()` starts it:

- without a presenter, the flow takes the best one the `SecureEnvironment` offers;
- with `presenter:`, the flow uses it if it accepts it, and throws `SecureFlowRefused` otherwise.
  It never switches to another presenter on its own.

`run` is a method of the flow, not a function of the presenter, because the flow is what knows how
to drive each kind: a browser over the loopback server, a terminal prompt, or a provider's SDK.

| Flow | Result | Presenter kinds, best first | Loopback host and answer |
| --- | --- | --- | --- |
| `OAuthFlow` | `OAuthResult`: `OAuthRedirect` (code or error, and the redirect URI) or `OAuthTokens` (from a provider app) | providerApp (if it can sign in to this provider), systemBrowser, inAppBrowser, console; never embeddedWebView or other | exactly `127.0.0.1`; GET on the redirect path, query |
| `RecaptchaFlow` | the reCAPTCHA v2 token | embeddedWebView, systemBrowser, console | `localhost` (127.0.0.1 and ::1 bound); POST of the page's form, random path |
| `CodeEntryFlow` | the code, trimmed | console (a prompt from the injected input: no browser, no server), systemBrowser | exactly `127.0.0.1`; POST of the page's form, random path |

A **presenter** is a way to show a flow and collect its answer. It has a `SecurePresenterKind`
(`providerApp`, `systemBrowser`, `inAppBrowser`, `embeddedWebView`, `console`, `other`), and what it can do
is told by the interfaces it implements: `LoopbackPresenter` (shows a URL), `PromptPresenter` (reads a
line), `ProviderAppPresenter` (returns OAuth results itself). Flows rank kinds and check interfaces;
they never look at a presenter's class, and presenters never look at a flow's.

| Presenter | Kind | In the environment when |
| --- | --- | --- |
| `SystemBrowserPresenter()` | systemBrowser: `open`, `xdg-open` or `rundll32` (`openInSystemBrowser`) | macOS or Windows, or Linux with `DISPLAY` or `WAYLAND_DISPLAY`, not over SSH |
| `ConsolePresenter(sink:, input:)` | console: writes only the URL to `sink` (stderr); prompts read a line from `input` (stdin) | stdin and stderr are terminals |
| `CallbackPresenter(show, kind:)` | the kind you declare (systemBrowser by default) | you register it |
| a `ProviderAppPresenter` of yours | providerApp | you register it |

```dart
final SecureEnvironment environment = SecureEnvironment.current(
  registered: <SecurePresenter>[myFacebookSdkPresenter],
);
final OAuthResult result = await OAuthFlow(
  providerId: 'facebook.com',
  authorizationUrl: (String redirectUri) => buildAuthorizationUrl(redirectUri),
  state: state,
  rawNonce: rawNonce,
  hashedNonce: hashedNonce,
).run(environment: environment);
switch (result) {
  case OAuthRedirect(:final Map<String, String> parameters):
    // Exchange parameters['code'] with your PKCE verifier.
    break;
  case OAuthTokens(:final String? idToken):
    // The SDK's tokens: no exchange.
    break;
}
```

`OAuthFlow` only carries the request out and the result back: PKCE, the code exchange, the nonce
check and the state value are the caller's; the flow checks the state and passes the scopes and both
nonces to a provider app. Its redirect URI is `http://127.0.0.1:<port>` for the path `/` (no
trailing `/`, the form GitHub OAuth Apps with the callback `http://127.0.0.1` and Google Desktop
clients accept). `flow.map(...)` runs work such as the code exchange while the browser waits, so
that the page it gets says whether the sign-in worked.

`run(presenter:, environment:, timeout:, cancel:)` throws `SecureFlowTimeout` (five minutes by
default; a console presenter adds an `ssh -L` hint), `SecureFlowCancelled`, `SecureFlowRefused` or
`SecureFlowNoPresenter` (nothing in the environment fits: on Android, iOS and the web register or
pass one). Errors of the parser and of the presenter are rethrown as they are.

## What the loopback server checks

- It binds 127.0.0.1, plus ::1 on the same port for `localhost` flows (so that no other process can
  answer on ::1 in its place), and no other interface.
- The page is served only to a GET of the flow's path that carries the state of this run.
- The answer must come to the flow's path (random unless the flow fixes it), with the flow's method
  and encoding, with `Host: <host>:<port>` exactly (a page of another site whose name resolves to
  the loopback address sends its own name), with the page's `Origin` for form answers when the
  browser sends one, and with the state of this run, compared in constant time. Anything else gets
  an error page, and the server keeps waiting.
- One answer is accepted, ever: while an answer is being handled and after it, every request gets a
  404. A flow can reject an answer (an empty token) and keep the state for a retry.
- Request bodies are limited to 64 KiB. Pages are not cached, cannot be framed, and carry a content
  security policy with a new nonce in every response (for the styles of the message and code pages;
  for the scripts of the reCAPTCHA page, whose widget needs inline style attributes). The reCAPTCHA
  page sends `Referrer-Policy: strict-origin` (Google sees the origin, not the path or the state);
  the other pages load nothing and send `no-referrer`. Pages follow the system's light or dark
  setting.
- The server is closed on every exit: result, error, timeout, cancel, or a presenter that throws.
- Nothing is logged, and no error message contains the state, the path, a token or a site key.

## What it does not protect against

- **Other programs of the same user.** They can read the URL from the list of processes while the
  browser starts, connect to the loopback port, or drive the browser. PKCE keeps an intercepted OAuth
  code useless to them; nothing here hides a URL from them.
- **Whoever sees the terminal** of a `ConsolePresenter`: it is only a URL (with the state of the
  run in it), or a typed code, on a terminal.
- **A remote browser.** The answer must reach this machine's loopback interface. Over SSH, forward
  the port while the flow waits (`ssh -L <port>:127.0.0.1:<port> <host>`, or `localhost` for a
  reCAPTCHA flow); without that, the run ends with a `SecureFlowTimeout` whose message says so.
- **A presenter that lies about its kind.** A web view registered as a system browser would be used
  for OAuth; kinds are declarations, not checks. A web view the app controls can read and change
  the page.
- **A provider app.** Its result is trusted as the app returns it; the caller checks the nonce of an
  ID token, and Firebase checks the token.
- **Google's verdict.** Whether a reCAPTCHA token made on a localhost page is accepted depends on the
  site key and the project; it has not been checked against Google.

## License

Apache 2.0; see `LICENSE` and `NOTICE`.
