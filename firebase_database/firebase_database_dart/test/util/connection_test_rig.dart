// Owner C. A RealtimeConnection over the fake connector, a recording delegate and a captured
// logger, for the tests of connection.dart and liveness.dart and C's security tests.

import 'package:fake_async/fake_async.dart';
import 'package:firebase_database_dart/src/core/repo_info.dart';
import 'package:firebase_database_dart/src/core/util/logger.dart';
import 'package:firebase_database_dart/src/realtime/connection.dart';
import 'package:firebase_database_dart/src/realtime/connection_timings.dart';
import 'package:firebase_database_dart/src/realtime/realtime_target.dart';
import 'package:firebase_database_dart/src/realtime/transport/ws_channel.dart';

import 'fake_ws.dart';

/// The configured host of the default rig.
const String configuredHost = 'demo-ns.firebaseio.com';

/// A production-like database.
const RepoInfo productionRepo = RepoInfo(
  host: configuredHost,
  namespace: 'demo-ns',
  secure: true,
);

/// An emulator database.
const RepoInfo emulatorRepo = RepoInfo(
  host: '127.0.0.1:9000',
  namespace: 'demo-ns',
  secure: false,
  isUsingEmulator: true,
);

/// One call the connection made on its delegate.
sealed class DelegateEvent {
  const DelegateEvent();
}

/// `onReady`.
final class Ready extends DelegateEvent {
  const Ready(this.ts, this.sessionId);
  final int ts;
  final String sessionId;
}

/// `onDataMessage`.
final class Data extends DelegateEvent {
  const Data(this.message);
  final Map<String, Object?> message;
}

/// `onDisconnect`.
final class Disconnected extends DelegateEvent {
  const Disconnected(this.reason);
  final DisconnectReason reason;
}

/// `onKill`.
final class Killed extends DelegateEvent {
  const Killed(this.reason);
  final String reason;
}

/// Records every callback; the `when*` hooks run inside the callback (re-entrancy tests).
final class RecordingDelegate implements RealtimeDelegate {
  final List<DelegateEvent> events = <DelegateEvent>[];

  void Function()? whenReady;
  void Function()? whenData;
  void Function()? whenDisconnect;
  void Function()? whenKill;

  List<Disconnected> get disconnects =>
      events.whereType<Disconnected>().toList();
  List<Ready> get readies => events.whereType<Ready>().toList();
  List<Data> get data => events.whereType<Data>().toList();
  List<Killed> get kills => events.whereType<Killed>().toList();

  @override
  void onReady(int serverTimeMs, String sessionId) {
    events.add(Ready(serverTimeMs, sessionId));
    whenReady?.call();
  }

  @override
  void onDataMessage(Map<String, Object?> message) {
    events.add(Data(message));
    whenData?.call();
  }

  @override
  void onDisconnect(DisconnectReason reason) {
    events.add(Disconnected(reason));
    whenDisconnect?.call();
  }

  @override
  void onKill(String reason) {
    events.add(Killed(reason));
    whenKill?.call();
  }
}

/// A connection, its fake connector, target, delegate and log, inside one `fakeAsync` zone.
final class ConnectionRig {
  ConnectionRig(
    this.async, {
    RepoInfo repoInfo = productionRepo,
    this.timings = const ConnectionTimings(),
    this.lastSessionId,
    this.appCheckToken,
    WsConnector? connector,
  }) : fake = FakeWsConnector(elapsed: () => async.elapsed),
       target = RealtimeTarget(repoInfo, useHeaders: true) {
    _connector = connector ?? fake.connect;
  }

  final FakeAsync async;
  final FakeWsConnector fake;
  final RealtimeTarget target;
  final ConnectionTimings timings;
  final String? lastSessionId;
  final String? appCheckToken;
  final RecordingDelegate delegate = RecordingDelegate();
  final List<(DatabaseLogLevel, String)> logs = <(DatabaseLogLevel, String)>[];
  late final WsConnector _connector;

  /// The log lines only.
  List<String> get lines => <String>[for (final (_, String line) in logs) line];

  /// A new connection over this rig (not opened).
  RealtimeConnection create() => RealtimeConnection(
    target,
    _connector,
    timings,
    delegate,
    lastSessionId: lastSessionId,
    appId: 'app-id',
    appCheckToken: appCheckToken,
    logger: (DatabaseLogLevel level, String message) =>
        logs.add((level, message)),
    now: () => DateTime.utc(2026, 11, 22).add(async.elapsed),
    random: () => 0.5,
  );

  /// Opens a new connection and lets the connector accept.
  RealtimeConnection open() {
    final RealtimeConnection connection = create()..open();
    async.flushMicrotasks();
    return connection;
  }

  /// Opens a new connection and delivers a hello naming [host].
  RealtimeConnection openReady({
    String host = configuredHost,
    String session = 'sess-1',
  }) {
    final RealtimeConnection connection = open();
    fake.last.serverHello(ts: 1700000000000, h: host, s: session);
    async.flushMicrotasks();
    return connection;
  }

  /// Runs microtasks after the test made the server do something.
  void flush() => async.flushMicrotasks();
}
