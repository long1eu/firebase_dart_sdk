// Owner R. Runs the core's read-only ServerActions contract against RestClient over a MockClient
// (package:http/testing.dart).
import 'package:firebase_database_dart/src/core/connection/server_actions.dart';
import 'package:firebase_database_dart/src/realtime/rest_client.dart';
import 'package:test/test.dart';

import '../contract/server_actions_contract.dart';
import '../util/rest_client_fakes.dart';

/// Creates a RestClient reporting to [delegate] (the contract's RecordingServerActionsDelegate),
/// over an emulator RepoInfo, fake tokens and a MockClient that answers reads.
Future<ServerActions> startRestClient(ServerActionsDelegate delegate) async {
  final RestClient client = restClientFor(
    ScriptedServer.always(200, 'null'),
    delegate: delegate,
  )..initialize();
  addTearDown(client.shutdown);
  return client;
}

void main() {
  group('read-only ServerActions contract', () {
    runReadOnlyServerActionsContract(startRestClient);
  });
}
