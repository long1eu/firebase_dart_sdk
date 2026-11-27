// Runs the ServerActions contracts (server_actions_contract.dart) against FakeServerActions.
import 'package:firebase_database_dart/src/core/connection/server_actions.dart';
import 'package:firebase_database_dart/src/testing/fake_server_actions.dart';
import 'package:test/test.dart';

import 'server_actions_contract.dart';

final class _FakeHarness implements ServerActionsHarness {
  late FakeServerActions fake;

  static const Map<String, String> _wire = <String, String>{
    'listen': 'q',
    'unlisten': 'n',
    'get': 'g',
    'put': 'p',
    'merge': 'm',
    'onDisconnectPut': 'o',
    'onDisconnectMerge': 'om',
    'onDisconnectCancel': 'oc',
  };

  @override
  Future<ServerActions> start(ServerActionsDelegate delegate) async {
    fake = FakeServerActions(delegate)..initialize();
    fake.connect();
    return fake;
  }

  @override
  List<({String action, Map<String, Object?> body})> get received =>
      <({String action, Map<String, Object?> body})>[
        for (final ServerCall call in fake.calls)
          if (_wire.containsKey(call.action))
            (
              action: _wire[call.action]!,
              body: <String, Object?>{
                'p': call.spec?.path ?? call.path,
                if (call.action == 'listen')
                  'h': call.hashProvider!.simpleHash(),
                if (call.tag != null || call.action == 'get')
                  'q': call.spec!.queryObject,
                if (call.tag != null) 't': call.tag,
                if (call.data != null) 'd': call.data,
                if (call.hash != null) 'h': call.hash,
              },
            ),
      ];

  @override
  Future<void> answer(
    String action, {
    String status = statusOk,
    Object? data,
  }) async {
    final ServerCall call = fake.calls.firstWhere(
      (ServerCall c) => _wire[c.action] == action && !c.answered,
    );
    fake.respond(call, status: status, data: data);
  }

  @override
  Future<void> push(
    String path,
    Object? data, {
    bool isMerge = false,
    int? tag,
  }) async => fake.deliverDataUpdate(path, data, isMerge: isMerge, tag: tag);

  @override
  Future<void> drop() async => fake.disconnect();
}

void main() {
  group('FakeServerActions', () => runServerActionsContract(_FakeHarness.new));
}
