// Owner P. A PersistentConnection over a FakeRtdbServer with the target and the token source of
// the test's choice, for the tests that PRig cannot express: a target that may not receive tokens
// (review M1 b) and the real ProviderTokenSource over a fake provider (shim review H1).

import 'package:firebase_database_dart/src/core/repo_info.dart';
import 'package:firebase_database_dart/src/core/util/logger.dart';
import 'package:firebase_database_dart/src/realtime/auth_session.dart';
import 'package:firebase_database_dart/src/realtime/connection.dart';
import 'package:firebase_database_dart/src/realtime/connection_timings.dart';
import 'package:firebase_database_dart/src/realtime/persistent_connection.dart';
import 'package:firebase_database_dart/src/realtime/realtime_target.dart';
import 'package:firebase_database_dart/src/realtime/reconnect_backoff.dart';
import 'package:firebase_database_dart/src/testing/recording_server_actions_delegate.dart';

import '../util/fake_rtdb_server.dart';
import '../util/persistent_connection_harness.dart';

/// One PersistentConnection over [server], built from a RepoInfo and [tokens].
final class CustomRig {
  /// Builds the connection; nothing connects before [start]. [useHeaders] false is the web form
  /// (App Check token and app id in the URL query).
  CustomRig({
    required RepoInfo repoInfo,
    required this.tokens,
    bool useHeaders = true,
  }) : target = RealtimeTarget(repoInfo, useHeaders: useHeaders),
       server = FakeRtdbServer() {
    final ConnectionTimings timings = shrunkTimings();
    connection = PersistentConnection(
      target: target,
      connectionFactory:
          (
            RealtimeDelegate delegate, {
            String? lastSessionId,
            String? appId,
            String? appCheckToken,
          }) => RealtimeConnection(
            target,
            server.connect,
            timings,
            delegate,
            lastSessionId: lastSessionId,
            appId: appId,
            appCheckToken: appCheckToken,
          ),
      backoff: ReconnectBackoff(
        min: timings.reconnectMin,
        max: timings.reconnectMax,
        multiplier: timings.reconnectMultiplier,
        resetAfter: timings.reconnectResetAfter,
        now: DateTime.now,
        random: () => 1,
      ),
      tokens: tokens,
      delegate: delegate,
      timings: timings,
      appId: '1:123:dart:abc',
      logger: (DatabaseLogLevel level, String message) =>
          logs.add('${level.name}: $message'),
      now: DateTime.now,
      random: () => 1,
    );
  }

  /// The target the connection was built with.
  final RealtimeTarget target;

  /// The token source.
  final RealtimeTokenSource tokens;

  /// The server.
  final FakeRtdbServer server;

  /// What the connection told Repo.
  final RecordingServerActionsDelegate delegate =
      RecordingServerActionsDelegate();

  /// Every log line, as `<level>: <message>`.
  final List<String> logs = <String>[];

  /// The connection under test.
  late final PersistentConnection connection;

  /// How many times the delegate heard `connect`.
  int get connects => delegate.callsOf('connect').length;

  /// Initializes the connection and waits for its first `connect`.
  Future<void> start() async {
    connection.initialize();
    await until(() => connects == 1);
  }

  /// The credential requests (`auth`, `gauth`, `unauth`, `appcheck`, the App Check removal) the
  /// server received, in order.
  List<ServerSeen> get credentialRequests => server.log
      .where((ServerSeen seen) => credentialActions.contains(seen.action))
      .toList();

  /// The `cred` of every `auth` and `gauth` the server received, in order.
  List<Object?> get sentAuthCredentials => <Object?>[
    for (final ServerSeen seen in server.log)
      if (seen.action == RealtimeProtocol.auth ||
          seen.action == RealtimeProtocol.gauth)
        seen.body['cred'],
  ];

  /// Lets queued events and microtasks run.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 5));
}
