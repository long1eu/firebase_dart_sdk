// Owner P. Runs the core's ServerActions contract and the reconnect contract against
// PersistentConnection over FakeRtdbServer (real RealtimeConnection, shrunk timings).
import 'package:firebase_database_dart/src/core/connection/server_actions.dart';
import 'package:firebase_database_dart/src/testing/recording_server_actions_delegate.dart';
import 'package:test/test.dart';

import '../contract/server_actions_contract.dart';
import '../contract/server_actions_reconnect_contract.dart';
import '../util/fake_rtdb_server.dart';
import '../util/persistent_connection_harness.dart';

const Set<String> _contractActions = <String>{
  'q',
  'n',
  'g',
  'p',
  'm',
  'o',
  'om',
  'oc',
};

/// Real time. A browser clamps nested timers to 4 ms, so the 20 zero-delay turns of one
/// `pumpEventQueue` alone take about 80 ms there: 60 ms would call a healthy link silent.
const Duration _requestTimeout = Duration(
  milliseconds: bool.fromEnvironment('dart.library.js_interop') ? 600 : 60,
);

/// Plays the server for a PersistentConnection built over a FakeRtdbServer. Responses are held:
/// the contract answers what it wants; the server answers the credentials of every connection
/// itself, as the emulator does.
/// Reconnects wait an hour unless [reconnect] sends a connectivity hint, so "no new connection
/// until [reconnect]" holds.
final class PersistentConnectionHarness
    implements ServerActionsReconnectHarness {
  late PRig _rig;
  final Set<String> _answered = <String>{};

  List<ServerSeen> get _contractLog => _rig.server.log
      .where((ServerSeen s) => _contractActions.contains(s.action))
      .toList();

  @override
  Future<ServerActions> start(ServerActionsDelegate delegate) async {
    _rig = PRig(
      hold: true,
      delegate: delegate as RecordingServerActionsDelegate,
      timings: shrunkTimings(
        reconnectMin: const Duration(hours: 1),
        reconnectMax: const Duration(hours: 1),
        requestTimeout: _requestTimeout,
      ),
    );
    await _rig.start();
    await _rig.settle();
    return _rig.connection;
  }

  static String _key(ServerSeen seen) => '${seen.connection}/${seen.r}';

  @override
  List<({String action, Map<String, Object?> body})> get received =>
      <({String action, Map<String, Object?> body})>[
        for (final ServerSeen seen in _contractLog)
          (action: seen.action, body: seen.body),
      ];

  @override
  int connectionOf(int index) => _contractLog[index].connection;

  @override
  List<String> actionsOn(int number) => _rig.actionsOn(number);

  @override
  Future<void> answer(
    String action, {
    String status = statusOk,
    Object? data,
  }) async {
    await _rig.settle();
    final int current = _rig.server.connections;
    final ServerSeen seen = _contractLog.firstWhere(
      (ServerSeen s) =>
          s.action == action &&
          s.connection == current &&
          !_answered.contains(_key(s)),
    );
    _answered.add(_key(seen));
    _rig.server.connector.last.serverResponse(
      seen.r!,
      status: status,
      data: data,
    );
    await _rig.settle();
  }

  @override
  Future<void> push(
    String path,
    Object? data, {
    bool isMerge = false,
    int? tag,
  }) async {
    final String wirePath = '/$path';
    if (isMerge) {
      _rig.server.pushMerge(wirePath, data! as Map<String, Object?>, tag: tag);
    } else {
      _rig.server.pushData(wirePath, data, tag: tag);
    }
    await _rig.settle();
  }

  @override
  Future<void> drop() => _rig.drop();

  @override
  Future<void> reconnect() async {
    final int before = _rig.connects;
    _rig.hints.add(null);
    await until(() => _rig.connects > before);
    await _rig.settle();
  }

  @override
  Future<void> revokeListen(
    String path, [
    List<Map<String, Object?>>? queries,
  ]) async {
    _rig.server.pushListenCancel('/$path', queries);
    await _rig.settle();
  }

  @override
  Future<void> revokeAuth(String status, String explanation) async {
    _rig.server.pushAuthRevoked(status, explanation);
    await _rig.settle();
  }

  @override
  Future<void> timeOutPending() async {
    await Future<void>.delayed(_requestTimeout * 2);
    await _rig.settle();
  }
}

void main() {
  group('ServerActions contract', () {
    runServerActionsContract(PersistentConnectionHarness.new);
  });
  group('reconnect contract', () {
    runServerActionsReconnectContract(PersistentConnectionHarness.new);
  });
}
