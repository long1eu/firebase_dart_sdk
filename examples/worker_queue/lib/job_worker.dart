import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';

/// What a job computes from its fields. It may throw: the job is then marked
/// `failed` with the error.
typedef JobHandler =
    Future<Map<String, Object?>> Function(Map<String, Object?> job);

/// A worker that takes jobs from a collection, one at a time.
///
/// A job is a document with `status: 'pending'`. The worker:
///
/// 1. listens to the pending jobs (one query listener), and wakes up when
///    the listener reports any;
/// 2. claims a job in a transaction: it reads the job and, only if it is still
///    `pending`, sets it to `running` with its own name. When two workers
///    claim the same job, the backend accepts one commit; the other
///    transaction is run again, reads `running` and gives up. So a job is
///    claimed once;
/// 3. runs [handler] and writes the result and a record of the run (in
///    `<job>/runs`) in one batch, with `status: 'done'` (or `failed`).
///
/// [stop] lets the job in progress finish and then returns; it does not
/// terminate the Firestore instance.
class JobWorker {
  JobWorker(
    this.firestore, {
    required this.workerId,
    required this.handler,
    this.collection = 'jobs',
    void Function(String line)? log,
  }) : _log = log ?? print;

  final FirebaseFirestore firestore;

  /// The name written into the jobs this worker claims.
  final String workerId;

  final JobHandler handler;

  /// The collection of the jobs.
  final String collection;

  final void Function(String line) _log;

  final Random _random = Random.secure();

  StreamSubscription<QuerySnapshot<Map<String, Object?>>>? _listener;
  List<String> _pending = <String>[];
  bool _changed = false;
  Completer<void>? _wake;
  bool _stopping = false;
  Future<void>? _loop;
  (Object, StackTrace)? _listenerError;

  /// The number of jobs this worker ran.
  int get jobsRun => _jobsRun;
  int _jobsRun = 0;

  /// The number of jobs this worker tried to claim and found taken by another
  /// worker.
  int get claimsLost => _claimsLost;
  int _claimsLost = 0;

  CollectionReference<Map<String, Object?>> get _jobs =>
      firestore.collection(collection);

  /// Starts listening and working. Completes when the worker has stopped,
  /// after [stop] or when the listener failed (the error is rethrown then).
  Future<void> run() {
    // The pending jobs, 20 at a time. A filter on one field needs no
    // composite index; the jobs come in the order of their ids.
    final Query<Map<String, Object?>> pending = _jobs
        .where('status', isEqualTo: 'pending')
        .limit(20);
    _listener = pending.snapshots().listen(
      (QuerySnapshot<Map<String, Object?>> snapshot) {
        _pending = <String>[
          for (final QueryDocumentSnapshot<Map<String, Object?>> job
              in snapshot.docs)
            job.id,
        ];
        _signal();
      },
      onError: (Object error, StackTrace stackTrace) {
        // A listener ends on an error such as permission-denied. A lost
        // connection is not an error: the client reconnects by itself.
        _listenerError = (error, stackTrace);
        _stopping = true;
        _signal();
      },
    );
    return _loop = _work();
  }

  /// Stops taking jobs, lets the job in progress finish, and stops the
  /// listener.
  Future<void> stop() async {
    _stopping = true;
    _signal();
    await _loop;
  }

  void _signal() {
    _changed = true;
    final Completer<void>? wake = _wake;
    if (wake != null && !wake.isCompleted) {
      wake.complete();
    }
  }

  Future<void> _work() async {
    try {
      while (!_stopping) {
        _changed = false;
        bool ranOne = false;
        for (final String id in List<String>.of(_pending)) {
          if (_stopping) {
            break;
          }
          final Map<String, Object?>? job = await _claim(_jobs.doc(id));
          if (job != null) {
            await _process(_jobs.doc(id), job);
            ranOne = true;
            // The listener has moved on in the meantime: start from its
            // latest list again.
            break;
          }
        }
        if (!ranOne && !_changed && !_stopping) {
          // Nothing to do until the listener reports a change.
          _wake = Completer<void>();
          await _wake!.future;
          _wake = null;
        }
      }
    } finally {
      await _listener?.cancel();
    }
    final (Object, StackTrace)? failure = _listenerError;
    if (failure != null) {
      Error.throwWithStackTrace(failure.$1, failure.$2);
    }
  }

  /// Claims [ref] for this worker. Returns the fields of the job, or null when
  /// it is not pending any more (another worker took it, or it was deleted).
  Future<Map<String, Object?>?> _claim(
    DocumentReference<Map<String, Object?>> ref,
  ) async {
    // A random id for this claim. If the answer to a commit is lost, the
    // transaction is run again and finds the job already claimed with this
    // id: it is ours, not another worker's.
    final String claim = _random.nextInt(1 << 32).toRadixString(16);
    try {
      return await firestore.runTransaction<Map<String, Object?>?>((
        Transaction transaction,
      ) async {
        final DocumentSnapshot<Object?> snapshot = await transaction.get(ref);
        final Map<String, Object?>? job =
            snapshot.data() as Map<String, Object?>?;
        if (job == null) {
          return null;
        }
        if (job['status'] == 'running' && job['claim'] == claim) {
          return job;
        }
        if (job['status'] != 'pending') {
          if (job['worker'] != workerId) {
            _claimsLost++;
          }
          return null;
        }
        transaction.update(ref, <String, Object?>{
          'status': 'running',
          'worker': workerId,
          'claim': claim,
          'claimedAt': FieldValue.serverTimestamp(),
        });
        return job;
      });
    } on FirestoreException catch (error) {
      // For example `unavailable` while the backend cannot be reached, or
      // `aborted` after too many conflicts. The job stays pending.
      _log('$workerId: could not claim ${ref.id}: ${error.code}');
      await Future<void>.delayed(const Duration(seconds: 1));
      return null;
    }
  }

  Future<void> _process(
    DocumentReference<Map<String, Object?>> ref,
    Map<String, Object?> job,
  ) async {
    Map<String, Object?> update;
    try {
      final Map<String, Object?> result = await handler(job);
      update = <String, Object?>{'status': 'done', 'result': result};
      _log('$workerId: ran ${ref.id} -> $result');
    } catch (error) {
      update = <String, Object?>{'status': 'failed', 'error': '$error'};
      _log('$workerId: ${ref.id} failed: $error');
    }
    _jobsRun++;
    // The result and the record of this run, atomically. The record is what
    // bin/report.dart counts: a job that ran twice would have two.
    final WriteBatch batch = firestore.batch()
      ..update(ref, <String, Object?>{
        ...update,
        'finishedAt': FieldValue.serverTimestamp(),
      })
      ..set(ref.collection('runs').doc(), <String, Object?>{
        'worker': workerId,
        'at': FieldValue.serverTimestamp(),
      });
    await batch.commit();
  }
}
