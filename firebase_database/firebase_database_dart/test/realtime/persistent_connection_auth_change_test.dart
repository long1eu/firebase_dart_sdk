// Owner P. Shim review H1: an auth token change event is a signal, never a credential. The real
// ProviderTokenSource over a fake AuthTokenProvider that announces a change with a marker, as the
// FlutterFire bridge of this repository does (`changedTokenMarker`), in place of the token.
import 'dart:async';

import 'package:firebase_database_dart/src/core/repo_info.dart';
import 'package:firebase_database_dart/src/realtime/auth_session.dart';
import 'package:firebase_database_dart/src/realtime/connection_timings.dart';
import 'package:test/test.dart';

import '../util/fakes.dart';
import '../util/persistent_connection_harness.dart';
import 'persistent_connection_custom_rig.dart';

/// Two user-shaped JWTs (claims with `iat`), sent as `auth`.
const String _tokenA = 'eyJhbGciOiJub25lIn0.eyJpYXQiOjEsInN1YiI6IkEifQ.a';
const String _tokenB = 'eyJhbGciOiJub25lIn0.eyJpYXQiOjIsInN1YiI6IkIifQ.b';

/// What `FlutterFireAuthTokenProvider` emits for a sign-in or a refresh.
const String _marker = 'flutterfire-bridge:token-changed';

const RepoInfo _secure = RepoInfo(
  host: 'test-ns.firebaseio.com',
  namespace: 'test-ns',
  secure: true,
);

CustomRig _rig(FakeAuth auth) => CustomRig(
  repoInfo: _secure,
  tokens: ProviderTokenSource(
    auth: auth,
    forcedRefreshMinInterval: const Duration(seconds: 60),
    now: DateTime.now,
  ),
);

void main() {
  test(
    'a change event without the token leads to a fetch; the fetched token goes out as auth',
    () async {
      final FakeAuth auth = FakeAuth(<String?>[_tokenA, _tokenB]);
      final CustomRig rig = _rig(auth);
      await rig.start();
      await until(() => rig.sentAuthCredentials.length == 1);

      auth.emit(_marker);
      await until(() => rig.sentAuthCredentials.length == 2);
      await rig.settle();

      // Breaks if PersistentConnection._onAuthTokenChanged hands the event's value to the session.
      expect(rig.sentAuthCredentials, <Object?>[_tokenA, _tokenB]);
      expect(rig.server.seen(RealtimeProtocol.gauth), isEmpty);
      expect(auth.calls, <bool>[false, false]);
      expect(rig.delegate.callsOf('disconnect'), isEmpty);
      await rig.connection.shutdown();
    },
  );

  test('a sign-out event sends unauth without a fetch', () async {
    final FakeAuth auth = FakeAuth(<String?>[_tokenA]);
    final CustomRig rig = _rig(auth);
    await rig.start();
    await until(() => rig.sentAuthCredentials.length == 1);

    auth.emit('');
    await until(() => rig.server.seen(RealtimeProtocol.unauth).isNotEmpty);

    expect(auth.calls, hasLength(1));
    expect(rig.sentAuthCredentials, <Object?>[_tokenA]);
    await rig.connection.shutdown();
  });

  test(
    'a sign-out during the fetch of a changed token wins over the fetched token',
    () async {
      final FakeAuth auth = FakeAuth(<String?>[_tokenA, _tokenB]);
      final CustomRig rig = _rig(auth);
      await rig.start();
      await until(() => rig.sentAuthCredentials.length == 1);

      auth.gate = Completer<void>();
      auth.emit(_marker);
      await until(() => auth.calls.length == 2);
      auth.emit('');
      await rig.settle();
      auth.gate!.complete();
      await rig.settle();

      // Breaks if _fetchChangedAuthToken applies its result without comparing the version.
      expect(rig.sentAuthCredentials, <Object?>[_tokenA]);
      expect(rig.credentialRequests.last.action, RealtimeProtocol.unauth);
      await rig.connection.shutdown();
    },
  );

  test(
    'a later change during the fetch of a changed token wins: the last fetch is sent',
    () async {
      final FakeAuth auth = FakeAuth(<String?>[_tokenA, _tokenA, _tokenB]);
      final CustomRig rig = _rig(auth);
      await rig.start();
      await until(() => rig.sentAuthCredentials.length == 1);

      auth.gate = Completer<void>();
      auth.emit(_marker); // Fetch 2, held: would answer _tokenA.
      auth.emit(_marker); // Fetch 3, held: answers _tokenB.
      await until(() => auth.calls.length == 3);
      auth.gate!.complete();
      await until(() => rig.sentAuthCredentials.length == 2);
      await rig.settle();

      expect(rig.sentAuthCredentials, <Object?>[_tokenA, _tokenB]);
      await rig.connection.shutdown();
    },
  );

  test(
    'a provider failure on a change is logged by type only and sends nothing',
    () async {
      final ScriptedTokens tokens = ScriptedTokens(auth: _tokenA);
      final CustomRig rig = CustomRig(repoInfo: _secure, tokens: tokens);
      await rig.start();
      await until(() => rig.sentAuthCredentials.length == 1);

      tokens
        ..error = Exception('provider says $_tokenB')
        ..emitAuth(_marker);
      await until(
        () => rig.logs.any(
          (String line) =>
              line.contains('Failed to get the changed auth token'),
        ),
      );
      await rig.settle();

      expect(rig.sentAuthCredentials, <Object?>[_tokenA]);
      expect(rig.logs.join('\n'), isNot(contains(_tokenB)));
      expect(rig.logs.join('\n'), isNot(contains(_marker)));
      await rig.connection.shutdown();
    },
  );
}
