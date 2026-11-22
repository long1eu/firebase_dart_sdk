// Owner K. Threat model T7 and T8, the rows of leakage_test.dart for K's types: no token, session
// data or snapshot data in a toString or an error message, and server text cleaned before it can
// reach a log line.
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_database_dart/src/realtime/auth_session.dart';
import 'package:firebase_database_dart/src/realtime/connection_timings.dart';
import 'package:firebase_database_dart/src/realtime/server_message.dart';
import 'package:test/test.dart';

import '../util/fakes.dart';

const String _marker = 'SECRET-MARKER-7f3a';

void main() {
  test('decoded records show no data, explanation or query', () {
    final List<Object?> messages = <Object?>[
      <String, Object?>{
        'r': 1,
        'b': <String, Object?>{
          's': 'ok',
          'd': <String, Object?>{'v': _marker},
        },
      },
      <String, Object?>{
        'r': 1,
        'b': <String, Object?>{'s': 'permission_denied', 'd': _marker},
      },
      <String, Object?>{
        'a': 'd',
        'b': <String, Object?>{'p': 'a', 'd': _marker},
      },
      <String, Object?>{
        'a': 'm',
        'b': <String, Object?>{
          'p': 'a',
          'd': <String, Object?>{'x': _marker},
        },
      },
      <String, Object?>{
        'a': 'c',
        'b': <String, Object?>{
          'p': 'a',
          'q': <Object?>[
            <String, Object?>{'sp': _marker},
          ],
        },
      },
      <String, Object?>{
        'a': 'ac',
        'b': <String, Object?>{'s': 'invalid_token', 'd': _marker},
      },
      <String, Object?>{
        'a': 'apc',
        'b': <String, Object?>{'s': 'invalid_token', 'd': _marker},
      },
      <String, Object?>{
        'a': 'sd',
        'b': <String, Object?>{'msg': _marker},
      },
      <String, Object?>{'error': _marker},
      <String, Object?>{
        'a': 'rm',
        'b': <String, Object?>{
          'p': 'a',
          'd': <Object?>[
            <String, Object?>{'m': _marker},
          ],
        },
      },
      <String, Object?>{'a': _marker, 'b': <String, Object?>{}},
      <String, Object?>{
        'a': 'd',
        'b': <String, Object?>{'p': '$_marker#', 'd': 1},
      },
    ];
    for (final Object? message in messages) {
      final ServerMessage decoded = decodeServerMessage(message);
      expect('$decoded', isNot(contains(_marker)), reason: '$decoded');
      if (decoded is Ignored) {
        expect(decoded.why, isNot(contains(_marker)));
      }
    }
  });

  test('AuthSession, the token source and sent requests hide tokens', () {
    final RecordingSender sender = RecordingSender();
    final AuthSession session = AuthSession(
      sender.send,
      FakeTokenSource(auth: _marker),
      invalidTokenThreshold: 3,
      protocol: const RealtimeProtocol(isUsingEmulator: false),
      onAuthStatus: (_, _) {},
      onAppCheckStatus: (_, _) {},
    );
    session.authChanged(_marker);
    session.appCheckChanged(_marker);
    session.onConnected();
    expect('$session', isNot(contains(_marker)));
    expect(sender.sent, hasLength(2));
    for (final SentRequest request in sender.sent) {
      expect('$request', isNot(contains(_marker)));
    }
    final ProviderTokenSource source = ProviderTokenSource(
      auth: FakeAuth(<String?>[_marker]),
      appCheck: FakeAppCheck(_marker),
      forcedRefreshMinInterval: const Duration(seconds: 60),
      now: () => DateTime.utc(2026),
    );
    expect('$source', isNot(contains(_marker)));
  });

  test(
    'a token provider failure does not carry the provider message (T8)',
    () async {
      final ProviderTokenSource source = ProviderTokenSource(
        auth: FakeAuth(<String?>['t'], error: StateError('auth said $_marker')),
        appCheck: FakeAppCheck(
          't',
          error: Exception('app check said $_marker'),
        ),
        forcedRefreshMinInterval: const Duration(seconds: 60),
        now: () => DateTime.utc(2026),
      );
      for (final Future<String?> Function() fetch
          in <Future<String?> Function()>[
            () => source.authToken(forceRefresh: false),
            () => source.appCheckToken(forceRefresh: false),
          ]) {
        Object? error;
        try {
          await fetch();
        } on Object catch (e) {
          error = e;
        }
        expect(error, isA<StateError>());
        expect('$error', isNot(contains(_marker)));
      }
    },
  );

  test('a firebase error other than the no-user ones is hidden too', () async {
    final ProviderTokenSource source = ProviderTokenSource(
      auth: FakeAuth(<String?>[
        't',
      ], error: FirebaseException(plugin: 'auth', code: 'x', message: _marker)),
      forcedRefreshMinInterval: const Duration(seconds: 60),
      now: () => DateTime.utc(2026),
    );
    await expectLater(
      source.authToken(forceRefresh: false),
      throwsA(
        isA<StateError>().having(
          (StateError e) => e.message,
          'message',
          isNot(contains(_marker)),
        ),
      ),
    );
  });

  test('server text cannot forge a log line', () {
    final ServerMessage decoded = decodeServerMessage(<String, Object?>{
      'a': 'sd',
      'b': <String, Object?>{'msg': 'ok\n[ERROR] forged line\r\n'},
    });
    final String message = (decoded as SecurityDebugPush).message;
    expect(message, isNot(contains('\n')));
    expect(message, isNot(contains('\r')));
  });
}
