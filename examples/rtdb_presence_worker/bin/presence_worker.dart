// Keeps a presence record in the Realtime Database (`worker`, the default) or
// lists who is online (`watch`), until SIGINT or SIGTERM. See README.md.

import 'dart:async';
import 'dart:io';

import 'package:firebase_database_dart/firebase_database_dart.dart';
import 'package:rtdb_presence_worker/database_from_env.dart';
import 'package:rtdb_presence_worker/presence.dart';

const String usage = '''
usage: dart run bin/presence_worker.dart [worker|watch] [options]

  --id <name>              worker id (WORKER_ID, default <host>-<pid>)
  --heartbeat <seconds>    heartbeat period (default 10)
  --emulator-host <h:p>    default FIREBASE_DATABASE_EMULATOR_HOST
  --database-url <url>     default FIREBASE_DATABASE_URL
''';

Future<void> main(List<String> args) async {
  final List<String> rest = <String>[...args];
  final String mode = rest.isNotEmpty && !rest.first.startsWith('-')
      ? rest.removeAt(0)
      : 'worker';
  final Map<String, String> flags = <String, String>{};
  for (int i = 0; i < rest.length; i += 2) {
    if (!rest[i].startsWith('--') || i + 1 >= rest.length) {
      stderr.write(usage);
      exit(64);
    }
    flags[rest[i].substring(2)] = rest[i + 1];
  }
  if (mode != 'worker' && mode != 'watch') {
    stderr.write(usage);
    exit(64);
  }

  final FirebaseDatabase database;
  try {
    database = databaseFromConfiguration(
      emulatorHost: flags['emulator-host'],
      databaseUrl: flags['database-url'],
    );
  } on ConfigurationError catch (error) {
    stderr.writeln(error);
    exit(78);
  }

  // Ctrl-C locally, SIGTERM from Kubernetes, systemd or `docker stop`.
  final Completer<void> stopRequested = Completer<void>();
  void request(ProcessSignal _) {
    if (!stopRequested.isCompleted) stopRequested.complete();
  }

  final List<StreamSubscription<ProcessSignal>> signals =
      <StreamSubscription<ProcessSignal>>[
        ProcessSignal.sigint.watch().listen(request),
        if (!Platform.isWindows) ProcessSignal.sigterm.watch().listen(request),
      ];

  int code = 0;
  if (mode == 'watch') {
    print('watching $statusPath');
    await watchOnline(database, stop: stopRequested.future);
    await database.close();
  } else {
    final String id =
        flags['id'] ??
        Platform.environment['WORKER_ID'] ??
        '${Platform.localHostname}-$pid';
    final int seconds = int.tryParse(flags['heartbeat'] ?? '10') ?? 10;
    final PresenceWorker worker = PresenceWorker(
      database,
      workerId: id,
      heartbeat: Duration(seconds: seconds < 1 ? 1 : seconds),
      log: (String line) => print(line),
    );
    worker.start();
    // Either a stop signal, or a failure such as `permission-denied`.
    try {
      await Future.any(<Future<void>>[stopRequested.future, worker.failed]);
    } catch (error) {
      stderr.writeln('$id: $error');
      code = 1;
    }
    if (!await worker.stop()) code = 1;
    print('$id: stopped');
  }
  for (final StreamSubscription<ProcessSignal> signal in signals) {
    await signal.cancel();
  }
  exit(code);
}
