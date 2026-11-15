// Adds jobs to the queue: `dart run bin/enqueue.dart [count]` (default 20).
// Each job is `{status: 'pending', n: <i>, createdAt: <server time>}`.

import 'dart:io';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:worker_queue/firestore_from_env.dart';

Future<void> main(List<String> arguments) async {
  final int count = arguments.isEmpty ? 20 : int.parse(arguments.first);
  final Firestore firestore;
  try {
    firestore = firestoreFromEnvironment();
  } on ConfigurationError catch (error) {
    stderr.writeln(error);
    exit(78);
  }
  final CollectionReference<Map<String, Object?>> jobs = firestore.collection(
    Platform.environment['JOBS_COLLECTION'] ?? 'jobs',
  );
  // One batch: at most 500 writes.
  final WriteBatch batch = firestore.batch();
  for (int i = 1; i <= count; i++) {
    batch.set(jobs.doc(), <String, Object?>{
      'status': 'pending',
      'n': i,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();
  print('enqueued $count jobs');
  await firestore.terminate();
}
