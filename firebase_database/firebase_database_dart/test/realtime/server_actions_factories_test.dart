// Owner P. The factory the core's Repo calls (server_actions_factories.dart): it builds without
// connecting, nothing reaches the delegate before initialize(), two factories share no state, and
// every named parameter reaches what it configures.
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:firebase_database_dart/src/core/connection/server_actions.dart';
import 'package:firebase_database_dart/src/core/repo.dart';
import 'package:firebase_database_dart/src/core/repo_info.dart';
import 'package:firebase_database_dart/src/realtime/connection_timings.dart';
import 'package:firebase_database_dart/src/realtime/server_actions_factories.dart';
import 'package:firebase_database_dart/src/testing/recording_server_actions_delegate.dart';
import 'package:test/test.dart';

import '../util/fake_ws.dart';
import '../util/fakes.dart';

/// A user-shaped JWT (claims {"iat":0}): sent as `auth`.
const String _jwt = 'eyJhbGciOiJub25lIn0.eyJpYXQiOjB9.sig';

const RepoInfo _repo = RepoInfo(
  host: 'test-ns.firebaseio.com',
  namespace: 'test-ns',
  secure: true,
);

const RepoInfo _otherRepo = RepoInfo(
  host: 'other-ns.firebaseio.com',
  namespace: 'other-ns',
  secure: true,
);

/// One WebSocket factory over a fake connector, driven by fake_async.
final class _Wired {
  _Wired(
    FakeAsync async, {
    RepoInfo repoInfo = _repo,
    ConnectionTimings timings = const ConnectionTimings(),
    double Function()? random,
    Stream<void>? hints,
    DateTime Function()? clock,
    String? appId,
  }) : connector = FakeWsConnector(
         autoHello: true,
         elapsed: () => async.elapsed,
       ) {
    factory = persistentConnectionFactory(
      repoInfo,
      authProvider: auth,
      appCheckProvider: appCheck,
      appId: appId,
      timings: timings,
      connectivityHints: hints,
      clock:
          clock ??
          () => DateTime.fromMillisecondsSinceEpoch(
            FakeWsConnector.helloEpochMs,
          ).add(async.elapsed),
      random: random ?? () => 1,
      connector: connector.connect,
    );
    actions = factory(delegate, null);
  }

  final FakeAuth auth = FakeAuth(<String?>[_jwt]);
  final FakeAppCheck appCheck = FakeAppCheck('app-check-token');
  final FakeWsConnector connector;
  final RecordingServerActionsDelegate delegate =
      RecordingServerActionsDelegate();
  late final ServerActionsFactory factory;
  late final ServerActions actions;

  void shutdown(FakeAsync async) {
    unawaited(actions.shutdown());
    async.flushMicrotasks();
  }
}

ConnectionTimings _slowReconnect(Duration min) => ConnectionTimings(
  reconnectMin: min,
  reconnectMax: min,
  keepAlive: const Duration(hours: 1),
  healthyTimeout: const Duration(hours: 1),
  idleProbeAfter: const Duration(hours: 1),
);

void main() {
  group('persistentConnectionFactory', () {
    test(
      'builds without opening a socket; nothing reaches the delegate before initialize',
      () {
        fakeAsync((FakeAsync async) {
          final _Wired wired = _Wired(async);
          async.elapse(const Duration(minutes: 1));
          expect(wired.connector.attempts, isEmpty);
          expect(wired.delegate.calls, isEmpty);
          expect(wired.auth.calls, isEmpty);
          wired.actions.initialize();
          async.elapse(const Duration(milliseconds: 100));
          expect(wired.connector.attempts, hasLength(1));
          expect(wired.delegate.methods, contains('connect'));
          wired.shutdown(async);
        });
      },
    );

    test('the token providers and the app id reach the connection', () {
      fakeAsync((FakeAsync async) {
        final _Wired wired = _Wired(async, appId: '1:123:dart:abc');
        wired.actions.initialize();
        async.elapse(const Duration(milliseconds: 100));
        expect(wired.auth.calls, <bool>[false]);
        expect(wired.appCheck.calls, <bool>[false]);
        final ConnectAttempt attempt = wired.connector.attempts.single;
        // A browser WebSocket carries no headers: there both travel in the query.
        if (_isWeb) {
          expect(attempt.url.queryParameters['p'], '1:123:dart:abc');
          expect(attempt.url.queryParameters['ac'], 'app-check-token');
          expect(attempt.headers, isEmpty);
        } else {
          expect(attempt.headers['X-Firebase-GMPID'], '1:123:dart:abc');
          expect(attempt.headers['X-Firebase-AppCheck'], 'app-check-token');
        }
        final FakeWsChannel channel = wired.connector.last;
        expect(channel.lastRequest('auth')?['b'], <String, Object?>{
          'cred': _jwt,
        });
        expect(channel.lastRequest('appcheck')?['b'], <String, Object?>{
          'token': 'app-check-token',
        });
        wired.shutdown(async);
      });
    });

    test('the clock reaches the connection (serverTimeOffset)', () {
      fakeAsync((FakeAsync async) {
        final DateTime fixed = DateTime.fromMillisecondsSinceEpoch(
          FakeWsConnector.helloEpochMs - 5000,
        );
        final _Wired wired = _Wired(async, clock: () => fixed);
        wired.actions.initialize();
        async.elapse(const Duration(milliseconds: 100));
        final Map<String, Object?> info =
            wired.delegate.callsOf('serverInfoUpdate').single.data!
                as Map<String, Object?>;
        expect(info['serverTimeOffset'], inInclusiveRange(5000, 5100));
        wired.shutdown(async);
      });
    });

    test('the timings and the random source reach the backoff', () {
      fakeAsync((FakeAsync async) {
        final _Wired full = _Wired(
          async,
          timings: _slowReconnect(const Duration(seconds: 10)),
        );
        full.connector.script(<AttemptBehavior>[
          const AttemptBehavior.refuse(),
        ]);
        full.actions.initialize();
        async.elapse(const Duration(seconds: 9));
        expect(full.connector.attempts, hasLength(1));
        async.elapse(const Duration(seconds: 2));
        expect(full.connector.attempts, hasLength(2));
        full.shutdown(async);

        final _Wired none = _Wired(
          async,
          timings: _slowReconnect(const Duration(seconds: 10)),
          random: () => 0,
        );
        none.connector.script(<AttemptBehavior>[
          const AttemptBehavior.refuse(),
        ]);
        none.actions.initialize();
        async.elapse(const Duration(milliseconds: 100));
        expect(none.connector.attempts, hasLength(2));
        none.shutdown(async);
      });
    });

    test('a connectivity hint reaches the connection', () {
      fakeAsync((FakeAsync async) {
        final StreamController<void> hints = StreamController<void>.broadcast();
        final _Wired wired = _Wired(
          async,
          timings: _slowReconnect(const Duration(hours: 1)),
          hints: hints.stream,
        );
        wired.connector.script(<AttemptBehavior>[
          const AttemptBehavior.refuse(),
        ]);
        wired.actions.initialize();
        async.elapse(const Duration(seconds: 1));
        expect(wired.connector.attempts, hasLength(1));
        hints.add(null);
        async.elapse(const Duration(milliseconds: 100));
        expect(wired.connector.attempts, hasLength(2));
        wired.shutdown(async);
      });
    });

    test('two factories for two databases share no state', () {
      fakeAsync((FakeAsync async) {
        final _Wired one = _Wired(async);
        final _Wired two = _Wired(async, repoInfo: _otherRepo);
        expect(
          identical(one.factory(one.delegate, null), one.actions),
          isFalse,
        );
        one.actions.initialize();
        two.actions.initialize();
        async.elapse(const Duration(milliseconds: 100));
        expect(
          one.connector.attempts.single.url.host,
          'test-ns.firebaseio.com',
        );
        expect(
          two.connector.attempts.single.url.host,
          'other-ns.firebaseio.com',
        );
        one.actions.interrupt(interruptReason);
        async.elapse(const Duration(milliseconds: 100));
        expect(one.actions.isInterrupted(interruptReason), isTrue);
        expect(two.actions.isInterrupted(interruptReason), isFalse);
        expect(two.delegate.methods, isNot(contains('disconnect')));
        one.shutdown(async);
        two.shutdown(async);
      });
    });
  });
}

/// Whether the tests run compiled for a browser (no `dart:io`).
const bool _isWeb = bool.fromEnvironment('dart.library.js_interop');
