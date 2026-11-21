// A file API on package:shelf backed by Cloud Storage for Firebase: uploads
// and downloads are streamed. See README.md for how to run it.

import 'dart:async';
import 'dart:io';

import 'package:firebase_storage_dart/firebase_storage_dart.dart';
import 'package:server_shelf/file_api.dart';
import 'package:server_shelf/storage_from_env.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<void> main() async {
  final FirebaseStorage storage = storageFromEnvironment();
  final int port = int.parse(Platform.environment['PORT'] ?? '8001');
  final HttpServer server = await shelf_io.serve(
    const Pipeline()
        .addMiddleware(logRequests())
        .addHandler(FileApi(storage).handler),
    InternetAddress.anyIPv4,
    port,
  );
  print('Listening on http://localhost:${server.port}');

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
  storage.close();
  print('Stopped');
}
