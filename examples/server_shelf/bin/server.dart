// A task API on package:shelf backed by Firestore, with a real-time listener
// that sends every change to the connected clients as server-sent events.
// See README.md for how to run it.

import 'dart:async';
import 'dart:io';

import 'package:server_shelf/firestore_from_env.dart';
import 'package:server_shelf/task_api.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<void> main() async {
  final TaskApi api = TaskApi(
    firestoreFromEnvironment(),
    Platform.environment['TASKS_COLLECTION'] ?? 'tasks',
  );
  // Cloud Run and most hosts pass the port in PORT.
  final int port = int.parse(Platform.environment['PORT'] ?? '8000');
  final HttpServer server = await shelf_io.serve(
    const Pipeline().addMiddleware(logRequests()).addHandler(api.handler),
    InternetAddress.anyIPv4,
    port,
  );
  print('Listening on http://localhost:${server.port}');

  // Ctrl-C locally, SIGTERM from Cloud Run and Kubernetes: stop accepting
  // requests, end the event streams and terminate Firestore so that the
  // process exits.
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
  await server.close(force: true);
  await api.close();
  print('Stopped');
}
