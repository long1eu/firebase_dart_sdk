// FirebaseAuthException.serverResponse: the answer kept on tagged errors, never printed with its tokens.

import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:test/test.dart';

void main() {
  const Map<String, Object?> answer = <String, Object?>{
    'email': 'a@example.com',
    'providerId': 'google.com',
    'oauthIdToken': 'secret-id-token',
    'oauthAccessToken': 'secret-access-token',
    'idToken': 'secret-firebase-token',
    'refreshToken': 'secret-refresh-token',
  };

  void expectNoSecret(Object? value) {
    expect('$value', isNot(contains('secret')));
  }

  test('a tagged error keeps the answer', () {
    for (final String server in <String>[
      'FEDERATED_USER_ID_ALREADY_LINKED',
      'EMAIL_EXISTS',
      'USER_DISABLED',
    ]) {
      final FirebaseAuthException e = FirebaseAuthException.fromServer(
        server,
        httpStatus: 400,
        response: answer,
      );
      expect(e.serverResponse, answer, reason: server);
      expect(e.serverResponse!['oauthAccessToken'], 'secret-access-token');
    }
  });

  test('needConfirmation keeps the answer', () {
    final FirebaseAuthException e = FirebaseAuthException.needConfirmation(
      const <String, Object?>{...answer, 'needConfirmation': true},
      httpStatus: 200,
    );
    expect(e.code, AuthErrorCode.accountExistsWithDifferentCredential);
    expect(e.serverResponse!['needConfirmation'], isTrue);
  });

  test('other errors have none', () {
    expect(
      FirebaseAuthException.fromServer(
        'INVALID_LOGIN_CREDENTIALS',
        httpStatus: 400,
        response: answer,
      ).serverResponse,
      isNull,
    );
  });

  test('the tokens are not printed and the answer cannot be changed', () {
    final Map<String, Object?> source = Map<String, Object?>.of(answer);
    final FirebaseAuthException e = FirebaseAuthException.fromServer(
      'FEDERATED_USER_ID_ALREADY_LINKED',
      httpStatus: 400,
      response: source,
    );
    expectNoSecret(e);
    expectNoSecret(e.message);
    expectNoSecret(e.serverResponse);
    expect('${e.serverResponse}', contains('oauthAccessToken: <redacted>'));
    expect(() => e.serverResponse!['idToken'] = 'x', throwsUnsupportedError);
    source['idToken'] = 'changed';
    expect(e.serverResponse!['idToken'], 'secret-firebase-token');
  });
}
