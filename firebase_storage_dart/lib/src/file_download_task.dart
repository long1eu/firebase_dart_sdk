// File created by
// Lung Razvan <long1eu>
// on 22/10/2018

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/src/internal/exponential_backoff_sender.dart';
import 'package:firebase_storage/src/internal/task_events.dart';
import 'package:firebase_storage/src/internal/task_impl.dart';
import 'package:firebase_storage/src/internal/task_proxy.dart';
import 'package:firebase_storage/src/network/get_network_request.dart';
import 'package:firebase_storage/src/network/network_request.dart';
import 'package:firebase_storage/src/storage_exception.dart';
import 'package:firebase_storage/src/storage_reference.dart';
import 'package:firebase_storage/src/storage_task.dart';
import 'package:firebase_storage/src/task.dart';

/// A task that downloads bytes of a GCS blob to a specified File.
class FileDownloadTask extends StorageTask<DownloadTaskSnapshot> {
  FileDownloadTask._(this.reference, this._destinationFile, SendPort sendPort)
      : _sender = ExponentialBackoffSender(
            reference.app, reference.storage.maxDownloadRetry),
        super(sendPort) {
    queue();
  }

  static const int kPreferredChunkSize = 256 * 1024; // 256KB
  static const String _tag = 'FileDownloadTask';

  @override
  final StorageReference reference;
  final File _destinationFile;

  dynamic _error;
  ExponentialBackoffSender _sender;
  String _eTagVerification;
  int _resumeOffset = 0;
  int _totalBytes = -1;
  int _resultCode = 0;
  int _bytesDownloaded = 0;

  static Task<DownloadTaskSnapshot> schedule(
      StorageReference storage, File destinationFile) {
    return proxySchedule(
      args: <String>[destinationFile.path],
      storage: storage,
      taskBuilder: TaskImpl.create,
      storageTaskBuilder: _execute,
    );
  }

  // ignore: prefer_constructors_over_static_methods
  static FileDownloadTask _execute(
      StorageReference reference, SendPort sendPort, List<dynamic> args) {
    final String path = args.first;
    final File destinationFile = File(path);
    return FileDownloadTask._(reference, destinationFile, sendPort);
  }

  @override
  Future<void> scheduleTask() => run().then((_) => ensureFinalState());

  /// Returns the number of bytes downloaded so far into the file.
  int get bytesDownloaded => _bytesDownloaded;

  /// Returns the total number of bytes to be downloaded. -1 if the content
  /// length is not known (if the source is sending using chunk encoding)
  int get totalBytes => _totalBytes;

  @override
  DownloadTaskSnapshot get snapStateImpl {
    return DownloadTaskSnapshot(
      reference.toString(),
      internalState,
      isCanceled,
      StorageException.fromExceptionAndHttpCode(_error, _resultCode),
      _bytesDownloaded + _resumeOffset,
      totalBytes,
    );
  }

  /// Returns whether we were able to completely download the file.
  Future<bool> _processResponse(final NetworkRequest request) async {
    bool success = true;
    final Stream<List<int>> stream = request.stream;
    IOSink output;

    if (stream != null) {
      if (!_destinationFile.existsSync()) {
        if (_resumeOffset > 0) {
          Log.e(
              _tag,
              'The file downloading to has been deleted: '
              '${_destinationFile.path}');
          throw StateError('expected a file to resume from.');
        }

        try {
          await _destinationFile.create(recursive: true);
        } on FileSystemException catch (_) {
          Log.w(_tag, 'unable to create file: ${_destinationFile.path}');
        }
      }

      if (_resumeOffset > 0) {
        Log.d(
            _tag,
            'Resuming download file ${_destinationFile.path} at '
            '$_resumeOffset');

        output = _destinationFile.openWrite(mode: FileMode.append);
      } else {
        // truncate if we are starting from scratch.
        output = _destinationFile.openWrite();
      }

      try {
        final Completer<void> completer = Completer<void>();
        stream.listen(
          (List<int> data) {
            int index = 0;
            while (index < data.length) {
              final int end = min(data.length, index + kPreferredChunkSize);
              final List<int> chunk = data.sublist(index, end);

              output.add(chunk);
              _bytesDownloaded += chunk.length;
              if (_error != null) {
                Log.d(
                    _tag, 'Exception occurred during file download. Retrying.');
                _error = null;
                success = false;
              }

              if (!tryChangeState(
                  state: StorageTask.kInternalStateInProgress,
                  userInitiated: false)) {
                success = false;
              }

              index = end;
            }
          },
          onDone: completer.complete,
          onError: completer.completeError,
        );

        await completer.future;
      } finally {
        await output.flush();
        await output.close();
      }
    } else {
      _error = StateError('Unable to open Firebase Storage stream.');
      success = false;
    }

    return success;
  }

  @override
  Future<void> run() async {
    if (_error != null) {
      tryChangeState(
          state: StorageTask.kInternalStateFailure, userInitiated: false);
      return;
    }

    if (!tryChangeState(
        state: StorageTask.kInternalStateInProgress, userInitiated: false)) {
      return;
    }

    do {
      _bytesDownloaded = 0;
      _error = null;
      _sender.reset();
      final NetworkRequest request =
          GetNetworkRequest(reference.storageUri, reference.app, _resumeOffset);

      await _sender.sendWithExponentialBackoff(request, closeRequest: false);
      _resultCode = request.resultCode;
      _error = request.error != null ? request.error : _error;

      bool success = _isValidHttpResponseCode(_resultCode) &&
          _error == null &&
          internalState == StorageTask.kInternalStateInProgress;

      if (success) {
        _totalBytes = request.resultingContentLength;
        final String newEtag = request.getResultString('ETag');
        if (newEtag != null &&
            newEtag.isNotEmpty &&
            _eTagVerification != null &&
            _eTagVerification != newEtag) {
          Log.w(
              _tag,
              'The file at the server has changed. Restarting from the '
              'beginning.');
          _resumeOffset = 0;
          _eTagVerification = null;
          await scheduleTask(); // reschedule
          return;
        }

        _eTagVerification = newEtag;

        try {
          success = await _processResponse(request);
        } catch (e) {
          Log.e(
              _tag,
              'Exception occurred during file write. Aborting. $e'
              '\n${e.stackTrace}');
          _error = e;
        }
      }

      success = success &&
          _error == null &&
          internalState == StorageTask.kInternalStateInProgress;

      if (success) {
        tryChangeState(
            state: StorageTask.kInternalStateSuccess, userInitiated: false);
        return;
      } else {
        if (_destinationFile.existsSync()) {
          _resumeOffset = await _destinationFile.length();
        } else {
          _resumeOffset = 0; // start over.
        }
        if (internalState == StorageTask.kInternalStatePausing) {
          tryChangeState(
              state: StorageTask.kInternalStatePaused, userInitiated: false);
          return;
        } else if (internalState == StorageTask.kInternalStateCanceling) {
          if (!tryChangeState(
              state: StorageTask.kInternalStateCanceled,
              userInitiated: false)) {
            Log.w(
                _tag,
                'Unable to change download task to final state from '
                '$internalState');
          }
          return;
        }
      }
    } while (_bytesDownloaded > 0);

    tryChangeState(
        state: StorageTask.kInternalStateFailure, userInitiated: false);
  }

  @override
  void onCanceled() {
    _sender.cancel();
    _error = StorageException.fromErrorStatus(Status.resultCanceled);
  }

  bool _isValidHttpResponseCode(int code) {
    return code == 308 || (code >= 200 && code < 300);
  }

  @override
  String toString() {
    return (ToStringHelper(runtimeType)
          ..add('storage', reference)
          ..add('destinationFile', _destinationFile)
          ..add('error', _error)
          ..add('sender', _sender)
          ..add('eTagVerification', _eTagVerification)
          ..add('resumeOffset', _resumeOffset)
          ..add('totalBytes', _totalBytes)
          ..add('resultCode', _resultCode)
          ..add('bytesDownloaded', _bytesDownloaded))
        .toString();
  }
}
