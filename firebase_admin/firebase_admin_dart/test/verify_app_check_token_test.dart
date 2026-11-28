// verifyToken of FirebaseAppCheckAdmin: tokens signed in the test by keys that a fake of the App Check JWKS
// endpoint serves.

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:firebase_admin_dart/app_check.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'app_check_keys.dart';
import 'fake_backend.dart';
import 'support.dart';

Matcher throwsAppCheck(String code, [Object? message]) => throwsA(
  isA<FirebaseAppCheckAdminException>()
      .having((FirebaseAppCheckAdminException e) => e.code, 'code', code)
      .having(
        (FirebaseAppCheckAdminException e) => e.plugin,
        'plugin',
        'app-check',
      )
      .having(
        (FirebaseAppCheckAdminException e) => e.message,
        'message',
        message ?? anything,
      ),
);

Map<String, Object?> jwk(
  TestKey key,
  String kid, {
  Map<String, Object?> extra = const <String, Object?>{},
}) => <String, Object?>{
  'kty': 'RSA',
  'use': 'sig',
  'alg': 'RS256',
  'kid': kid,
  'n': b64url(bytesOf(key.n, key.length)),
  'e': b64url(bytesOf(key.e, 3)),
  ...extra,
};

void main() {
  final TestKey key = appCheckKey1;
  final TestKey other = appCheckKey2;
  // Signs the service account's assertions; App Check needs no credential.
  final TestKey credentialKey = TestKey();
  late FakeBackend backend;
  late FakeClock clock;
  late List<Map<String, Object?>> keys;
  late int jwksStatus;
  late FirebaseAdminApp app;

  setUp(() {
    backend = FakeBackend();
    clock = FakeClock(DateTime.utc(2026, 11, 28, 12));
    keys = <Map<String, Object?>>[jwk(key, 'kid-1')];
    jwksStatus = 200;
    backend.on(
      'firebaseappcheck.googleapis.com',
      '/v1/jwks',
      (http.Request request) async =>
          FakeBackend.json(<String, Object?>{'keys': keys}, jwksStatus),
    );
    app = FirebaseAdminApp(
      projectId: 'demo-test',
      credential: AdminCredential.serviceAccount(
        credentialKey.serviceAccount(),
      ),
      httpClient: backend.client,
      clock: clock.call,
    );
  });

  Map<String, Object?> claims({
    Map<String, Object?> extra = const <String, Object?>{},
  }) {
    final int now = clock.now.millisecondsSinceEpoch ~/ 1000;
    return <String, Object?>{
      'iss': 'https://firebaseappcheck.googleapis.com/123456789',
      'aud': <String>['projects/123456789', 'projects/demo-test'],
      'sub': '1:123456789:web:abcdef',
      'iat': now - 60,
      'exp': now + 3600,
      ...extra,
    };
  }

  const Map<String, Object?> header = <String, Object?>{
    'alg': 'RS256',
    'kid': 'kid-1',
    'typ': 'JWT',
  };

  String token({
    Map<String, Object?> extra = const <String, Object?>{},
    Map<String, Object?> header = header,
    TestKey? signer,
  }) => jwt(header, claims(extra: extra), signer ?? key);

  Future<VerifiedAppCheckToken> verify(String token, {String? projectNumber}) =>
      app.appCheck().verifyToken(token, projectNumber: projectNumber);

  test('a valid token gives the app id and the claims', () async {
    final VerifiedAppCheckToken verified = await verify(token());
    expect(verified.appId, '1:123456789:web:abcdef');
    expect(verified.projectNumber, '123456789');
    expect(verified.audience, <String>[
      'projects/123456789',
      'projects/demo-test',
    ]);
    expect(verified.expiresAt, clock.now.add(const Duration(hours: 1)));
    expect(verified.issuedAt, clock.now.subtract(const Duration(minutes: 1)));
    expect(
      verified.toString(),
      'VerifiedAppCheckToken(appId: 1:123456789:web:abcdef)',
    );
    expect(() => verified.claims['sub'] = 'x', throwsUnsupportedError);
  });

  test('app.appCheck() is the same object for the same app', () {
    expect(identical(app.appCheck(), FirebaseAppCheckAdmin(app)), isTrue);
  });

  group('header and signature', () {
    test('alg "none" is refused', () async {
      await expectLater(
        verify(
          jwt(<String, Object?>{'alg': 'none', 'typ': 'JWT'}, claims(), null),
        ),
        throwsAppCheck('invalid-argument', contains('unsigned')),
      );
      await expectLater(
        verify(
          jwt(
            <String, Object?>{'alg': 'none', 'kid': 'kid-1', 'typ': 'JWT'},
            claims(),
            key,
          ),
        ),
        throwsAppCheck('invalid-argument', contains('unsigned')),
      );
    });

    test(
      'HS256 signed with the public key (algorithm confusion) is refused',
      () async {
        const Map<String, Object?> hs = <String, Object?>{
          'alg': 'HS256',
          'kid': 'kid-1',
          'typ': 'JWT',
        };
        final String input = '${segment(hs)}.${segment(claims())}';
        final List<int> mac = Hmac(
          sha256,
          utf8.encode(jsonEncode(jwk(key, 'kid-1'))),
        ).convert(ascii.encode(input)).bytes;
        await expectLater(
          verify('$input.${b64url(mac)}'),
          throwsAppCheck('invalid-argument', contains('RS256')),
        );
      },
    );

    test('a missing or wrong typ is refused', () async {
      await expectLater(
        verify(
          token(header: <String, Object?>{'alg': 'RS256', 'kid': 'kid-1'}),
        ),
        throwsAppCheck('invalid-argument', contains('typ')),
      );
      await expectLater(
        verify(
          token(
            header: <String, Object?>{
              'alg': 'RS256',
              'kid': 'kid-1',
              'typ': 'at+jwt',
            },
          ),
        ),
        throwsAppCheck('invalid-argument', contains('typ')),
      );
    });

    test('a kid that is missing or not among the keys is refused', () async {
      await expectLater(
        verify(token(header: <String, Object?>{'alg': 'RS256', 'typ': 'JWT'})),
        throwsAppCheck('invalid-argument', contains('"kid"')),
      );
      await expectLater(
        verify(
          token(
            header: <String, Object?>{
              'alg': 'RS256',
              'kid': 'kid-2',
              'typ': 'JWT',
            },
          ),
        ),
        throwsAppCheck('invalid-argument', contains('does not match')),
      );
    });

    test('a signature by another key is refused', () async {
      await expectLater(
        verify(token(signer: other)),
        throwsAppCheck('invalid-argument', contains('signature')),
      );
    });

    test('a changed payload breaks the signature', () async {
      final List<String> parts = token().split('.');
      final String forged = segment(
        claims(extra: <String, Object?>{'sub': '1:999:web:evil'}),
      );
      await expectLater(
        verify('${parts[0]}.$forged.${parts[2]}'),
        throwsAppCheck('invalid-argument', contains('signature')),
      );
    });

    test('malformed tokens are refused without quoting them', () async {
      for (final String bad in <String>[
        '',
        'a.b',
        'a.b.c.d',
        'not-base64!.x.y',
        '${'a' * 20000}.b.c',
      ]) {
        await expectLater(
          verify(bad),
          throwsA(
            isA<FirebaseAppCheckAdminException>()
                .having(
                  (FirebaseAppCheckAdminException e) => e.code,
                  'code',
                  'invalid-argument',
                )
                .having(
                  (FirebaseAppCheckAdminException e) => e.message,
                  'message',
                  bad.length > 3 ? isNot(contains(bad)) : anything,
                ),
          ),
          reason: bad.length > 40 ? 'a long token' : bad,
        );
      }
    });
  });

  group('claims', () {
    test('an audience of another project is refused', () async {
      await expectLater(
        verify(
          token(
            extra: <String, Object?>{
              'aud': <String>['projects/other', 'projects/42'],
            },
          ),
        ),
        throwsAppCheck('invalid-argument', contains('audience')),
      );
    });

    test('an audience that is a string, not a list, is refused', () async {
      await expectLater(
        verify(token(extra: <String, Object?>{'aud': 'projects/demo-test'})),
        throwsAppCheck('invalid-argument', contains('audience')),
      );
    });

    test(
      'the project number is accepted in aud only when it is given',
      () async {
        final String byNumber = token(
          extra: <String, Object?>{
            'aud': <String>['projects/123456789'],
          },
        );
        await expectLater(
          verify(byNumber),
          throwsAppCheck('invalid-argument', contains('audience')),
        );
        expect(
          (await verify(byNumber, projectNumber: '123456789')).appId,
          isNotEmpty,
        );
      },
    );

    test(
      'the issuer must be the App Check issuer and a number, and the given number',
      () async {
        for (final String iss in <String>[
          'https://securetoken.google.com/demo-test',
          'https://firebaseappcheck.googleapis.com/',
          'https://firebaseappcheck.googleapis.com/demo-test',
          'https://firebaseappcheck.googleapis.com/123/../456',
          'https://firebaseappcheck.googleapis.com.evil.example/123',
        ]) {
          await expectLater(
            verify(token(extra: <String, Object?>{'iss': iss})),
            throwsAppCheck('invalid-argument', contains('issuer')),
            reason: iss,
          );
        }
        await expectLater(
          verify(token(), projectNumber: '987654321'),
          throwsAppCheck('invalid-argument', contains('987654321')),
        );
        await expectLater(verify(token()), completes);
      },
    );

    test('an empty or missing sub is refused', () async {
      await expectLater(
        verify(token(extra: <String, Object?>{'sub': ''})),
        throwsAppCheck('invalid-argument', contains('subject')),
      );
      await expectLater(
        verify(token(extra: <String, Object?>{'sub': 42})),
        throwsAppCheck('invalid-argument', contains('subject')),
      );
    });

    test(
      'an expired token is refused with its own code; within the clock skew it passes',
      () async {
        final int now = clock.now.millisecondsSinceEpoch ~/ 1000;
        await expectLater(
          verify(token(extra: <String, Object?>{'exp': now - 11})),
          throwsAppCheck('app-check-token-expired'),
        );
        expect(
          await verify(token(extra: <String, Object?>{'exp': now - 9})),
          isA<VerifiedAppCheckToken>(),
        );
      },
    );

    test('a token issued in the future is refused', () async {
      final int now = clock.now.millisecondsSinceEpoch ~/ 1000;
      await expectLater(
        verify(token(extra: <String, Object?>{'iat': now + 60})),
        throwsAppCheck('invalid-argument', contains('"iat"')),
      );
    });

    test('an exp that JSON reads as infinity is refused', () async {
      final String payload = b64url(
        utf8.encode(
          jsonEncode(
            claims(),
          ).replaceFirst(RegExp(r'"exp":\d+'), '"exp":1e999'),
        ),
      );
      final String input = '${segment(header)}.$payload';
      await expectLater(
        verify('$input.${b64url(key.sign(ascii.encode(input)))}'),
        throwsAppCheck('invalid-argument', contains('times in seconds')),
      );
    });

    test('missing exp or iat is refused', () async {
      final Map<String, Object?> noExp = claims()..remove('exp');
      await expectLater(
        verify(jwt(header, noExp, key)),
        throwsAppCheck('invalid-argument', contains('times in seconds')),
      );
    });
  });

  group('keys', () {
    test('are fetched once and kept for six hours', () async {
      await verify(token());
      await verify(token());
      expect(backend.to('firebaseappcheck.googleapis.com'), hasLength(1));
      clock.advance(const Duration(hours: 5, minutes: 59));
      await verify(token());
      expect(backend.to('firebaseappcheck.googleapis.com'), hasLength(1));
      clock.advance(const Duration(minutes: 2));
      await verify(token());
      expect(backend.to('firebaseappcheck.googleapis.com'), hasLength(2));
    });

    test('concurrent checks share one fetch', () async {
      await Future.wait(<Future<VerifiedAppCheckToken>>[
        verify(token()),
        verify(token()),
        verify(token()),
      ]);
      expect(backend.to('firebaseappcheck.googleapis.com'), hasLength(1));
    });

    test('a failed fetch is internal-error and is not kept', () async {
      jwksStatus = 503;
      await expectLater(
        verify(token()),
        throwsAppCheck('internal-error', contains('HTTP 503')),
      );
      jwksStatus = 200;
      clock.advance(const Duration(seconds: 31));
      expect(await verify(token()), isA<VerifiedAppCheckToken>());
    });

    test('an answer that is not a key set is internal-error', () async {
      backend.on(
        'firebaseappcheck.googleapis.com',
        '/v1/jwks',
        (http.Request request) async => http.Response('<html>', 200),
      );
      await expectLater(
        verify(token()),
        throwsAppCheck('internal-error', contains('JSON Web Key Set')),
      );
    });

    test('keys of another type, algorithm or use are left out', () async {
      keys = <Map<String, Object?>>[
        jwk(key, 'kid-1', extra: <String, Object?>{'alg': 'RS512'}),
        jwk(key, 'kid-1b', extra: <String, Object?>{'use': 'enc'}),
        <String, Object?>{
          'kty': 'EC',
          'kid': 'kid-ec',
          'crv': 'P-256',
          'x': 'AA',
          'y': 'AA',
        },
        jwk(other, 'kid-3'),
      ];
      await expectLater(
        verify(token()),
        throwsAppCheck('invalid-argument', contains('does not match')),
      );
    });
  });

  test('clockSkew and projectNumber are checked', () {
    expect(
      () => app.appCheck().verifyToken(
        token(),
        clockSkew: const Duration(minutes: 6),
      ),
      throwsArgumentError,
    );
    expect(
      () => app.appCheck().verifyToken(token(), projectNumber: 'demo-test'),
      throwsArgumentError,
    );
  });

  group('more refusals', () {
    test(
      'RS512, PS256 and ES256 headers over a valid RS256 signature are refused',
      () async {
        for (final String alg in <String>['RS512', 'PS256', 'ES256', 'rs256']) {
          await expectLater(
            verify(
              token(
                header: <String, Object?>{
                  'alg': alg,
                  'kid': 'kid-1',
                  'typ': 'JWT',
                },
              ),
            ),
            throwsAppCheck('invalid-argument', contains('RS256')),
            reason: alg,
          );
        }
      },
    );

    test('RS256 with an empty signature is refused', () async {
      final List<String> parts = token().split('.');
      await expectLater(
        verify('${parts[0]}.${parts[1]}.'),
        throwsAppCheck('invalid-argument', contains('unsigned')),
      );
    });

    test('a signature with an extra leading zero byte is refused', () async {
      final List<String> parts = token().split('.');
      final List<int> signature = base64Url.decode(
        base64Url.normalize(parts[2]),
      );
      await expectLater(
        verify('${parts[0]}.${parts[1]}.${b64url(<int>[0, ...signature])}'),
        throwsAppCheck('invalid-argument', contains('signature')),
      );
    });

    test('nbf in the future is refused; in the past it passes', () async {
      final int now = clock.now.millisecondsSinceEpoch ~/ 1000;
      await expectLater(
        verify(token(extra: <String, Object?>{'nbf': now + 600})),
        throwsAppCheck('invalid-argument', contains('"nbf"')),
      );
      expect(
        await verify(token(extra: <String, Object?>{'nbf': now - 60})),
        isA<VerifiedAppCheckToken>(),
      );
    });

    test('exp before iat, and times out of range, are refused', () async {
      final int now = clock.now.millisecondsSinceEpoch ~/ 1000;
      await expectLater(
        verify(
          token(
            extra: <String, Object?>{
              'iat': now - 10,
              'exp': now - 20 + 3600 - 3600,
            },
          ),
        ),
        throwsA(isA<FirebaseAppCheckAdminException>()),
      );
      await expectLater(
        verify(token(extra: <String, Object?>{'exp': 1e300})),
        throwsAppCheck('invalid-argument', contains('times in seconds')),
      );
      await expectLater(
        verify(token(extra: <String, Object?>{'iat': -5})),
        throwsAppCheck('invalid-argument', contains('times in seconds')),
      );
      await expectLater(
        verify(token(extra: <String, Object?>{'exp': '9999999999'})),
        throwsAppCheck('invalid-argument', contains('times in seconds')),
      );
    });

    test(
      'iat within the clock skew passes; a wider skew accepts a later expiry',
      () async {
        final int now = clock.now.millisecondsSinceEpoch ~/ 1000;
        expect(
          await verify(token(extra: <String, Object?>{'iat': now + 5})),
          isA<VerifiedAppCheckToken>(),
        );
        final String expired = token(
          extra: <String, Object?>{'iat': now - 600, 'exp': now - 60},
        );
        await expectLater(
          verify(expired),
          throwsAppCheck('app-check-token-expired'),
        );
        expect(
          await app.appCheck().verifyToken(
            expired,
            clockSkew: const Duration(minutes: 2),
          ),
          isA<VerifiedAppCheckToken>(),
        );
      },
    );

    test(
      'audience entries that are not strings are left out of the getter',
      () async {
        final VerifiedAppCheckToken verified = await verify(
          token(
            extra: <String, Object?>{
              'aud': <Object?>[null, 7, 'projects/demo-test'],
            },
          ),
        );
        expect(verified.audience, <String>['projects/demo-test']);
      },
    );
  });

  group('key set robustness', () {
    test('a malformed key next to a good one is skipped', () async {
      keys = <Map<String, Object?>>[
        jwk(key, 'bad-e', extra: <String, Object?>{'e': 'AQ'}),
        jwk(key, 'bad-n', extra: <String, Object?>{'n': ''}),
        jwk(key, 'bad-b64', extra: <String, Object?>{'n': 'not base64!'}),
        jwk(key, 'kid-1'),
      ];
      expect(await verify(token()), isA<VerifiedAppCheckToken>());
    });

    test(
      'keys under 2048 bits, with an even exponent or a huge exponent are not used',
      () async {
        final TestKey small = TestKey();
        keys = <Map<String, Object?>>[
          jwk(small, 'kid-1'),
          jwk(
            key,
            'kid-even',
            extra: <String, Object?>{
              'e': b64url(<int>[1, 0, 0]),
            },
          ),
          jwk(
            key,
            'kid-big-e',
            extra: <String, Object?>{'e': b64url(List<int>.filled(64, 0xff))},
          ),
          jwk(other, 'kid-ok'),
        ];
        await expectLater(
          verify(jwt(header, claims(), small)),
          throwsAppCheck('invalid-argument', contains('does not match')),
        );
        for (final String kid in <String>['kid-even', 'kid-big-e']) {
          await expectLater(
            verify(
              token(
                header: <String, Object?>{
                  'alg': 'RS256',
                  'kid': kid,
                  'typ': 'JWT',
                },
              ),
            ),
            throwsAppCheck('invalid-argument', contains('does not match')),
            reason: kid,
          );
        }
      },
    );

    test(
      'a set without usable keys, or without "keys", is internal-error',
      () async {
        backend.on(
          'firebaseappcheck.googleapis.com',
          '/v1/jwks',
          (http.Request request) async =>
              FakeBackend.json(<String, Object?>{'other': <Object?>[]}),
        );
        await expectLater(verify(token()), throwsAppCheck('internal-error'));
      },
    );

    test('an answer over 1 MiB is refused', () async {
      backend.on(
        'firebaseappcheck.googleapis.com',
        '/v1/jwks',
        (http.Request request) async =>
            http.Response('{"keys":[${'0,' * (600 * 1024)}0]}', 200),
      );
      await expectLater(
        verify(token()),
        throwsAppCheck('internal-error', contains('too large')),
      );
    });

    test('a streamed answer over 1 MiB without a length is refused', () async {
      final FirebaseAdminApp streaming = FirebaseAdminApp(
        projectId: 'demo-test',
        credential: AdminCredential.serviceAccount(
          credentialKey.serviceAccount(),
        ),
        httpClient: MockClient.streaming((
          http.BaseRequest request,
          http.ByteStream body,
        ) async {
          return http.StreamedResponse(
            Stream<List<int>>.fromIterable(
              List<List<int>>.generate(
                20,
                (_) => List<int>.filled(64 * 1024, 32),
              ),
            ),
            200,
          );
        }),
        clock: clock.call,
      );
      await expectLater(
        streaming.appCheck().verifyToken(token()),
        throwsAppCheck('internal-error', contains('too large')),
      );
    });

    test('a network error is internal-error', () async {
      backend.on(
        'firebaseappcheck.googleapis.com',
        '/v1/jwks',
        (http.Request request) async => throw http.ClientException('down'),
      );
      await expectLater(verify(token()), throwsAppCheck('internal-error'));
    });

    test(
      'after a failed fetch, checks fail for 30 seconds without fetching again',
      () async {
        jwksStatus = 503;
        for (int i = 0; i < 5; i++) {
          await expectLater(verify(token()), throwsAppCheck('internal-error'));
        }
        expect(backend.to('firebaseappcheck.googleapis.com'), hasLength(1));
        jwksStatus = 200;
        clock.advance(const Duration(seconds: 31));
        expect(await verify(token()), isA<VerifiedAppCheckToken>());
        expect(backend.to('firebaseappcheck.googleapis.com'), hasLength(2));
      },
    );

    test(
      'a failed refetch for an unknown kid keeps the current keys',
      () async {
        await verify(token());
        jwksStatus = 503;
        await expectLater(
          verify(
            token(
              header: <String, Object?>{
                'alg': 'RS256',
                'kid': 'made-up',
                'typ': 'JWT',
              },
            ),
          ),
          throwsAppCheck('invalid-argument', contains('does not match')),
        );
        expect(backend.to('firebaseappcheck.googleapis.com'), hasLength(2));
        expect(await verify(token()), isA<VerifiedAppCheckToken>());
        expect(backend.to('firebaseappcheck.googleapis.com'), hasLength(2));
      },
    );

    test(
      'an unknown kid fetches the set again at most once per five minutes',
      () async {
        await verify(token());
        keys = <Map<String, Object?>>[jwk(key, 'kid-1'), jwk(other, 'kid-new')];
        final String fresh = token(
          header: <String, Object?>{
            'alg': 'RS256',
            'kid': 'kid-new',
            'typ': 'JWT',
          },
          signer: other,
        );
        expect(await verify(fresh), isA<VerifiedAppCheckToken>());
        expect(backend.to('firebaseappcheck.googleapis.com'), hasLength(2));
        for (int i = 0; i < 5; i++) {
          await expectLater(
            verify(
              token(
                header: <String, Object?>{
                  'alg': 'RS256',
                  'kid': 'kid-random-$i',
                  'typ': 'JWT',
                },
              ),
            ),
            throwsAppCheck('invalid-argument', contains('does not match')),
          );
        }
        expect(backend.to('firebaseappcheck.googleapis.com'), hasLength(2));
      },
    );
  });
}
