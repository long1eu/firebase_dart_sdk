// Owner P. Threat model T7/T8 for PersistentConnection: across a whole session (connect, auth,
// App Check, data, a server error, a shutdown) no log line and no toString holds a token, a
// session id or user data; credential requests are logged as "<action> (contents hidden)".
import 'package:test/test.dart';

import '../util/persistent_connection_harness.dart';

/// Claims {"iat":0,"sub":"u1","marker":"AUTH"}: accepted by the server as `auth`.
const String _authToken =
    'eyJhbGciOiJub25lIn0.eyJpYXQiOjAsInN1YiI6InUxIiwibWFya2VyIjoiQVVUSCJ9.AUTHMARK';

/// Not a JWT: the server refuses it, so the refusal path is in the log too.
const String _appCheckToken = 'APPCHECK-MARKER-TOKEN';
const String _secret = 'SECRET-USER-DATA';

void main() {
  test('no token, session id or user data in any log line or toString', () async {
    // Both layers log to the same logger, as in production.
    final PRig rig = PRig(logConnection: true)
      ..tokens.auth = _authToken
      ..tokens.appCheck = _appCheckToken;
    await rig.start();
    await until(() => rig.delegate.callsOf('appCheckStatus').isNotEmpty);
    expect(
      rig.delegate.callsOf('appCheckStatus').single.status,
      'invalid_token',
    );
    rig.connection.put('/a', _secret);
    rig.connection.merge('/b', <String, Object?>{'k': _secret});
    rig.connection.onDisconnectPut('/c', _secret);
    rig.server.pushData('/a', _secret);
    rig.tokens.emitAuth('$_authToken-2');
    await rig.settle();
    rig.server.pushShutdown('shutting down');
    await until(() => rig.delegate.callsOf('serverShutdown').isNotEmpty);

    final String everything = <String>[
      ...rig.logs,
      rig.connection.toString(),
    ].join('\n');
    for (final String marker in <String>[
      'AUTHMARK',
      'APPCHECK-MARKER',
      'sess-1',
      _secret,
    ]) {
      expect(everything, isNot(contains(marker)), reason: marker);
    }
    // Every credential request was logged, by each layer, and only as its action: the first
    // auth, the appcheck, the auth of the changed token.
    expect(
      rig.logs.where((String l) => l.contains('(contents hidden)')),
      <String>[
        for (final String action in <String>[
          'auth',
          'appcheck',
          'auth',
        ]) ...<String>[
          'debug: $action (contents hidden)',
          'debug: $action (contents hidden)',
        ],
      ],
    );
    await rig.connection.shutdown();
  });

  test('a token provider failure is logged by type only', () async {
    final PRig rig = PRig();
    rig.tokens.error = Exception('token AUTHMARK leaked');
    rig.connection.initialize();
    await until(() => rig.tokens.authCalls.length >= 2);
    // The failure was logged (so the check below looks at a line that exists), by its type.
    expect(
      rig.logs.where(
        (String l) => l.startsWith('warning: Failed to get a token: '),
      ),
      isNotEmpty,
    );
    expect(rig.logs.join('\n'), isNot(contains('AUTHMARK')));
    await rig.connection.shutdown();
  });
}
