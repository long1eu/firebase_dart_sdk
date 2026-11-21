import 'dart:convert';

import 'package:secure_flow/src/errors.dart';
import 'package:secure_flow/src/flow.dart';
import 'package:secure_flow/src/pages.dart';
import 'package:secure_flow/src/presenter.dart';
import 'package:secure_flow/src/recaptcha_scripts.dart';
import 'package:secure_flow/src/secrets.dart';

/// The size of a reCAPTCHA v2 widget (its `size` parameter).
enum RecaptchaSize {
  /// The checkbox in its default size.
  normal('normal'),

  /// The checkbox in a smaller size.
  compact('compact'),

  /// No checkbox: the check starts at once and shows a challenge only when Google asks for one.
  invisible('invisible');

  const RecaptchaSize(this.value);

  /// The value of the widget's `size` parameter.
  final String value;
}

/// The color theme of a reCAPTCHA v2 widget (its `theme` parameter).
enum RecaptchaTheme {
  /// Light.
  light('light'),

  /// Dark.
  dark('dark');

  const RecaptchaTheme(this.value);

  /// The value of the widget's `theme` parameter.
  final String value;
}

/// What a [RecaptchaPresenter] gets from a [RecaptchaFlow]: which check to run.
final class RecaptchaRequest {
  /// Made by the flow.
  const RecaptchaRequest({
    required this.siteKey,
    this.enterpriseAction,
    this.languageCode,
    this.size = RecaptchaSize.normal,
    this.theme,
  });

  /// The site key the check runs with.
  final String siteKey;

  /// For reCAPTCHA Enterprise, the action the token is for
  /// (`grecaptcha.enterprise.execute(siteKey, {action})`); null for a reCAPTCHA v2 widget.
  final String? enterpriseAction;

  /// The `hl` of the widget (a plain language tag), or null to follow the browser.
  final String? languageCode;

  /// The size of a reCAPTCHA v2 widget.
  final RecaptchaSize size;

  /// The theme of a reCAPTCHA v2 widget, or null for the light or dark setting of the system.
  final RecaptchaTheme? theme;

  /// Whether this is a reCAPTCHA Enterprise check ([enterpriseAction] is set).
  bool get isEnterprise => enterpriseAction != null;

  /// Leaves out the site key.
  @override
  String toString() => isEnterprise
      ? 'RecaptchaRequest(enterprise, action: $enterpriseAction)'
      : 'RecaptchaRequest(v2, size: ${size.name})';
}

/// A presenter that runs a reCAPTCHA itself and returns the token, without the loopback server:
/// the in-page presenter of a web app (`InPageRecaptchaPresenter`), or one of yours (a native
/// reCAPTCHA SDK, a web view that you drive).
abstract interface class RecaptchaPresenter implements SecurePresenter {
  /// Runs the check of [request] and returns its token. Throws a [RecaptchaFailure] when it cannot
  /// make one.
  Future<String> recaptcha(RecaptchaRequest request);
}

/// A reCAPTCHA check whose result is its token: a reCAPTCHA v2 widget ([RecaptchaFlow.new]) or a
/// reCAPTCHA Enterprise token for an action ([RecaptchaFlow.enterprise]).
///
/// With a [RecaptchaPresenter] (on the web, the `InPageRecaptchaPresenter` that
/// `SecureEnvironment.current()` offers there), the presenter runs the check in the app's own page
/// and returns the token; an empty token is a [RecaptchaFailure]
/// ([RecaptchaFailureReason.noToken]).
///
/// With a [LoopbackPresenter], the check is a page served on
/// `http://localhost:<port>/<random path>` that posts the token back:
///
/// * Host `localhost` ([SecureFlowHost.localhost]): the domain that reCAPTCHA site keys (and
///   Firebase projects) allow by default; 127.0.0.1 is not. The server binds 127.0.0.1 and ::1.
/// * The page loads only Google's `api.js` (v2) or `enterprise.js` (Enterprise), under a content
///   security policy with a nonce, renders the v2 widget in [theme] (by default the system's light
///   or dark scheme), and posts `state` and `token` as a form to its own path ([SecureAnswer.form],
///   random path). Its referrer policy gives Google the origin only, not the path or the state,
///   and the state is not part of the HTML. The Enterprise page needs no click: it asks for the
///   token as soon as the script is ready.
/// * An empty token is rejected ([SecureAnswerRejected]): the person can check the box again.
///
/// Whether Google accepts a token made on a localhost page depends on the site key's allowed
/// domains and on the project; this package has not checked it against Google.
final class RecaptchaFlow extends SecureFlow<String> {
  /// A reCAPTCHA v2 check with [siteKey] (letters, digits, `-` and `_`; otherwise an
  /// [ArgumentError] that does not repeat the value). [languageCode] becomes the widget's `hl`
  /// when it is a plain language tag (`en`, `pt-BR`); otherwise the widget follows the browser.
  /// [size] and [theme] are those of the widget ([theme] null: the system's light or dark scheme).
  RecaptchaFlow({
    required this.siteKey,
    String? languageCode,
    this.size = RecaptchaSize.normal,
    this.theme,
  }) : languageCode = languageTagOrNull(languageCode),
       action = null {
    checkSiteKey(siteKey);
  }

  /// A reCAPTCHA Enterprise token for [action] (letters, digits, `/` and `_`; otherwise an
  /// [ArgumentError]) with the Enterprise [siteKey], as
  /// `grecaptcha.enterprise.execute(siteKey, {action})` makes it. Google shows its badge while the
  /// script is loaded, and a challenge only when it asks for one.
  RecaptchaFlow.enterprise({
    required this.siteKey,
    required String this.action,
    String? languageCode,
  }) : languageCode = languageTagOrNull(languageCode),
       size = RecaptchaSize.invisible,
       theme = null {
    checkSiteKey(siteKey);
    checkAction(action!);
  }

  /// The site key the check runs with.
  final String siteKey;

  /// The `hl` of the widget, or null.
  final String? languageCode;

  /// The Enterprise action of the token, or null for a reCAPTCHA v2 check.
  final String? action;

  /// The size of the v2 widget ([RecaptchaSize.invisible] for Enterprise).
  final RecaptchaSize size;

  /// The theme of the v2 widget, or null for the system's light or dark scheme.
  final RecaptchaTheme? theme;

  /// What a [RecaptchaPresenter] is asked for.
  RecaptchaRequest get request => RecaptchaRequest(
    siteKey: siteKey,
    enterpriseAction: action,
    languageCode: languageCode,
    size: size,
    theme: theme,
  );

  @override
  SecureFlowPurpose get purpose => SecureFlowPurpose.recaptcha;

  /// The app's own page first (a web build), then an embedded web view (the check stays inside the
  /// app), then the system browser, then the console.
  @override
  List<SecurePresenterKind> get presenterKinds => const <SecurePresenterKind>[
    SecurePresenterKind.inPage,
    SecurePresenterKind.embeddedWebView,
    SecurePresenterKind.systemBrowser,
    SecurePresenterKind.console,
  ];

  /// A [RecaptchaPresenter] or a [LoopbackPresenter].
  @override
  bool canDrive(SecurePresenter presenter) =>
      presenter is RecaptchaPresenter || presenter is LoopbackPresenter;

  /// With a [RecaptchaPresenter], its token.
  @override
  Future<String>? presentDirectly(SecurePresenter presenter) =>
      presenter is RecaptchaPresenter ? _direct(presenter) : null;

  Future<String> _direct(RecaptchaPresenter presenter) async {
    final String token = await presenter.recaptcha(request);
    if (token.isEmpty) {
      throw const RecaptchaFailure(
        RecaptchaFailureReason.noToken,
        'The reCAPTCHA presenter returned no token.',
      );
    }
    return token;
  }

  @override
  SecureFlowHost get host => SecureFlowHost.localhost;

  @override
  SecureAnswer get answer => const SecureAnswer.form();

  @override
  Uri start(SecureFlowSession session) =>
      Uri.parse('${session.address}?state=${session.state}');

  @override
  SecurePage page(SecureFlowSession session) {
    final String nonce = randomNonce();
    return SecurePage.html(
      _document(nonce, session.path),
      contentSecurityPolicy:
          "default-src 'none'; "
          "script-src 'nonce-$nonce' https://www.google.com/recaptcha/ "
          'https://www.gstatic.com/recaptcha/; '
          'frame-src https://www.google.com/recaptcha/ https://recaptcha.google.com/recaptcha/; '
          // Inline styles stay allowed: the widget sets style attributes, which a nonce cannot
          // cover. Scripts need the nonce of this response.
          "style-src 'unsafe-inline'; form-action 'self'; base-uri 'none'; "
          "frame-ancestors 'none'",
      // Google's script sees the origin (localhost), not the path or the state.
      referrerPolicy: 'strict-origin',
    );
  }

  @override
  String parse(Map<String, String> parameters, SecureFlowSession session) {
    final String token = parameters['token'] ?? '';
    if (token.isEmpty) {
      throw const SecureAnswerRejected(
        SecurePage.message(
          title: 'No token',
          text:
              'The reCAPTCHA check returned no token. Go back and check the box again.',
        ),
      );
    }
    return token;
  }

  @override
  SecurePage get notFoundPage => const SecurePage.message(
    title: 'Not found',
    text: 'This address only serves the reCAPTCHA check of the app.',
  );

  @override
  SecurePage get rejectedPage => const SecurePage.message(
    title: 'Not this check',
    text:
        'This request does not belong to the check in progress. Return to the app and try again.',
  );

  @override
  SecurePage get donePage => const SecurePage.message(
    title: 'Verified',
    text: 'You can close this window and return to the app.',
  );

  /// Leaves out the site key.
  @override
  String toString() =>
      action == null ? 'RecaptchaFlow()' : 'RecaptchaFlow.enterprise($action)';

  String _document(String nonce, String path) {
    const HtmlEscape escape = HtmlEscape(HtmlEscapeMode.attribute);
    final String? action = this.action;
    final Uri script = action == null
        ? recaptchaV2ScriptUrl(
            onload: 'onRecaptchaLoad',
            languageCode: languageCode,
          )
        : recaptchaEnterpriseScriptUrl(
            siteKey: siteKey,
            onload: 'onRecaptchaLoad',
            languageCode: languageCode,
          );
    final String box = action == null
        ? '<div id="w" data-sitekey="${escape.convert(siteKey)}" '
              'data-size="${size.value}" data-theme="${theme?.value ?? ''}"></div>'
        : '<div id="w" data-sitekey="${escape.convert(siteKey)}" '
              'data-action="${escape.convert(action)}"></div>';
    return '<!doctype html><html lang="en"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1">'
        '<meta name="color-scheme" content="light dark">'
        '<title>Verify that you are not a robot</title>'
        '<style>$pageStyle#w{margin:24px 0}</style>'
        '</head><body><h1>Verify that you are not a robot</h1>'
        '<p id="s">${action == null ? _v2Text : _enterpriseText}</p>'
        '$box'
        '<noscript><p>This check needs JavaScript.</p></noscript>'
        '<form id="f" method="post" action="${escape.convert(path)}" hidden>'
        '<input type="hidden" name="state"><input type="hidden" name="token"></form>'
        '<script nonce="$nonce">(function () {$_sendScript'
        '${action == null ? _v2Script : _enterpriseScript}})();</script>'
        '<script nonce="$nonce" src="${escape.convert(script.toString())}" async defer>'
        '</script></body></html>';
  }
}

const String _v2Text =
    'The app needs this check before it sends a verification code.';

const String _enterpriseText =
    'Checking that the request comes from a person. This takes a moment.';

/// The common part of the page scripts: `send(token)` posts the token with the state of the
/// address to the server, `say(text)` updates the status line.
const String _sendScript = '''
var state = new URLSearchParams(location.search).get('state') || '';
var form = document.getElementById('f');
var status = document.getElementById('s');
var box = document.getElementById('w');
function say(text) { status.textContent = text; }
function send(token) {
  form.elements.state.value = state;
  form.elements.token.value = token;
  say('Sending the result to the app...');
  form.submit();
}
''';

/// Renders the v2 widget in its size and theme (the system's color scheme without one) and starts
/// an invisible one at once.
const String _v2Script = '''
window.onRecaptchaLoad = function () {
  var size = box.dataset.size || 'normal';
  var id = grecaptcha.render(box, {
    sitekey: box.dataset.sitekey,
    size: size,
    theme: box.dataset.theme ||
      (matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'),
    callback: send,
    'expired-callback': function () {
      say('The check expired. Check the box again.');
    },
    'error-callback': function () {
      say('The check could not load. Check the connection, then reload this page.');
    }
  });
  if (size === 'invisible') { grecaptcha.execute(id); }
};
''';

/// Asks reCAPTCHA Enterprise for a token for the action as soon as it is ready.
const String _enterpriseScript = '''
window.onRecaptchaLoad = function () {
  grecaptcha.enterprise.ready(function () {
    grecaptcha.enterprise.execute(box.dataset.sitekey, { action: box.dataset.action })
      .then(send, function () {
        say('The check failed. Check the connection, then reload this page.');
      });
  });
};
''';
