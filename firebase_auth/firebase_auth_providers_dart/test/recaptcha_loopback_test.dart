// AppVerification.recaptchaV2Loopback against a simulated browser: an HTTP client fetches the
// reCAPTCHA page of secure_flow and posts what the page's callback would post. No browser and no
// Google script run. The page and the server themselves are tested in package:secure_flow.

@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:firebase_auth_providers_dart/src/app_verification.dart'
    show appVerificationFields;
import 'package:test/test.dart';

const String _siteKey = '6LcTestSiteKey-for_the_loopback_page_0001';

/// One request as a browser would send it, with the Host header of [url].
Future<(int, String)> _send(
  String method,
  Uri url, {
  Map<String, String> headers = const <String, String>{},
  String? body,
}) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request = await client.openUrl(method, url);
    headers.forEach(request.headers.set);
    if (body != null) {
      request.write(body);
    }
    final HttpClientResponse response = await request.close();
    return (response.statusCode, await utf8.decodeStream(response));
  } finally {
    client.close(force: true);
  }
}

/// Posts the form of the page: what the reCAPTCHA callback submits.
Future<(int, String)> _post(Uri url, String token) => _send(
  'POST',
  url.replace(query: ''),
  headers: <String, String>{
    HttpHeaders.contentTypeHeader: 'application/x-www-form-urlencoded',
    'origin': 'http://localhost:${url.port}',
  },
  body: Uri(
    queryParameters: <String, String>{
      'state': url.queryParameters['state']!,
      'token': token,
    },
  ).query,
);

/// Whether the page of [url] still answers.
Future<bool> _answers(Uri url) async {
  try {
    final (int _, String body) = await _send(
      'GET',
      url,
    ).timeout(const Duration(seconds: 5));
    return body.contains('reCAPTCHA');
  } on SocketException {
    return false;
  } on HttpException {
    return false;
  } on TimeoutException {
    return false;
  }
}

/// The fields of a `sendVerificationCode` request with [verification].
Future<Map<String, Object?>> _fields(AppVerification verification) =>
    appVerificationFields(
      verification,
      action: RecaptchaAction.sendVerificationCode,
      siteKey: () async => _siteKey,
      languageCode: 'ro',
    );

TypeMatcher<FirebaseAuthException> _authError(String code) =>
    isA<FirebaseAuthException>().having(
      (FirebaseAuthException e) => e.code,
      'code',
      code,
    );

void main() {
  test(
    'the page renders the project key in the request language; its token is the proof',
    () async {
      late String page;
      final Map<String, Object?> fields = await _fields(
        AppVerification.recaptchaV2Loopback(
          presenter: CallbackPresenter((Uri url) async {
            expect(url.host, 'localhost');
            final (int status, String body) = await _send('GET', url);
            expect(status, HttpStatus.ok);
            page = body;
            final (int done, String _) = await _post(url, 'page-token');
            expect(done, HttpStatus.ok);
          }),
          timeout: const Duration(seconds: 10),
        ),
      );
      expect(fields, <String, Object?>{'recaptchaToken': 'page-token'});
      expect(page, contains('data-sitekey="$_siteKey"'));
      expect(page, contains('hl=ro'));
    },
  );

  test(
    'a timeout is a FirebaseAuthException `timeout` without secrets; the server is closed',
    () async {
      late Uri presented;
      final Object error = await _fields(
        AppVerification.recaptchaV2Loopback(
          presenter: CallbackPresenter((Uri url) => presented = url),
          timeout: const Duration(milliseconds: 300),
        ),
      ).then<Object>((_) => fail('no timeout'), onError: (Object e) => e);
      expect(error, _authError('timeout'));
      expect(
        error.toString(),
        allOf(
          isNot(contains(presented.queryParameters['state']!)),
          isNot(contains(presented.path)),
          isNot(contains(_siteKey)),
        ),
      );
      expect(await _answers(presented), isFalse);
    },
  );

  test(
    'the console presenter\'s ssh hint is part of the timeout message',
    () async {
      final StringBuffer sink = StringBuffer();
      final Object error = await _fields(
        AppVerification.recaptchaV2Loopback(
          presenter: ConsolePresenter(sink: sink),
          timeout: const Duration(milliseconds: 200),
        ),
      ).then<Object>((_) => fail('no timeout'), onError: (Object e) => e);
      expect(
        error,
        _authError('timeout').having(
          (FirebaseAuthException e) => e.message,
          'message',
          contains('ssh -L'),
        ),
      );
      expect(sink.toString().trim(), startsWith('http://localhost:'));
    },
  );

  test('an error of the presenter is rethrown as it is', () async {
    await expectLater(
      _fields(
        AppVerification.recaptchaV2Loopback(
          presenter: CallbackPresenter((_) => throw StateError('no browser')),
        ),
      ),
      throwsStateError,
    );
  });

  test('a site key that is not one fails before anything is shown', () async {
    bool shown = false;
    await expectLater(
      appVerificationFields(
        AppVerification.recaptchaV2Loopback(
          presenter: CallbackPresenter((_) => shown = true),
        ),
        action: RecaptchaAction.mfaSmsSignIn,
        siteKey: () async => '"><script>alert(1)</script>',
      ),
      throwsA(
        isA<ArgumentError>().having(
          (ArgumentError e) => e.toString(),
          'toString',
          isNot(contains('<script>')),
        ),
      ),
    );
    expect(shown, isFalse);
  });

  test(
    'no presenter in the environment is operation-not-supported-in-this-environment; the cause is '
    'kept',
    () async {
      final Object error = await _fields(
        AppVerification.recaptchaV2Loopback(
          environment: const SecureEnvironment(operatingSystem: 'ios'),
        ),
      ).then<Object>((_) => fail('no error'), onError: (Object e) => e);
      expect(
        error,
        _authError('operation-not-supported-in-this-environment').having(
          (FirebaseAuthException e) => e.cause,
          'cause',
          isA<SecureFlowNoPresenter>(),
        ),
      );
    },
  );
}
