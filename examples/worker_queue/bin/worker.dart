// A worker that claims jobs from a Firestore collection, runs them and writes
// the results, until SIGINT (Ctrl-C) or SIGTERM. See README.md.

import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:worker_queue/firestore_from_env.dart';
import 'package:worker_queue/job_worker.dart';

Future<void> main() async {
  final Map<String, String> env = Platform.environment;
  final FirebaseFirestore firestore;
  try {
    firestore = firestoreFromEnvironment();
  } on ConfigurationError catch (error) {
    stderr.writeln(error);
    exit(78);
  }
  final String workerId = env['WORKER_ID'] ?? '${Platform.localHostname}-$pid';
  final JobWorker worker = JobWorker(
    firestore,
    workerId: workerId,
    collection: env['JOBS_COLLECTION'] ?? 'jobs',
    handler: square,
  );

  // Ctrl-C locally, SIGTERM from Cloud Run, Kubernetes or `docker stop`: let
  // the job in progress finish, then stop.
  final List<StreamSubscription<ProcessSignal>> signals =
      <StreamSubscription<ProcessSignal>>[
        ProcessSignal.sigint.watch().listen((_) => worker.stop()),
        if (!Platform.isWindows)
          ProcessSignal.sigterm.watch().listen((_) => worker.stop()),
      ];

  print('$workerId: waiting for jobs');
  int code = 0;
  try {
    await worker.run();
  } catch (error) {
    stderr.writeln('$workerId: the listener failed: $error');
    code = 1;
  }
  for (final StreamSubscription<ProcessSignal> signal in signals) {
    await signal.cancel();
  }

  // Every write of the worker is awaited, so nothing should be pending; this
  // is the step for programs that do not await their writes. It does not
  // complete while the backend is unreachable, hence the timeout.
  try {
    await firestore.waitForPendingWrites().timeout(const Duration(seconds: 5));
  } on TimeoutException {
    stderr.writeln('$workerId: writes still pending at shutdown');
    code = 1;
  }
  // Closes the streams; without it the process does not exit.
  await firestore.terminate();
  print(
    '$workerId: stopped after ${worker.jobsRun} jobs '
    '(${worker.claimsLost} claims lost to another worker)',
  );
  exit(code);
}

/// The work of a job: squares its `n`, slowly enough that two workers
/// interleave.
Future<Map<String, Object?>> square(Map<String, Object?> job) async {
  final num n = job['n']! as num;
  await Future<void>.delayed(const Duration(milliseconds: 200));
  return <String, Object?>{'square': n * n};
}
