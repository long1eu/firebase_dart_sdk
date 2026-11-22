// The emulator credentials (rtdb_protocol.md 2.4; util:src/emulator.ts:95-142; probe "Auth":
// the emulator needs sub, iat and exp and reads the uid from sub).
import 'dart:convert';

import 'package:firebase_database_dart/src/realtime/emulator_token.dart';
import 'package:test/test.dart';

String decodePart(String part) =>
    utf8.decode(base64Url.decode(base64Url.normalize(part)));

void main() {
  test('the admin credential is the string owner (sent as gauth)', () {
    expect(ownerToken, 'owner');
  });

  group('createMockUserToken', () {
    test('layout: header, payload in JS key order, empty signature', () {
      final String token = createMockUserToken(<String, Object?>{
        'sub': 'u1',
      }, projectId: 'demo-test');
      final List<String> parts = token.split('.');
      expect(parts, hasLength(3));
      expect(parts[2], isEmpty);
      expect(token.endsWith('.'), isTrue);
      expect(decodePart(parts[0]), '{"alg":"none","type":"JWT"}');
      expect(
        decodePart(parts[1]),
        '{"iss":"https://securetoken.google.com/demo-test","aud":"demo-test",'
        '"iat":0,"exp":3600,"auth_time":0,"sub":"u1","user_id":"u1",'
        '"firebase":{"sign_in_provider":"custom","identities":{}}}',
      );
    });

    test('base64url without padding', () {
      for (final String sub in <String>['a', 'ab', 'abc', 'u?>~']) {
        final String token = createMockUserToken(<String, Object?>{
          'sub': sub,
        }, projectId: 'p');
        expect(token, isNot(contains('=')), reason: sub);
        expect(token, isNot(contains('+')), reason: sub);
        expect(token, isNot(contains('/')), reason: sub);
      }
    });

    test('user_id alone becomes sub (the emulator reads sub only)', () {
      final String token = createMockUserToken(<String, Object?>{
        'user_id': 'u2',
      }, projectId: 'p');
      final Map<String, Object?> payload =
          jsonDecode(decodePart(token.split('.')[1])) as Map<String, Object?>;
      expect(payload['sub'], 'u2');
      expect(payload['user_id'], 'u2');
    });

    test('iat sets exp and auth_time; claims override in place and extra '
        'claims come last', () {
      final String token = createMockUserToken(<String, Object?>{
        'sub': 'u1',
        'iat': 100,
        'aud': 'other',
        'admin': true,
        'email': 'a@b.c',
      }, projectId: 'p');
      final Map<String, Object?> payload =
          jsonDecode(decodePart(token.split('.')[1])) as Map<String, Object?>;
      expect(payload.keys.toList(), <String>[
        'iss',
        'aud',
        'iat',
        'exp',
        'auth_time',
        'sub',
        'user_id',
        'firebase',
        'admin',
        'email',
      ]);
      expect(payload['iat'], 100);
      expect(payload['exp'], 3700);
      expect(payload['auth_time'], 100);
      expect(payload['aud'], 'other');
      expect(payload['admin'], isTrue);
    });

    test('refuses uid, a missing or empty sub, a bad iat, an empty project, '
        'and non-JSON claims', () {
      final List<(Map<String, Object?>, String)> bad =
          <(Map<String, Object?>, String)>[
            (<String, Object?>{'uid': 'u1', 'sub': 'u1'}, 'p'),
            (<String, Object?>{}, 'p'),
            (<String, Object?>{'sub': ''}, 'p'),
            (<String, Object?>{'sub': 1}, 'p'),
            (<String, Object?>{'sub': 'u', 'iat': 1.5}, 'p'),
            (<String, Object?>{'sub': 'u', 'iat': '1'}, 'p'),
            (<String, Object?>{'sub': 'u'}, ''),
            (<String, Object?>{'sub': 'u', 'when': DateTime(2026)}, 'p'),
          ];
      for (final (Map<String, Object?> claims, String project) in bad) {
        expect(
          () => createMockUserToken(claims, projectId: project),
          throwsArgumentError,
          reason: '$claims',
        );
      }
    });

    test('an error does not quote a claim value', () {
      expect(
        () => createMockUserToken(<String, Object?>{
          'sub': 'u',
          'iat': 'secret-iat-marker',
        }, projectId: 'p'),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.toString(),
            'toString',
            isNot(contains('secret-iat-marker')),
          ),
        ),
      );
    });
  });
}
