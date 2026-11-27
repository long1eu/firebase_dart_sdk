/// The wiring the core's Repo calls (owner P): the [ServerActionsFactory] of the WebSocket
/// connection (`lib/src/core/repo.dart`).
///
/// Repo calls the factory once, in its constructor, with itself as the delegate; its start order
/// is: load persisted writes, `restoreWrites`, then `ServerActions.initialize`. So the objects
/// built here open nothing and call nothing on the delegate before `initialize`. Every call of a
/// returned factory builds fresh state (target, token adapter, backoff, connector): two Repos
/// never share a server host, a backoff or a subscription. No `dart:io` here: the WebSocket
/// connector comes through the conditional import of `transport/ws_connector.dart`.
library;

import 'dart:math' as math;

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_database_dart/src/core/connection/server_actions.dart';
import 'package:firebase_database_dart/src/core/repo.dart';
import 'package:firebase_database_dart/src/core/repo_info.dart';
import 'package:firebase_database_dart/src/core/util/clock.dart';
import 'package:firebase_database_dart/src/core/util/logger.dart';
import 'package:firebase_database_dart/src/realtime/auth_session.dart';
import 'package:firebase_database_dart/src/realtime/connection.dart';
import 'package:firebase_database_dart/src/realtime/connection_timings.dart';
import 'package:firebase_database_dart/src/realtime/persistent_connection.dart';
import 'package:firebase_database_dart/src/realtime/realtime_target.dart';
import 'package:firebase_database_dart/src/realtime/reconnect_backoff.dart';
import 'package:firebase_database_dart/src/realtime/transport/ws_channel.dart';
import 'package:firebase_database_dart/src/realtime/transport/ws_connector.dart';

/// The factory of the WebSocket [PersistentConnection] of the database at [repoInfo].
///
/// [authProvider] and [appCheckProvider] are wrapped in a [ProviderTokenSource] (null: no
/// credential of that kind); [appId] goes to every connection (`X-Firebase-GMPID` on the VM, `p`
/// on the web); [timings] configures the connection, its liveness, the request timeouts and the
/// backoff; [connectivityHints] is the only external reconnect trigger (test plan B-8.7).
/// [clock] and [random] replace `DateTime.now` and `Random().nextDouble` (the defaults: this is
/// the composition root, the one place they are chosen). [connector] replaces the platform's
/// WebSocket connector (tests pass a fake one); by default it is the platform's, bounded by
/// `ConnectionTimings.maxMessageBytes`.
ServerActionsFactory persistentConnectionFactory(
  RepoInfo repoInfo, {
  required AuthTokenProvider? authProvider,
  required AppCheckTokenProvider? appCheckProvider,
  String? appId,
  ConnectionTimings timings = const ConnectionTimings(),
  Stream<void>? connectivityHints,
  Clock? clock,
  double Function()? random,
  WsConnector? connector,
}) {
  final Clock now = clock ?? DateTime.now;
  final double Function() jitter = random ?? math.Random().nextDouble;
  return (ServerActionsDelegate delegate, DatabaseLogger? logger) {
    final RealtimeTarget target = RealtimeTarget(
      repoInfo,
      useHeaders: wsConnectorSendsHeaders,
    );
    final WsConnector ws =
        connector ??
        platformWsConnector(maxMessageBytes: timings.maxMessageBytes);
    return PersistentConnection(
      target: target,
      connectionFactory:
          (
            RealtimeDelegate connectionDelegate, {
            String? lastSessionId,
            String? appId,
            String? appCheckToken,
          }) => RealtimeConnection(
            target,
            ws,
            timings,
            connectionDelegate,
            lastSessionId: lastSessionId,
            appId: appId,
            appCheckToken: appCheckToken,
            logger: logger,
          ),
      backoff: ReconnectBackoff(
        min: timings.reconnectMin,
        max: timings.reconnectMax,
        multiplier: timings.reconnectMultiplier,
        resetAfter: timings.reconnectResetAfter,
        now: now,
        random: jitter,
      ),
      tokens: ProviderTokenSource(
        auth: authProvider,
        appCheck: appCheckProvider,
        forcedRefreshMinInterval: timings.forcedRefreshMinInterval,
        now: now,
      ),
      delegate: delegate,
      timings: timings,
      appId: appId,
      logger: logger,
      now: now,
      random: jitter,
      connectivityHints: connectivityHints,
    );
  };
}
