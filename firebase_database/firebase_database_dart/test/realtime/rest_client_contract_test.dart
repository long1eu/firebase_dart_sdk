// Owner R. Runs the core's read-only ServerActions contract against RestClient over a MockClient
// (package:http/testing.dart). Fails with UnimplementedError until R fills it: expected.
import 'package:firebase_database_dart/src/core/connection/server_actions.dart';
import 'package:test/test.dart';

import '../contract/server_actions_contract.dart';

/// Creates a RestClient reporting to [delegate] (the contract's RecordingServerActionsDelegate),
/// over an emulator RepoInfo, fake tokens and a MockClient that answers reads.
Future<ServerActions> startRestClient(ServerActionsDelegate delegate) {
  throw UnimplementedError();
}

void main() {
  group('read-only ServerActions contract', () {
    runReadOnlyServerActionsContract(startRestClient);
  });
}
