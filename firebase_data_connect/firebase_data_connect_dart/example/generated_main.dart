// Runs generated code on the Dart VM, without Flutter.
//
// `firebase dataconnect:sdk:generate` wrote example/generated/ for FlutterFire's firebase_data_connect;
// `dart run firebase_data_connect_dart:rewrite_generated example/generated` pointed its imports at
// package:firebase_data_connect_dart/flutterfire.dart. The code is the generator's output for the probe
// connector of the research service (service `probe-service`, connector `probe-connector`, a table
// `Owner`), so it needs an emulator that serves that connector: tool/start_data_connect_emulator.sh
// serves the `test-connector` fixture and answers `not-found` here.
//
//     dart run example/generated_main.dart      # with FIREBASE_DATA_CONNECT_EMULATOR_HOST set

import 'dart:io';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_data_connect_dart/flutterfire.dart' as compat;

import 'generated/probe_connector.dart';

Future<void> main() async {
  final String? emulatorHost =
      Platform.environment['FIREBASE_DATA_CONNECT_EMULATOR_HOST'];
  if (emulatorHost == null) {
    stderr.writeln(
      'Set FIREBASE_DATA_CONNECT_EMULATOR_HOST (for example 127.0.0.1:9399) to an emulator that '
      'serves the probe connector.',
    );
    exit(64);
  }
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: 'fake-api-key',
      appId: '1:123456789012:dart:0123456789abcdef',
      projectId: 'demo-test',
    ),
  );
  final int separator = emulatorHost.lastIndexOf(':');
  final ProbeConnectorConnector connector = ProbeConnectorConnector.instance;
  connector.dataConnect.useDataConnectEmulator(
    emulatorHost.substring(0, separator),
    int.parse(emulatorHost.substring(separator + 1)),
  );
  try {
    final created = await connector.createOwner(name: 'Ada').execute();
    print('created owner ${created.data.owner_insert.id}');
    final owners = await connector.listOwners().execute();
    for (final owner in owners.data.owners) {
      print('${owner.id}: ${owner.name}');
    }
  } on compat.DataConnectError catch (e) {
    stderr.writeln('Failed: ${e.code}: ${e.message}');
    exitCode = 1;
  }
}
