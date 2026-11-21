import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage_dart/firebase_storage_dart.dart' as fs;
import 'package:firebase_storage_platform_interface/firebase_storage_platform_interface.dart';

import 'errors.dart';
import 'metadata.dart';
import 'reference.dart';

/// A snapshot of a [DartTask].
class DartTaskSnapshot extends TaskSnapshotPlatform {
  DartTaskSnapshot(
    this._ref,
    TaskState state, {
    required int bytesTransferred,
    required int totalBytes,
    Map<String, dynamic>? metadata,
  }) : super(state, <String, dynamic>{
         'bytesTransferred': bytesTransferred,
         'totalBytes': totalBytes,
         'metadata': metadata,
       });

  final ReferencePlatform _ref;

  @override
  ReferencePlatform get ref => _ref;
}

/// What the upload and download tasks share: the latest snapshot, the stream
/// of snapshots and the future of the end.
///
/// As with the official plugin, [snapshotEvents] is a broadcast stream: it
/// emits a snapshot on each change while there are listeners, then the last
/// one (`success`) or the error, and closes. A failed or canceled task
/// completes [onComplete] with a [FirebaseException] (`canceled` for a
/// canceled one), whose snapshot has the state `error` or `canceled`.
abstract class DartTask extends TaskPlatform {
  DartTask(this.ref, {int totalBytes = 0})
    : _snapshot = DartTaskSnapshot(
        ref,
        TaskState.running,
        bytesTransferred: 0,
        totalBytes: totalBytes,
      );

  /// The reference of the object the task writes or reads.
  final DartReference ref;

  final StreamController<TaskSnapshotPlatform> _events =
      StreamController<TaskSnapshotPlatform>.broadcast(sync: true);

  // Ignored here so that a failure nobody awaits is not an unhandled error;
  // whoever awaits onComplete still gets it.
  final Completer<TaskSnapshotPlatform> _done =
      Completer<TaskSnapshotPlatform>()..future.ignore();

  DartTaskSnapshot _snapshot;

  /// Whether the task has succeeded, failed or been canceled.
  bool get isFinished => _done.isCompleted;

  @override
  Stream<TaskSnapshotPlatform> get snapshotEvents => _events.stream;

  @override
  TaskSnapshotPlatform get snapshot => _snapshot;

  @override
  Future<TaskSnapshotPlatform> get onComplete => _done.future;

  /// Records a snapshot in [state] and emits it, unless the task is finished.
  void emit(
    TaskState state,
    int bytesTransferred,
    int totalBytes, {
    bool silent = false,
  }) {
    if (isFinished) {
      return;
    }
    _snapshot = DartTaskSnapshot(
      ref,
      state,
      bytesTransferred: bytesTransferred,
      totalBytes: totalBytes,
    );
    if (!silent) {
      _events.add(_snapshot);
    }
  }

  /// Ends the task with a `success` snapshot.
  void succeed(int bytesTransferred, int totalBytes, fs.FullMetadata metadata) {
    if (isFinished) {
      return;
    }
    _snapshot = DartTaskSnapshot(
      ref,
      TaskState.success,
      bytesTransferred: bytesTransferred,
      totalBytes: totalBytes,
      metadata: metadataMapOf(metadata),
    );
    _events.add(_snapshot);
    _done.complete(_snapshot);
    unawaited(_events.close());
  }

  /// Ends the task with [error], as a [FirebaseException] when it is one of
  /// the client's. The code `canceled` gives the state `canceled`, any other
  /// error the state `error`.
  void fail(Object error, StackTrace stackTrace) {
    if (isFinished) {
      return;
    }
    final Object converted = convertError(error, stackTrace);
    final bool canceled =
        converted is FirebaseException && converted.code == 'canceled';
    _snapshot = DartTaskSnapshot(
      ref,
      canceled ? TaskState.canceled : TaskState.error,
      bytesTransferred: _snapshot.bytesTransferred,
      totalBytes: _snapshot.totalBytes,
    );
    _events.addError(converted, stackTrace);
    _done.completeError(converted, stackTrace);
    unawaited(_events.close());
  }

  /// The exception of a task canceled by [cancel].
  static FirebaseException canceledException() =>
      storageException('canceled', 'The operation was canceled.');
}

/// A resumable upload of the client (`UploadTask` of `firebase_storage_dart`)
/// as a FlutterFire task.
class DartUploadTask extends DartTask {
  DartUploadTask._(super.ref, this._task) : super(totalBytes: _task.totalBytes);

  /// Starts the upload that [create] returns. When [create] throws (a string
  /// that does not match its format, for example), the task fails with that
  /// error, after the caller had the chance to listen.
  static DartTask start(DartReference ref, fs.UploadTask Function() create) {
    final fs.UploadTask task;
    try {
      task = create();
    } catch (error, stackTrace) {
      return _FailedTask(ref, error, stackTrace);
    }
    return DartUploadTask._(ref, task).._listen();
  }

  final fs.UploadTask _task;

  void _listen() {
    _task.progress.listen(
      (fs.UploadProgress progress) {
        // The end comes from the result, with the metadata or the error.
        switch (progress.state) {
          case fs.UploadState.running:
            emit(
              TaskState.running,
              progress.bytesTransferred,
              progress.totalBytes,
            );
          case fs.UploadState.paused:
            emit(
              TaskState.paused,
              progress.bytesTransferred,
              progress.totalBytes,
            );
          case fs.UploadState.success:
          case fs.UploadState.canceled:
          case fs.UploadState.error:
            break;
        }
      },
      // The same error reaches the result.
      onError: (Object _) {},
    );
    _task.result.then(
      (fs.FullMetadata metadata) =>
          succeed(_task.bytesTransferred, _task.totalBytes, metadata),
      onError: fail,
    );
  }

  @override
  Future<bool> pause() async {
    final bool paused = _task.pause();
    if (paused) {
      emit(
        TaskState.paused,
        _task.bytesTransferred,
        _task.totalBytes,
        silent: true,
      );
    }
    return paused;
  }

  @override
  Future<bool> resume() async {
    final bool resumed = _task.resume();
    if (resumed) {
      emit(
        TaskState.running,
        _task.bytesTransferred,
        _task.totalBytes,
        silent: true,
      );
    }
    return resumed;
  }

  /// Cancels the upload, from `running` or `paused`; the task then fails with
  /// the code `canceled`.
  @override
  Future<bool> cancel() async => _task.cancel();
}

/// A task that failed before it started.
class _FailedTask extends DartTask {
  _FailedTask(super.ref, Object error, StackTrace stackTrace) {
    scheduleMicrotask(() => fail(error, stackTrace));
  }

  @override
  Future<bool> pause() async => false;

  @override
  Future<bool> resume() async => false;

  @override
  Future<bool> cancel() async => false;
}

/// `writeToFile`: reads the object with `openRead` of the client into a
/// temporary file next to the target, and renames it over the target at the
/// end. The size comes from the metadata of the object, read first.
///
/// Pausing stops reading the response (the connection stays open); canceling
/// closes it and removes the temporary file. On an error the target is left
/// as it was.
class DartDownloadTask extends DartTask {
  DartDownloadTask._(super.ref, this._file);

  /// Starts the download of [ref] to [file].
  static DartTask start(DartReference ref, File file) =>
      DartDownloadTask._(ref, file).._run();

  final File _file;
  StreamIterator<List<int>>? _reader;
  bool _paused = false;
  bool _canceled = false;
  Completer<void>? _resumed;

  Future<void> _run() async {
    final File temporary = File(
      '${_file.path}.download-${DateTime.now().microsecondsSinceEpoch}',
    );
    RandomAccessFile? output;
    try {
      final fs.Reference source = ref.clientRef;
      final fs.FullMetadata metadata = await source.metadata();
      final int total = metadata.size ?? 0;
      if (_canceled) {
        return;
      }
      emit(_paused ? TaskState.paused : TaskState.running, 0, total);
      output = await temporary.open(mode: FileMode.write);
      final StreamIterator<List<int>> reader = _reader = StreamIterator(
        source.openRead(),
      );
      int written = 0;
      while (await _waitWhilePaused() && await reader.moveNext()) {
        await output.writeFrom(reader.current);
        written += reader.current.length;
        emit(TaskState.running, written, total);
      }
      await output.close();
      output = null;
      if (_canceled) {
        await _delete(temporary);
        return;
      }
      await temporary.rename(_file.path);
      succeed(written, total, metadata);
    } catch (error, stackTrace) {
      await output?.close();
      await _delete(temporary);
      fail(error, stackTrace);
    }
  }

  /// Waits while the task is paused; false when it was canceled.
  Future<bool> _waitWhilePaused() async {
    while (_paused && !_canceled) {
      await (_resumed ??= Completer<void>()).future;
    }
    return !_canceled;
  }

  static Future<void> _delete(File file) async {
    try {
      await file.delete();
    } on FileSystemException {
      // It was never created.
    }
  }

  @override
  Future<bool> pause() async {
    if (isFinished || _paused) {
      return false;
    }
    _paused = true;
    emit(TaskState.paused, snapshot.bytesTransferred, snapshot.totalBytes);
    return true;
  }

  @override
  Future<bool> resume() async {
    if (isFinished || !_paused) {
      return false;
    }
    _paused = false;
    _wake();
    emit(TaskState.running, snapshot.bytesTransferred, snapshot.totalBytes);
    return true;
  }

  /// Cancels the download, from `running` or `paused`; the task fails with
  /// the code `canceled` at once, and the temporary file is removed.
  @override
  Future<bool> cancel() async {
    if (isFinished) {
      return false;
    }
    _canceled = true;
    _wake();
    fail(DartTask.canceledException(), StackTrace.current);
    await _reader?.cancel();
    return true;
  }

  void _wake() {
    _resumed?.complete();
    _resumed = null;
  }
}
