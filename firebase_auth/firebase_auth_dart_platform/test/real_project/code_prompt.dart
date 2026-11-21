// How the real-project harness asks for a one-time code. `flutter test` does
// not forward the terminal's stdin to the test process, so the code is typed
// into a page served on 127.0.0.1 instead.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Asks the person at the computer for a one-time code.
abstract interface class CodeSource {
  /// Returns the code the person entered for [prompt]. [otpauthUri], when
  /// given, is shown so that it can be added to an authenticator app.
  Future<String> ask(String prompt, {String? otpauthUri});
}

/// A [CodeSource] that serves a form at a random path on 127.0.0.1.
///
/// Each [ask] prints the address of the form through [log] and opens it with
/// [open] (the system browser in the harness, nothing in tests). The path
/// holds a random token, so that another local page cannot post a code. The
/// server starts at the first [ask] and stops at [close].
class LoopbackCodePrompt implements CodeSource {
  /// A prompt that reports through [log] and opens its page with [open].
  LoopbackCodePrompt({
    required this.log,
    this.open,
    this.timeout = const Duration(minutes: 10),
  });

  /// Prints a line for the person at the terminal.
  final void Function(String line) log;

  /// Opens the address of the form; null leaves that to the person.
  final Future<void> Function(Uri url)? open;

  /// How long [ask] waits for a code before it throws a [TimeoutException].
  final Duration timeout;

  static final Random _random = Random.secure();
  final String _token = List<String>.generate(
    24,
    (_) => _random.nextInt(16).toRadixString(16),
  ).join();

  HttpServer? _server;
  Completer<String>? _waiting;
  String _prompt = '';
  String? _otpauthUri;

  /// The address of the form; null before the first [ask].
  Uri? get url {
    final HttpServer? server = _server;
    return server == null
        ? null
        : Uri.parse('http://127.0.0.1:${server.port}/$_token/');
  }

  @override
  Future<String> ask(String prompt, {String? otpauthUri}) async {
    if (_server == null) {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      _server = server;
      server.listen(_handle);
    }
    final Completer<String> waiting = Completer<String>();
    _waiting = waiting;
    _prompt = prompt;
    _otpauthUri = otpauthUri;
    final Uri address = url!;
    log('  $prompt: enter it at $address');
    await open?.call(address);
    try {
      return await waiting.future.timeout(timeout);
    } finally {
      _waiting = null;
    }
  }

  /// Stops the server.
  Future<void> close() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handle(HttpRequest request) async {
    final HttpResponse response = request.response;
    try {
      if (request.uri.path != '/$_token/') {
        await _reply(response, HttpStatus.notFound, 'Not found.');
      } else if (request.method == 'POST') {
        await _receive(request);
      } else {
        await _reply(response, HttpStatus.ok, _form());
      }
    } on Object catch (e) {
      log('  The code page failed to answer: ${e.runtimeType}');
    }
  }

  Future<void> _receive(HttpRequest request) async {
    final Completer<String>? waiting = _waiting;
    if (waiting == null || waiting.isCompleted) {
      await _reply(
        request.response,
        HttpStatus.conflict,
        'No code is needed right now. Go back to the terminal.',
      );
      return;
    }
    final String body = await utf8.decoder.bind(request).join();
    final String code = normalizeCode(Uri.splitQueryString(body)['code']);
    if (code.isEmpty) {
      await _reply(
        request.response,
        HttpStatus.badRequest,
        '<p>That is not a 6 to 8 digit code.</p>${_form()}',
      );
      return;
    }
    await _reply(
      request.response,
      HttpStatus.ok,
      'Received. Go back to the terminal.',
    );
    waiting.complete(code);
  }

  String _form() {
    final StringBuffer html = StringBuffer()
      ..write('<p>${_escape(_prompt)}</p>');
    final String? uri = _otpauthUri;
    if (uri != null) {
      html
        ..write('<p>Add this to your authenticator app (paste the URI, or ')
        ..write('type the <code>secret</code> parameter as a setup key):</p>')
        ..write('<p><code style="word-break:break-all">${_escape(uri)}</code>')
        ..write('</p>');
    }
    html.write(
      '<form method="post"><input name="code" inputmode="numeric" '
      'autocomplete="one-time-code" autofocus> '
      '<button type="submit">Send</button></form>',
    );
    return html.toString();
  }

  static String _escape(String text) => const HtmlEscape().convert(text);

  static Future<void> _reply(
    HttpResponse response,
    int status,
    String body,
  ) async {
    response
      ..statusCode = status
      ..headers.contentType = ContentType.html
      ..headers.set('Cache-Control', 'no-store')
      ..write(
        '<!doctype html><meta charset="utf-8"><title>Auth harness</title>'
        '<body style="font-family:sans-serif;max-width:40em;margin:2em auto">'
        '$body</body>',
      );
    await response.close();
  }
}

/// [value] without spaces and dashes when what is left is 6 to 8 digits (the
/// length of a TOTP code); otherwise an empty string.
String normalizeCode(String? value) {
  final String code = (value ?? '').replaceAll(RegExp(r'[\s-]'), '');
  return RegExp(r'^\d{6,8}$').hasMatch(code) ? code : '';
}
