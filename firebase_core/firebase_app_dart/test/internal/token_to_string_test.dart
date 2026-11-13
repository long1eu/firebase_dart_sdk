// Security review: the string form of a token result must not contain the
// token, so that printing or logging the object (or an error message built
// from it) does not leak a credential.

import 'dart:convert';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:test/test.dart';

String _jwt(Map<String, Object?> claims) {
  String part(Object? value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part(<String, Object?>{'alg': 'RS256'})}.${part(claims)}.c2lnbmF0dXJl';
}

void main() {
  test('GetTokenResult.toString() does not contain the token', () {
    final String token = _jwt(<String, Object?>{
      'sub': 'alice',
      'email': 'alice@example.com',
      'exp': 1700003600,
    });
    final GetTokenResult result = GetTokenResult(token);
    expect(result.token, token);

    final String text = result.toString();
    expect(text, isNot(contains(token)));
    for (final String part in token.split('.')) {
      expect(text, isNot(contains(part)));
    }
    // Claims are personal data (email, uid): not printed either.
    expect(text, isNot(contains('alice')));
    expect(text, contains('GetTokenResult'));
  });

  test('InternalTokenResult.toString() does not contain the token', () {
    const InternalTokenResult result = InternalTokenResult('secret-token');
    expect(result.toString(), isNot(contains('secret-token')));
    expect(result.toString(), contains('InternalTokenResult'));
  });

  test('AppCheckTokenResult.toString() does not contain the token', () {
    const AppCheckTokenResult result = AppCheckTokenResult('app-check-secret');
    expect(result.toString(), isNot(contains('app-check-secret')));
  });
}
