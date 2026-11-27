// Owner P. Threat model T3g and review ruling M1 (b): PersistentConnection asks
// RealtimeTarget.mayReceiveTokens before it hands over the App Check token and before
// AuthSession.onConnected. The target here is an emulator configured without a port
// (`emulatorHost: 'localhost'` builds one): its WebSocket URL is ws://<host>/ on port 80, which the
// target does not trust with a token, so the connection works without any credential.
import 'package:firebase_database_dart/src/core/repo_info.dart';
import 'package:firebase_database_dart/src/realtime/connection_timings.dart';
import 'package:firebase_database_dart/src/testing/recording_server_actions_delegate.dart';
import 'package:test/test.dart';

import '../realtime/persistent_connection_custom_rig.dart';
import '../util/fake_ws.dart';
import '../util/persistent_connection_harness.dart';

const String _authToken = validAuthToken;
const String _appCheckToken = validAppCheckToken;

RepoInfo _emulator(String host) => RepoInfo(
  host: host,
  namespace: 'test-ns',
  secure: false,
  isUsingEmulator: true,
);

CustomRig _rig(String host, {required bool useHeaders}) => CustomRig(
  repoInfo: _emulator(host),
  tokens: ScriptedTokens(auth: _authToken, appCheck: _appCheckToken),
  useHeaders: useHeaders,
);

/// Whether any attempt carried the App Check token, in a header or in the query.
bool _appCheckInUpgrade(CustomRig rig) => rig.server.connector.attempts.any(
  (ConnectAttempt attempt) =>
      attempt.headers.containsKey(RealtimeProtocol.appCheckHeader) ||
      attempt.url.queryParameters.containsKey(
        RealtimeProtocol.appCheckTokenParam,
      ) ||
      attempt.url.toString().contains(_appCheckToken),
);

void main() {
  for (final bool useHeaders in <bool>[true, false]) {
    final String form = useHeaders ? 'headers' : 'query (web form)';

    test(
      'no auth, no appcheck frame, no App Check $form when mayReceiveTokens is false',
      () async {
        final CustomRig rig = _rig('127.0.0.1', useHeaders: useHeaders);
        expect(
          rig.target.mayReceiveTokens(rig.target.connectionUri()),
          isFalse,
          reason: 'the precondition of this test',
        );
        await rig.start();
        // Changes while connected must not send a credential either.
        (rig.tokens as ScriptedTokens)
          ..emitAuth('$_authToken-2')
          ..emitAuth(null);
        await rig.settle();
        rig.connection.put('/a', 1);
        await until(() => rig.server.seen('p').isNotEmpty);

        // Breaks if PersistentConnection._replay calls _session.onConnected() without asking
        // _tokensAllowed (persistent_connection.dart, `if (_tokensAllowed)`).
        expect(rig.credentialRequests, isEmpty);
        // Breaks if _openConnection passes appCheckToken whatever _tokensAllowed says.
        expect(_appCheckInUpgrade(rig), isFalse);
        expect(
          rig.logs.where((String l) => l.contains('not secure')),
          hasLength(1),
        );
        await rig.connection.shutdown();
      },
    );

    test(
      'control: the same emulator with its port receives both tokens ($form)',
      () async {
        final CustomRig rig = _rig('127.0.0.1:9000', useHeaders: useHeaders);
        expect(rig.target.mayReceiveTokens(rig.target.connectionUri()), isTrue);
        await rig.start();
        await until(
          () => rig.server.seen(RealtimeProtocol.appCheck).isNotEmpty,
        );

        expect(rig.sentAuthCredentials, <Object?>[_authToken]);
        expect(_appCheckInUpgrade(rig), isTrue);
        // Both accepted: the connection stays (a refused auth would close it).
        await until(() => rig.delegate.callsOf('appCheckStatus').isNotEmpty);
        expect(
          rig.delegate.callsOf('authStatus').map((DelegateCall c) => c.status),
          <String>['ok'],
        );
        expect(
          rig.delegate
              .callsOf('appCheckStatus')
              .map((DelegateCall c) => c.status),
          <String>['ok'],
        );
        await rig.connection.shutdown();
      },
    );
  }
}
