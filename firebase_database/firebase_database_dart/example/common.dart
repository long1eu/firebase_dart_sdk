// Setup shared by the examples in this directory: a FirebaseApp for the demo
// project `demo-example` and a FirebaseDatabase connected to the local
// Realtime Database emulator.
//
// Start the emulator with this repository's script, from the repository root
// (port 9100; the Firebase CLI's own default, 9000, is refused by the script
// because other tools use it):
//
//     tool/start_database_emulator.sh
//
// and run any example from this package with
//
//     FIREBASE_DATABASE_EMULATOR_HOST=127.0.0.1:9100 dart run example/<name>.dart
//
// Every program needs the variable and stops with a message without it, so an
// example can never reach a real project.

import 'dart:convert';
import 'dart:io';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_database_dart/firebase_database_dart.dart';

/// The project of the emulator; "demo-" projects never reach production.
const String projectId = 'demo-example';

/// The namespace of the emulator database of [projectId], what the client uses
/// without a database URL.
const String namespace = '$projectId-default-rtdb';

/// Rules that allow every read and write: what the emulator starts with.
const String openRules = '{"rules": {".read": true, ".write": true}}';

/// The port of the Realtime Database emulator when the variable names none.
const int defaultEmulatorPort = 9100;

/// A new [FirebaseApp] for the `demo-example` project. The emulator accepts
/// any API key and application id.
FirebaseApp exampleApp([String name = defaultFirebaseAppName]) {
  return FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: 'demo-key',
      appId: '1:1234567890:dart:example',
      projectId: projectId,
    ),
    name: name,
  );
}

/// The emulator address from `FIREBASE_DATABASE_EMULATOR_HOST`, with port 9100
/// added when the value has none. The program stops with a message when the
/// variable is not set.
String emulatorHost() {
  final String? host = FirebaseDatabase.emulatorHostFromEnvironment;
  if (host == null || host.isEmpty) {
    stderr.writeln(
      'Set FIREBASE_DATABASE_EMULATOR_HOST=host:port (see example/common.dart).',
    );
    exit(64);
  }
  final bool hasPort = host.startsWith('[')
      ? host.contains(']:')
      : host.contains(':');
  return hasPort ? host : '$host:$defaultEmulatorPort';
}

/// Replaces the rules of [namespace] on the emulator with [rules] (JSON), through
/// its REST endpoint `PUT /.settings/rules.json?ns=<namespace>` with the
/// `owner` credential, which the emulator accepts as an admin.
///
/// Stops with a message instead of sending anything when the address from
/// `FIREBASE_DATABASE_EMULATOR_HOST` is a real Firebase host, or when
/// [projectId] is not a `demo-` project, so that this never touches a real
/// database. Throws a [StateError] when the emulator refuses the rules (for
/// example, invalid JSON).
Future<void> setEmulatorRules(String rules) async {
  final String host = emulatorHost();
  if (!projectId.startsWith('demo-') ||
      host.contains('firebaseio.com') ||
      host.contains('firebasedatabase.app')) {
    stderr.writeln('Refusing to change rules: $host is not a local emulator.');
    exit(64);
  }
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request = await client.putUrl(
      Uri.parse('http://$host/.settings/rules.json?ns=$namespace'),
    );
    request.headers.set('Authorization', 'Bearer owner');
    request.write(rules);
    final HttpClientResponse response = await request.close();
    final String body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw StateError(
        'The emulator at $host refused the rules '
        '(${response.statusCode}): $body',
      );
    }
  } finally {
    client.close();
  }
}

/// A [FirebaseDatabase] connected to the emulator. [mockUserToken] makes the
/// emulator treat the connection as a signed-in user (see
/// auth_and_rules.dart). Give a second instance in one program its own
/// [appName]: each instance has its own connection.
FirebaseDatabase emulatorDatabase({
  String? mockUserToken,
  String appName = defaultFirebaseAppName,
}) {
  return FirebaseDatabase(
    exampleApp(appName),
    emulatorHost: emulatorHost(),
    mockUserToken: mockUserToken,
  );
}

/// A key that no earlier run has used, `example-<name>-<timestamp>`, so that
/// examples do not see each other's data.
String freshKey(String name) =>
    'example-$name-${DateTime.now().microsecondsSinceEpoch}';

/// Runs [body] with a database and a reference to a fresh key (see [freshKey]), then
/// removes that key and closes the database, also when [body] throws.
Future<void> runExample(
  String name,
  Future<void> Function(FirebaseDatabase db, DatabaseReference root) body, {
  String? mockUserToken,
}) async {
  final FirebaseDatabase db = emulatorDatabase(mockUserToken: mockUserToken);
  final DatabaseReference root = db.ref(freshKey(name));
  try {
    await body(db, root);
  } finally {
    try {
      await root.remove();
    } finally {
      await db.close();
    }
  }
}

/// Gives the streams a moment. Local events are delivered in a microtask after
/// the write that caused them, and events caused by the server take a round
/// trip.
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 50));

/// `key=value` of each child of [snapshot], in the order of the query that
/// produced it.
String describe(DataSnapshot snapshot) =>
    snapshot.children.map((DataSnapshot c) => '${c.key}=${c.value}').join(', ');

/// The current result of [query], read with a listener.
///
/// `Query.get` asks the server to run the query, and the server refuses an
/// ordered query on a child or on values unless the rules have an `.indexOn`
/// for it (`index-not-defined`). A listener has no such limit: without the
/// index the client downloads the location and filters it itself, and logs a
/// warning. The examples run with any rules, so they read this way; with the
/// index in your rules, `get` works and downloads only the result.
Future<DataSnapshot> once(Query query) async => (await query.once()).snapshot;
