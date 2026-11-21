import 'dart:convert';

import 'package:secure_flow/src/flow.dart';
import 'package:secure_flow/src/pages.dart';
import 'package:secure_flow/src/presenter.dart';
import 'package:secure_flow/src/secrets.dart';

/// A small form on `http://127.0.0.1:<port>/<random path>` where the person types a code (a
/// one-time password, a code from an email); the result is what they typed, trimmed.
///
/// On a terminal it asks there and reads the typed line (a [PromptPresenter]); without one (a test
/// runner that keeps stdin, a desktop app) it serves the form.
///
/// * Host exactly `127.0.0.1` ([SecureFlowHost.loopbackIPv4]).
/// * The page has no script; it posts `code` and the state as a form to its own path
///   ([SecureAnswer.form], random path), and only to it (`form-action 'self'`).
/// * An empty code, or one longer than 256 characters, is rejected ([SecureAnswerRejected]): the
///   person can try again.
final class CodeEntryFlow extends SecureFlow<String> {
  /// A form that asks for [prompt] (shown escaped).
  const CodeEntryFlow({required this.prompt});

  /// What the page asks for.
  final String prompt;

  @override
  SecureFlowPurpose get purpose => SecureFlowPurpose.codeEntry;

  /// A terminal first (a [PromptPresenter]: no browser, no server), then the small page in the
  /// system browser.
  @override
  List<SecurePresenterKind> get presenterKinds => const <SecurePresenterKind>[
    SecurePresenterKind.console,
    SecurePresenterKind.systemBrowser,
  ];

  @override
  bool canDrive(SecurePresenter presenter) =>
      presenter is PromptPresenter || presenter is LoopbackPresenter;

  /// With a [PromptPresenter], asks for the code until one is valid (see [parse]).
  @override
  Future<String>? presentDirectly(SecurePresenter presenter) =>
      presenter is PromptPresenter ? _prompt(presenter) : null;

  Future<String> _prompt(PromptPresenter presenter) async {
    while (true) {
      final String? code = _valid(await presenter.prompt(prompt));
      if (code != null) {
        return code;
      }
    }
  }

  @override
  SecureFlowHost get host => SecureFlowHost.loopbackIPv4;

  @override
  SecureAnswer get answer => const SecureAnswer.form();

  @override
  Uri start(SecureFlowSession session) =>
      Uri.parse('${session.address}?state=${session.state}');

  @override
  SecurePage page(SecureFlowSession session) {
    const HtmlEscape text = HtmlEscape();
    const HtmlEscape attribute = HtmlEscape(HtmlEscapeMode.attribute);
    final String nonce = randomNonce();
    return SecurePage.html(
      '<!doctype html><html lang="en"><head><meta charset="utf-8">'
      '<meta name="viewport" content="width=device-width, initial-scale=1">'
      '<meta name="color-scheme" content="light dark">'
      '<title>Enter the code</title>'
      '<style nonce="$nonce">${pageStyle}input,button{font:inherit;padding:4px 8px}</style>'
      '</head><body><h1>Enter the code</h1><p>${text.convert(prompt)}</p>'
      '<form method="post" action="${attribute.convert(session.path)}">'
      '<input type="hidden" name="state" value="${attribute.convert(session.state)}">'
      '<input name="code" autocomplete="one-time-code" autofocus required maxlength="256"> '
      '<button type="submit">Send</button></form></body></html>',
      contentSecurityPolicy:
          "default-src 'none'; style-src 'nonce-$nonce'; form-action 'self'; "
          "base-uri 'none'; frame-ancestors 'none'",
    );
  }

  @override
  String parse(Map<String, String> parameters, SecureFlowSession session) {
    final String? code = _valid(parameters['code']);
    if (code == null) {
      throw const SecureAnswerRejected(
        SecurePage.message(
          title: 'No code',
          text: 'Go back and enter the code.',
        ),
      );
    }
    return code;
  }

  /// [value] trimmed, or null when that is empty or longer than 256 characters.
  static String? _valid(String? value) {
    final String code = (value ?? '').trim();
    return code.isEmpty || code.length > 256 ? null : code;
  }

  @override
  SecurePage get notFoundPage => const SecurePage.message(
    title: 'Not found',
    text: 'This address only receives a code for the app.',
  );

  @override
  SecurePage get donePage => const SecurePage.message(
    title: 'Received',
    text: 'You can close this window and return to the app.',
  );

  /// Leaves out the prompt.
  @override
  String toString() => 'CodeEntryFlow()';
}
