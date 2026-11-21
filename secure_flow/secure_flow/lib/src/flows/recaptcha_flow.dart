import 'dart:convert';

import 'package:secure_flow/src/flow.dart';
import 'package:secure_flow/src/pages.dart';
import 'package:secure_flow/src/presenter.dart';
import 'package:secure_flow/src/secrets.dart';

/// A reCAPTCHA v2 checkbox served on `http://localhost:<port>/<random path>`; the result is the
/// token the page posts back.
///
/// * Host `localhost` ([SecureFlowHost.localhost]): the domain that reCAPTCHA site keys (and
///   Firebase projects) allow by default; 127.0.0.1 is not. The server binds 127.0.0.1 and ::1.
/// * The page loads only Google's `api.js`, under a content security policy with a nonce, renders
///   the widget in the system's light or dark scheme, and posts `state` and `token` as a form to
///   its own path ([SecureAnswer.form], random path). Its referrer policy gives Google the origin
///   only, not the path or the state, and the state is not part of the HTML.
/// * An empty token is rejected ([SecureAnswerRejected]): the person can check the box again.
///
/// Whether Google accepts a token made on a localhost page depends on the site key's allowed
/// domains and on the project; this package has not checked it against Google.
final class RecaptchaFlow extends SecureFlow<String> {
  /// A check with [siteKey] (letters, digits, `-` and `_`; otherwise an [ArgumentError] that does
  /// not repeat the value). [languageCode] becomes the widget's `hl` when it is a plain language
  /// tag (`en`, `pt-BR`); otherwise the widget follows the browser.
  RecaptchaFlow({required this.siteKey, String? languageCode})
    : languageCode = languageCode != null && _languageTag.hasMatch(languageCode)
          ? languageCode
          : null {
    if (!_siteKeyPattern.hasMatch(siteKey)) {
      throw ArgumentError.value(
        '<redacted>',
        'siteKey',
        'is not a reCAPTCHA site key (letters, digits, - and _)',
      );
    }
  }

  static final RegExp _siteKeyPattern = RegExp(r'^[A-Za-z0-9_-]{1,100}$');
  static final RegExp _languageTag = RegExp(
    r'^[A-Za-z]{2,3}(-[A-Za-z0-9]{1,8})*$',
  );

  /// The reCAPTCHA v2 site key the widget renders with.
  final String siteKey;

  /// The `hl` of the widget, or null.
  final String? languageCode;

  @override
  SecureFlowPurpose get purpose => SecureFlowPurpose.recaptcha;

  /// An embedded web view first (the check stays inside the app), then the system browser, then
  /// the console.
  @override
  List<SecurePresenterKind> get presenterKinds => const <SecurePresenterKind>[
    SecurePresenterKind.embeddedWebView,
    SecurePresenterKind.systemBrowser,
    SecurePresenterKind.console,
  ];

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
  String toString() => 'RecaptchaFlow()';

  String _document(String nonce, String path) {
    const HtmlEscape escape = HtmlEscape(HtmlEscapeMode.attribute);
    final String script = Uri.https(
      'www.google.com',
      '/recaptcha/api.js',
      <String, String>{
        'onload': 'onRecaptchaLoad',
        'render': 'explicit',
        'hl': ?languageCode,
      },
    ).toString();
    return '<!doctype html><html lang="en"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1">'
        '<meta name="color-scheme" content="light dark">'
        '<title>Verify that you are not a robot</title>'
        '<style>$pageStyle#w{margin:24px 0}</style>'
        '</head><body><h1>Verify that you are not a robot</h1>'
        '<p id="s">The app needs this check before it sends a verification code.</p>'
        '<div id="w" data-sitekey="${escape.convert(siteKey)}"></div>'
        '<noscript><p>This check needs JavaScript.</p></noscript>'
        '<form id="f" method="post" action="${escape.convert(path)}" hidden>'
        '<input type="hidden" name="state"><input type="hidden" name="token"></form>'
        '<script nonce="$nonce">$_pageScript</script>'
        '<script nonce="$nonce" src="${escape.convert(script)}" async defer></script>'
        '</body></html>';
  }
}

/// The script of the page: renders the widget in the color scheme of the system, then posts the
/// token with the state of the address to the server.
const String _pageScript = '''
(function () {
  var state = new URLSearchParams(location.search).get('state') || '';
  var form = document.getElementById('f');
  var status = document.getElementById('s');
  var box = document.getElementById('w');
  window.onRecaptchaLoad = function () {
    grecaptcha.render(box, {
      sitekey: box.dataset.sitekey,
      theme: matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light',
      callback: function (token) {
        form.elements.state.value = state;
        form.elements.token.value = token;
        status.textContent = 'Sending the result to the app...';
        form.submit();
      },
      'expired-callback': function () {
        status.textContent = 'The check expired. Check the box again.';
      },
      'error-callback': function () {
        status.textContent =
          'The check could not load. Check the connection, then reload this page.';
      }
    });
  };
})();
''';
