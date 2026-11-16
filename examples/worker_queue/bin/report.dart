// Prints the state of the queue and checks that no job ran more than once:
// every finished job must have exactly one record in its `runs`
// subcollection. Exits with 1 when one has more.

import 'dart:io';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:worker_queue/firestore_from_env.dart';

Future<void> main() async {
  final FirebaseFirestore firestore;
  try {
    firestore = firestoreFromEnvironment();
  } on ConfigurationError catch (error) {
    stderr.writeln(error);
    exit(78);
  }
  final QuerySnapshot<Map<String, Object?>> jobs = await firestore
      .collection(Platform.environment['JOBS_COLLECTION'] ?? 'jobs')
      .get(const GetOptions(source: Source.server));

  final Map<String, int> byStatus = <String, int>{};
  final Map<String, int> byWorker = <String, int>{};
  final List<String> twice = <String>[];
  for (final QueryDocumentSnapshot<Map<String, Object?>> job in jobs.docs) {
    final String status = '${job.data()['status']}';
    byStatus[status] = (byStatus[status] ?? 0) + 1;
    final QuerySnapshot<Map<String, Object?>> runs = await job.reference
        .collection('runs')
        .get(const GetOptions(source: Source.server));
    for (final QueryDocumentSnapshot<Map<String, Object?>> run in runs.docs) {
      final String worker = '${run.data()['worker']}';
      byWorker[worker] = (byWorker[worker] ?? 0) + 1;
    }
    if (runs.length > 1) {
      twice.add('${job.id} (${runs.length} runs)');
    }
  }
  await firestore.terminate();

  print('jobs: ${jobs.length} $byStatus');
  print('runs per worker: $byWorker');
  if (twice.isEmpty) {
    print('no job ran more than once');
  } else {
    print('ran more than once: ${twice.join(', ')}');
    exit(1);
  }
}
