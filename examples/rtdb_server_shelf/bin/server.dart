// A notes API on package:shelf over one shared Realtime Database client.
// See README.md for how to run it.

import 'dart:async';
import 'dart:io';

import 'package:firebase_database_dart/firebase_database_dart.dart';
import 'package:rtdb_server_shelf/database_from_env.dart';
import 'package:rtdb_server_shelf/notes_api.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<void> main() async {
  final FirebaseDatabase db;
  try {
    db = databaseFromEnvironment();
  } on ConfigurationError catch (e) {
    stderr.writeln(e);
    exitCode = 64;
    return;
  }
  final NotesApi api = NotesApi(db);
  final int port = int.parse(Platform.environment['PORT'] ?? '8000');
  final HttpServer server = await shelf_io.serve(
    const Pipeline().addMiddleware(logRequests()).addHandler(api.handler),
    InternetAddress.anyIPv4,
    port,
  );
  print('Listening on http://localhost:${server.port}');

  // Ctrl-C locally, SIGTERM from hosts: stop accepting requests, end the event
  // streams (which cancels their listeners), then close the database.
  final Completer<void> stop = Completer<void>();
  void onSignal(ProcessSignal signal) {
    if (!stop.isCompleted) {
      stop.complete();
    }
  }

  final List<StreamSubscription<ProcessSignal>> signals =
      <StreamSubscription<ProcessSignal>>[
        ProcessSignal.sigint.watch().listen(onSignal),
        if (!Platform.isWindows) ProcessSignal.sigterm.watch().listen(onSignal),
      ];
  await stop.future;
  for (final StreamSubscription<ProcessSignal> signal in signals) {
    await signal.cancel();
  }
  // then<void>: the Future of close is not a Future<void> at run time, and timeout checks its
  // onTimeout against that type.
  final Future<void> closing = server.close(force: false).then<void>((_) {});
  await api.close();
  await closing.timeout(const Duration(seconds: 5), onTimeout: () {});
  await server.close(force: true);
  await db.close();
  print('Stopped');
}
