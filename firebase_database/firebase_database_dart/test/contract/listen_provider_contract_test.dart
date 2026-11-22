// Runs the listen provider contract (listen_provider_contract.dart) against RepoListenProvider
// over FakeServerActions.
import 'package:firebase_database_dart/src/core/repo.dart';
import 'package:firebase_database_dart/src/core/view/event.dart';
import 'package:firebase_database_dart/src/testing/fake_server_actions.dart';
import 'package:test/test.dart';

import 'listen_provider_contract.dart';

void main() {
  group('RepoListenProvider', () {
    runListenProviderContract(
      (FakeServerActions server) =>
          RepoListenProvider(server, (List<Event> events) {}),
    );
  });
}
