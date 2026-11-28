// Shared specification v3, 5.10: header names, the token text and header value checks, the
// X-Goog-Api-Client value, and RequestTokens.forTesting.
//
// The "refusal names the header only" case of 11.4 is dropped by ruling M8 of code review 1: the
// package has no function that refuses a header; products and GrpcCaller test their own.
import 'package:_firebase_transport_dart/_firebase_transport_dart.dart';
import 'package:test/test.dart';

final RegExp _clientPart = RegExp(r'^[A-Za-z0-9._/-]+$');

/// The text of the [ArgumentError] that [call] throws.
String _errorTextOf(void Function() call) {
  try {
    call();
  } on ArgumentError catch (error) {
    return '$error | ${error.message} | ${error.invalidValue} | ${error.name}';
  }
  fail('expected an ArgumentError');
}

void main() {
  _valueTests();
  _apiClientTests();
  _forTestingTests();
}

void _valueTests() {
  test('header names and the token cap', () {
    expect(FirebaseHeaders.authorization, 'Authorization');
    expect(FirebaseHeaders.firebaseAuthToken, 'X-Firebase-Auth-Token');
    expect(FirebaseHeaders.appCheck, 'X-Firebase-AppCheck');
    expect(FirebaseHeaders.gmpId, 'X-Firebase-GMPID');
    expect(FirebaseHeaders.apiKey, 'X-Goog-Api-Key');
    expect(FirebaseHeaders.apiClient, 'X-Goog-Api-Client');
    expect(maxTokenLength, 8192);
    expect(AuthHeaderStyle.values, <AuthHeaderStyle>[
      AuthHeaderStyle.bearer,
      AuthHeaderStyle.firebase,
      AuthHeaderStyle.firebaseAuthToken,
    ]);
  });

  test('header value table', () {
    final List<String> accepted = <String>[
      'a',
      'a space inside',
      'two  spaces',
      '1:1234567890:web:abcdef',
      'AIzaSy-fake_api.key',
      '!',
      '~',
      '!"#\$%&\'()*+,-./:;<=>?@[\\]^_`{|}~',
      'a' * 8192,
      '${'a' * 4095} ${'a' * 4096}',
    ];
    for (final String value in accepted) {
      expect(isHeaderValue(value), isTrue, reason: '"$value"');
    }
    final List<String> refused = <String>[
      '',
      ' ',
      ' leading',
      'trailing ',
      ' both ',
      'a\rb',
      'a\nb',
      'a\r\nInjected: header',
      'a\u0000b',
      'a\tb',
      '\n',
      'a\u007Fb',
      'a\u001Fb',
      'a\u0080b',
      'café',
      'snow☃',
      'emoji\u{1F600}',
      'a' * 8193,
    ];
    for (final String value in refused) {
      expect(isHeaderValue(value), isFalse, reason: '"$value"');
    }
  });

  test('token text table', () {
    final List<String> accepted = <String>[
      'a',
      '!',
      '~',
      'eyJhbGciOiJub25lIn0.eyJzdWIiOiJmYWtlIn0.c2lnbmF0dXJl',
      'eyJlcnJvciI6IlVOS05PV05fRVJST1IifQ==',
      '!"#\$%&\'()*+,-./:;<=>?@[\\]^_`{|}~',
      'a' * 8192,
    ];
    for (final String value in accepted) {
      expect(isTokenText(value), isTrue, reason: '"$value"');
    }
    final List<String> refused = <String>[
      '',
      'a' * 8193,
      ' ',
      'a b',
      ' a',
      'a ',
      'a\rb',
      'a\nb',
      'a\r\nInjected: header',
      'a\u0000b',
      'a\tb',
      'a\u007F',
      'a\u001F',
      'a\u0080',
      'café',
      'snow☃',
      'emoji\u{1F600}',
    ];
    for (final String value in refused) {
      expect(isTokenText(value), isFalse, reason: '"$value"');
    }
  });

  test('every token text is a header value', () {
    for (int unit = 0; unit < 0x100; unit++) {
      final String value = 'a${String.fromCharCode(unit)}b';
      final bool visible = unit >= 0x21 && unit <= 0x7E;
      expect(
        isTokenText(value),
        visible,
        reason: 'U+${unit.toRadixString(16)}',
      );
      expect(
        isHeaderValue(value),
        visible || unit == 0x20,
        reason: 'U+${unit.toRadixString(16)}',
      );
    }
  });
}

void _apiClientTests() {
  test('apiClientHeader forms and its ArgumentError', () {
    expect(dartRuntimeVersion, isNotEmpty);
    expect(_clientPart.hasMatch(dartRuntimeVersion), isTrue);
    expect(
      apiClientHeader(sdkVersion: '0.1.0'),
      'gl-dart/$dartRuntimeVersion fire/0.1.0',
    );
    expect(
      apiClientHeader(sdkVersion: '0.1.0', extra: const <String>[]),
      'gl-dart/$dartRuntimeVersion fire/0.1.0',
    );
    expect(
      apiClientHeader(
        sdkVersion: '1.2.3-dev.4',
        extra: const <String>['fire-fn/0.1.0', 'grpc/5.1.0', 'x_y'],
      ),
      'gl-dart/$dartRuntimeVersion fire/1.2.3-dev.4 fire-fn/0.1.0 grpc/5.1.0 x_y',
    );
    expect(isHeaderValue(apiClientHeader(sdkVersion: '0.1.0')), isTrue);

    const List<String> badParts = <String>[
      '',
      ' ',
      '1.0 beta',
      ' 1.0',
      '1.0 ',
      '1.0\n',
      '1.0\r\nInjected: header',
      '1.0+build',
      '1.0;q=1',
      '1.0\u0000',
      'café',
    ];
    for (final String bad in badParts) {
      expect(
        () => apiClientHeader(sdkVersion: bad),
        throwsArgumentError,
        reason: 'sdkVersion "$bad"',
      );
      expect(
        () => apiClientHeader(sdkVersion: '0.1.0', extra: <String>[bad]),
        throwsArgumentError,
        reason: 'extra "$bad"',
      );
      expect(
        () => apiClientHeader(
          sdkVersion: '0.1.0',
          extra: <String>['fire-fn/0.1.0', bad],
        ),
        throwsArgumentError,
        reason: 'second extra "$bad"',
      );
    }
  });

  test('the apiClientHeader error does not repeat the value', () {
    const String marker = 'ZZQQXX';
    final String forVersion = _errorTextOf(
      () => apiClientHeader(sdkVersion: '$marker bad'),
    );
    expect(forVersion, isNot(contains(marker)));
    final String forExtra = _errorTextOf(
      () =>
          apiClientHeader(sdkVersion: '0.1.0', extra: <String>['$marker bad']),
    );
    expect(forExtra, isNot(contains(marker)));
  });
}

void _forTestingTests() {
  final Uri origin = Uri.parse('https://api.example.test');

  test('RequestTokens.forTesting refuses a value that is not token text', () {
    final List<String> bad = <String>[
      '',
      'a b',
      'a\rb',
      'a\nb',
      'a\u0000b',
      'a\u007F',
      'café',
      'a' * 8193,
    ];
    for (final String value in bad) {
      expect(
        () => RequestTokens.forTesting(origin: origin, authToken: value),
        throwsArgumentError,
        reason: 'authToken "$value"',
      );
      expect(
        () => RequestTokens.forTesting(origin: origin, appCheckToken: value),
        throwsArgumentError,
        reason: 'appCheckToken "$value"',
      );
      expect(
        () => RequestTokens.forTesting(
          origin: origin,
          authToken: 'FAKE-AUTH-TOKEN',
          appCheckToken: value,
        ),
        throwsArgumentError,
        reason: 'appCheckToken "$value" beside a good authToken',
      );
    }
  });

  test('the forTesting error does not repeat the value', () {
    const String marker = 'ZZQQXX';
    final String forAuth = _errorTextOf(
      () => RequestTokens.forTesting(origin: origin, authToken: '$marker bad'),
    );
    expect(forAuth, isNot(contains(marker)));
    final String forAppCheck = _errorTextOf(
      () => RequestTokens.forTesting(
        origin: origin,
        appCheckToken: '$marker\nbad',
      ),
    );
    expect(forAppCheck, isNot(contains(marker)));
  });

  test(
    'RequestTokens.forTesting gives tokens that behave like fetched ones',
    () {
      final RequestTokens tokens = RequestTokens.forTesting(
        origin: origin,
        authToken: 'a' * 8192,
        appCheckToken: 'FAKE-APPCHECK-TOKEN',
        appCheck: AppCheckOutcome.sent,
      );
      expect(tokens.hasAuthToken, isTrue);
      expect(tokens.appCheck, AppCheckOutcome.sent);
      expect(
        '$tokens',
        'RequestTokens(origin: https://api.example.test, auth: present, '
            'appCheck: sent)',
      );
      final Uri url = Uri.parse('https://api.example.test/v1/call');
      expect(
        tokens.headersFor(url, auth: AuthHeaderStyle.firebaseAuthToken),
        <String, String>{
          'X-Firebase-Auth-Token': 'a' * 8192,
          'X-Firebase-AppCheck': 'FAKE-APPCHECK-TOKEN',
        },
      );
      expect(
        () => tokens.headersFor(url, auth: AuthHeaderStyle.firebaseAuthToken),
        throwsStateError,
      );

      final RequestTokens none = RequestTokens.forTesting(origin: origin);
      expect(none.hasAuthToken, isFalse);
      expect(none.appCheck, AppCheckOutcome.none);
      expect(none.headersFor(url, auth: AuthHeaderStyle.bearer), isEmpty);
      expect(
        none.sameTokensAs(RequestTokens.forTesting(origin: origin)),
        isTrue,
      );
      expect(none.sameTokensAs(tokens), isFalse);
    },
  );

  test('reading 11: forTesting normalises origin through tokenOrigin', () {
    final RequestTokens fromSocket = RequestTokens.forTesting(
      origin: Uri.parse('wss://API.example.test:443/socket?x=1'),
      authToken: 'FAKE-AUTH-TOKEN',
    );
    expect('${fromSocket.origin}', 'https://api.example.test');
    expect(
      fromSocket.headersFor(
        Uri.parse('https://api.example.test/v1/call'),
        auth: AuthHeaderStyle.bearer,
      ),
      <String, String>{'Authorization': 'Bearer FAKE-AUTH-TOKEN'},
    );
    expect(
      '${RequestTokens.forTesting(origin: Uri.parse('ws://localhost:9000/s')).origin}',
      'http://localhost:9000',
    );
    expect(
      () => RequestTokens.forTesting(origin: Uri.parse('wss://h.test/socket')),
      throwsArgumentError,
    );
  });
}
