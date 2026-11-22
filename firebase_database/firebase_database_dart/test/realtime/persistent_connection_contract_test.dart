// Owner P. Runs the core's ServerActions contract and the reconnect contract against
// PersistentConnection over FakeRtdbServer. Fails with UnimplementedError until P fills the
// harness and the connection: expected.
import 'package:firebase_database_dart/src/core/connection/server_actions.dart';
import 'package:test/test.dart';

import '../contract/server_actions_contract.dart';
import '../contract/server_actions_reconnect_contract.dart';

/// Plays the server for a PersistentConnection built over a FakeRtdbServer (test/util), with
/// fake tokens (test/util/fakes.dart) and the production ConnectionTimings shrunk for fakeAsync.
/// The delegate given to [start] is the contract's RecordingServerActionsDelegate.
final class PersistentConnectionHarness
    implements ServerActionsReconnectHarness {
  @override
  Future<ServerActions> start(ServerActionsDelegate delegate) {
    throw UnimplementedError();
  }

  @override
  List<({String action, Map<String, Object?> body})> get received =>
      throw UnimplementedError();

  @override
  int connectionOf(int index) {
    throw UnimplementedError();
  }

  @override
  Future<void> answer(String action, {String status = statusOk, Object? data}) {
    throw UnimplementedError();
  }

  @override
  Future<void> push(
    String path,
    Object? data, {
    bool isMerge = false,
    int? tag,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> drop() {
    throw UnimplementedError();
  }

  @override
  Future<void> reconnect() {
    throw UnimplementedError();
  }

  @override
  Future<void> revokeListen(
    String path, [
    List<Map<String, Object?>>? queries,
  ]) {
    throw UnimplementedError();
  }

  @override
  Future<void> revokeAuth(String status, String explanation) {
    throw UnimplementedError();
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
