// Runs a query and a mutation of the test connector against the Data Connect emulator.
//
// From the repository root, in a second terminal (once: `firebase setup:emulators:dataconnect`):
//
//     ./tool/start_data_connect_emulator.sh
//     export FIREBASE_DATA_CONNECT_EMULATOR_HOST=127.0.0.1:9499
//     cd firebase_data_connect/firebase_data_connect_dart && dart run example/main.dart
//     cd ../.. && ./tool/stop_data_connect_emulator.sh
//
// The connector is the fixture of tool/data_connect_emulator/dataconnect: a table `Item`, the query
// `ListItems` and the mutations `CreateItem` and `DeleteItem`. On the VM the calls go over gRPC.

import 'dart:io';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_data_connect_dart/firebase_data_connect_dart.dart';

Future<void> main() async {
  final String? emulatorHost = DataConnect.emulatorHostFromEnvironment;
  if (emulatorHost == null) {
    stderr.writeln(
      'Set FIREBASE_DATA_CONNECT_EMULATOR_HOST (for example 127.0.0.1:9499) to the address of the '
      'Data Connect emulator: tool/start_data_connect_emulator.sh starts one.',
    );
    exit(64);
  }
  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: 'fake-api-key',
      appId: '1:123456789012:dart:0123456789abcdef',
      projectId: 'demo-test',
    ),
  );
  final DataConnect dataConnect = DataConnect(
    app,
    connector: const ConnectorConfig(
      location: 'us-central1',
      serviceId: 'test-service',
      connector: 'test-connector',
    ),
    emulatorHost: emulatorHost,
  );
  try {
    final MutationRef<String, String> createItem = dataConnect
        .mutation<String, String>(
          'CreateItem',
          variables: 'first item',
          encodeVariables: (String name) => <String, Object?>{'name': name},
          decode: (Map<String, Object?> data) =>
              (data['item_insert']! as Map<String, Object?>)['id']! as String,
        );
    final String id = (await createItem.execute()).data;
    print('created $id');

    final QueryRef<List<String>, void> listItems = dataConnect
        .query<List<String>, void>(
          'ListItems',
          decode: (Map<String, Object?> data) => <String>[
            for (final Object? item in data['items']! as List<Object?>)
              (item! as Map<String, Object?>)['name']! as String,
          ],
        );
    print('items: ${(await listItems.execute()).data}');

    await dataConnect.executeMutation(
      'DeleteItem',
      variables: <String, Object?>{'id': id},
    );
    print('deleted $id');
  } on DataConnectException catch (e) {
    stderr.writeln('Failed: ${e.code}: ${e.message}');
    exitCode = 1;
  } finally {
    await dataConnect.close();
  }
}
