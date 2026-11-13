import 'dart:convert';

import 'package:firebase_app_dart/src/internal/auth.dart';
import 'package:firebase_app_dart/src/internal/util/base64_utils.dart';
import 'package:test/test.dart';

String _jwt(Map<String, dynamic> claims) {
  String enc(Object o) =>
      base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${enc(<String, String>{'alg': 'none'})}.${enc(claims)}.sig';
}

void main() {
  test('missing claims do not throw', () {
    final GetTokenResult result = GetTokenResult(
      _jwt(<String, dynamic>{'firebase': <String, dynamic>{}}),
    );
    expect(result.signInProvider, isNull);
    expect(result.extraClaims, isEmpty);
    expect(result.expirationTimestamp, DateTime.fromMillisecondsSinceEpoch(0));
  });

  test('sign in provider is read from the firebase element or the root', () {
    expect(
      GetTokenResult(
        _jwt(<String, dynamic>{
          'firebase': <String, dynamic>{'sign_in_provider': 'password'},
        }),
      ).signInProvider,
      'password',
    );
    expect(
      GetTokenResult(
        _jwt(<String, dynamic>{'sign_in_provider': 'custom'}),
      ).signInProvider,
      'custom',
    );
  });

  test('numeric claims may be doubles', () {
    final GetTokenResult result = GetTokenResult(
      _jwt(<String, dynamic>{'exp': 1700000000.0, 'iat': 5}),
    );
    expect(
      result.expirationTimestamp,
      DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000),
    );
    expect(result.issuedAtTimestamp, DateTime.fromMillisecondsSinceEpoch(5000));
  });

  test('extra claims are returned', () {
    expect(
      GetTokenResult(
        _jwt(<String, dynamic>{
          'extra_claims': <String, dynamic>{'a': 1},
        }),
      ).extraClaims,
      <String, dynamic>{'a': 1},
    );
  });

  test('tokens that are not a JWT have no claims', () {
    for (final String token in <String>['opaque', 'a.b.c', 'a.!!.c', '..']) {
      final GetTokenResult result = GetTokenResult(token);
      expect(result.token, token);
      expect(result.claims, isEmpty);
      expect(result.signInProvider, isNull);
    }
  });

  test('Base64Utils.encodeUrlSafeNoPadding is URL safe and unpadded', () {
    expect(
      Base64Utils.encodeUrlSafeNoPadding(<int>[0xfb, 0xff, 0xfe, 1]),
      '-__-AQ',
    );
    expect(Base64Utils.encodeUrlSafeNoPadding(null), isNull);
  });
}
