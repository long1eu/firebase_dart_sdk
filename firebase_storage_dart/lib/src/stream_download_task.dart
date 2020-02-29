// File created by
// Lung Razvan <long1eu>
// on 06/11/2018

import 'dart:async';
import 'dart:isolate';

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_storage/src/cancel_exception.dart';
import 'package:firebase_storage/src/internal/exponential_backoff_sender.dart';
import 'package:firebase_storage/src/internal/task_events.dart';
import 'package:firebase_storage/src/internal/task_impl.dart';
import 'package:firebase_storage/src/internal/task_proxy.dart';
import 'package:firebase_storage/src/network/get_network_request.dart';
import 'package:firebase_storage/src/network/network_request.dart';
import 'package:firebase_storage/src/storage_exception.dart';
import 'package:firebase_storage/src/storage_reference.dart';
import 'package:firebase_storage/src/storage_task.dart';
import 'package:firebase_storage/src/streamed_task.dart';

/// A task that downloads bytes of a GCS blob.
@publicApi
class StreamDownloadTask extends StorageTask<DownloadStreamTaskSnapshot> {
  StreamDownloadTask._(this.reference, SendPort sendPort)
      : _sender = ExponentialBackoffSender(
          reference.app,
          reference.storage.maxDownloadRetry,
        ),
        super(sendPort);

  static const String _tag = 'StreamDownloadTask';
  static const int kPreferredChunkSize = 256 * 1024; // 256KB

  @override
  final StorageReference reference;
  final ExponentialBackoffSender _sender;

  dynamic _error;
  int _resultCode = 0;
  int _totalBytes = -1;
  int _bytesDownloaded = 0;
  int _bytesDownloadedSnapped = 0;
  List<int> _data;
  NetworkRequest _request;
  String _eTagVerification;

  static StreamedTask<DownloadStreamTaskSnapshot> schedule(
      StorageReference storage) {
    final StreamedTask<DownloadStreamTaskSnapshot> task =
        proxySchedule<DownloadStreamTaskSnapshot>(
      storage: storage,
      taskBuilder: StreamedTaskImpl.create,
      storageTaskBuilder: _createTask,
    );
    return task;
  }

  // ignore: prefer_constructors_over_static_methods
  static StreamDownloadTask _createTask(
      StorageReference reference, SendPort sendPort, List<dynamic> args) {
    return StreamDownloadTask._(reference, sendPort);
  }

  void _recordDownloadedBytes(int bytesDownloaded) {
    _bytesDownloaded += bytesDownloaded;
    if (_bytesDownloadedSnapped + kPreferredChunkSize <= _bytesDownloaded) {
      if (internalState == StorageTask.kInternalStateInProgress) {
        tryChangeState(
            state: StorageTask.kInternalStateInProgress, userInitiated: false);
      } else {
        _bytesDownloadedSnapped = _bytesDownloaded;
      }
    }
  }

  @override
  Future<void> scheduleTask() => run().then((_) => ensureFinalState());

  @override
  DownloadStreamTaskSnapshot get snapStateImpl => DownloadStreamTaskSnapshot(
        reference.toString(),
        internalState,
        isCanceled,
        StorageException.fromExceptionAndHttpCode(_error, _resultCode),
        _bytesDownloadedSnapped,
        _totalBytes,
        _data,
      );

  Future<List<int>> _getChunk() async {
    _sender.reset();

    _request = GetNetworkRequest(
      reference.storageUri,
      reference.app,
      _bytesDownloaded,
    );

    await _sender.sendWithExponentialBackoff(_request, closeRequest: false);

    _resultCode = _request.resultCode;
    _error = _request.error != null ? _request.error : _error;

    final bool success = _isValidHttpResponseCode(_resultCode) &&
        _error == null &&
        internalState == StorageTask.kInternalStateInProgress;

    if (success) {
      final String newETag = _request.getResultString('ETag');
      if (newETag != null &&
          newETag.isNotEmpty &&
          _eTagVerification != null &&
          _eTagVerification != newETag) {
        _resultCode = 409; // Conflict
        throw StateError('The ETag on the server changed.');
      }

      _eTagVerification = newETag;
      if (_totalBytes == -1) {
        _totalBytes = _request.resultingContentLength;
      }

      return _request.stream.first;
    } else {
      throw StateError('Could not open resulting stream.');
    }
  }

  bool _isValidHttpResponseCode(int code) {
    return code == 308 || (code >= 200 && code < 300);
  }

  @override
  Future<void> run() async {
    if (_error != null) {
      tryChangeState(
          state: StorageTask.kInternalStateFailure, userInitiated: false);
    }

    if (!tryChangeState(
        state: StorageTask.kInternalStateInProgress, userInitiated: false)) {
      return;
    }

    do {
      _data = await _getChunk();
      _recordDownloadedBytes(_data.length);
      _checkCancel();
    } while (_bytesDownloaded < _totalBytes);

    final bool success =
        _error == null && internalState == StorageTask.kInternalStateInProgress;

    if (success) {
      tryChangeState(
          state: StorageTask.kInternalStateInProgress, userInitiated: false);
      tryChangeState(
          state: StorageTask.kInternalStateSuccess, userInitiated: false);
    } else {
      if (!tryChangeState(
          state: internalState == StorageTask.kInternalStateCanceling
              ? StorageTask.kInternalStateCanceled
              : StorageTask.kInternalStateFailure,
          userInitiated: false)) {
        Log.w(
            _tag,
            'Unable to change download task to final state from '
            '$internalState');
      }
    }
  }

  void _checkCancel() {
    if (internalState == StorageTask.kInternalStateCanceling) {
      throw CancelException();
    }
  }

  @override
  bool resume() {
    throw StateError('This operation is not support on StreamDownloadTask.');
  }

  @override
  bool pause() {
    throw StateError('This operation is not support on StreamDownloadTask.');
  }

  @override
  void onCanceled() {
    _sender.cancel();
    _error = StorageException.fromErrorStatus(Status.resultCanceled);
  }

  @override
  void onProgress() {
    _bytesDownloadedSnapped = _bytesDownloaded;
  }
}
