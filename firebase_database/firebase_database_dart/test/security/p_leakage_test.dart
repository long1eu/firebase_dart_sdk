// Owner P. Threat model T7/T8 for PersistentConnection: across a whole session (connect, auth,
// App Check, data, a server error, a shutdown) no log line and no toString holds a token, a
// session id or user data; credential requests are logged as "<action> (contents hidden)".
import 'package:test/test.dart';

import '../util/persistent_connection_harness.dart';

const String _authToken =
    'eyJhbGciOiJub25lIn0.eyJpYXQiOjAsIm1hcmtlciI6IkFVVEgifQ.AUTHMARK';
const String _appCheckToken = 'APPCHECK-MARKER-TOKEN';
const String _secret = 'SECRET-USER-DATA';

void main() {
  test(
    'no token, session id or user data in any log line or toString',
    () async {
      final PRig rig = PRig()
        ..tokens.auth = _authToken
        ..tokens.appCheck = _appCheckToken;
      await rig.start();
      await rig.answerCredentials();
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
      expect(
        rig.logs.where((String l) => l.endsWith('(contents hidden)')),
        isNotEmpty,
      );
      await rig.connection.shutdown();
    },
  );

  test('a token provider failure is logged by type only', () async {
    final PRig rig = PRig();
    rig.tokens.error = Exception('token AUTHMARK leaked');
    rig.connection.initialize();
    await until(() => rig.tokens.authCalls.length >= 2);
    expect(rig.logs.join('\n'), isNot(contains('AUTHMARK')));
    await rig.connection.shutdown();
  });
}
