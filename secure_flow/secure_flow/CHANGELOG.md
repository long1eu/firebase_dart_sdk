## Unreleased

- `RecaptchaFlow.enterprise(siteKey:, action:)`: a reCAPTCHA Enterprise token for an action. Its loopback page
  loads `enterprise.js?render=<site key>` and posts the token of `grecaptcha.enterprise.execute` as soon as it is
  ready. The action is checked (letters, digits, `/` and `_`).
- `RecaptchaFlow` takes the `size` (`RecaptchaSize`: normal, compact, invisible) and `theme` (`RecaptchaTheme`)
  of the v2 widget; the loopback page starts an invisible widget at once. Its script keeps its names out of the
  page's global scope.
- `InPageRecaptchaPresenter` (web builds, `dart:js_interop` and `package:web`): renders the v2 widget into an
  element of the app's page (invisible without a container), or runs the Enterprise execute, and returns the
  token without the loopback server; `render`, `clear`, and `onVerified`/`onExpired`/`onError` callbacks.
  `SecureEnvironment.current()` offers one on the web, and `RecaptchaFlow` ranks it first, so a reCAPTCHA runs in
  the page there. Tested in Chrome against a fake `grecaptcha`.
- New presenter kind `SecurePresenterKind.inPage` and interface `RecaptchaPresenter` (a presenter that returns a
  reCAPTCHA token itself; `RecaptchaFlow` takes one of any kind it ranks). `CallbackPresenter` refuses the
  `inPage` kind.
- `RecaptchaFailure` (`scriptLoad`, `loadTimeout`, `widget`, `noToken`) for a presenter that could not make a
  token; `RecaptchaFlow` throws it for an empty token of a `RecaptchaPresenter`.
- Depends on `package:web`.

## 0.1.0

First release.

- `SecureFlow<T>`: a self-contained browser round trip (what to open or serve, which request
  answers it, its host, how the answer becomes a `T`) that ranks the presenter kinds it accepts and
  runs itself: `flow.run(presenter:, environment:, timeout:, cancel:)` takes the best presenter of
  the environment, or checks the given one and throws `SecureFlowRefused` when it does not accept
  it. `map` runs work, such as a code exchange, before the browser is told the outcome. Third
  parties can write flows and presenters.
- Flows: `OAuthFlow` (result `OAuthResult`: the redirect of a code request on
  `http://127.0.0.1:<port>`, or the tokens of a provider app; ranks provider app, system browser,
  in-app browser, console), `RecaptchaFlow` (a reCAPTCHA v2 token from a page on
  `http://localhost:<port>`; ranks embedded web view, system browser, console) and
  `CodeEntryFlow` (a code typed at the terminal or into a form; ranks console, then the system browser).
- Presenters with a `SecurePresenterKind` (`providerApp`, `systemBrowser`, `inAppBrowser`,
  `embeddedWebView`, `console`, `other`) and capability interfaces (`LoopbackPresenter`,
  `PromptPresenter`, `ProviderAppPresenter`): `SystemBrowserPresenter`, `ConsolePresenter` (only
  the URL, on stderr by default; prompts read the injected input, stdin by default) and
  `CallbackPresenter` (the app shows the URL and declares the kind). `SecureEnvironment` lists
  what is on offer: registered presenters, the system browser with a display, the console with a
  terminal.
- The loopback server: binds 127.0.0.1 (and ::1 for `localhost` flows), random path, the page only
  for a GET with the state, single-use state compared in constant time, one accepted answer,
  `Host` checked against the flow's host, `Origin` checked for form answers, 64 KiB body limit,
  a CSP nonce in every response, timeout, cancel, closed on every exit; pages follow the system's
  light or dark setting.
- Typed errors: `SecureFlowTimeout` (with an `ssh -L` hint from `ConsolePresenter`),
  `SecureFlowCancelled`, `SecureFlowRefused`, `SecureFlowNoPresenter`.
