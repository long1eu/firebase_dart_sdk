// File created by
// Lung Razvan <long1eu>
// on 22/10/2018

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_storage/src/controllable_future_handle.dart';
import 'package:firebase_storage/src/firebase_storage.dart';
import 'package:firebase_storage/src/internal/exponential_backoff_sender.dart';
import 'package:firebase_storage/src/internal/task_events.dart';
import 'package:firebase_storage/src/network/get_network_request.dart';
import 'package:firebase_storage/src/network/network_request.dart';
import 'package:firebase_storage/src/storage_exception.dart';
import 'package:firebase_storage/src/storage_reference.dart';
import 'package:firebase_storage/src/storage_task.dart';
import 'package:firebase_storage/src/storage_task_scheduler.dart';
import 'package:rxdart/rxdart.dart';

Future<void> _execute(List<dynamic> arguments) async {
  final SendPort sendPort = arguments[0];
  final ReceivePort receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);

  final String referenceUrl = arguments[1];
  final String path = arguments[2];

  // TODO:{22/10/2018 14:15}-long1eu: this is not good since we don't know if
  // this is the right FirestoreStorage instance
  final StorageReference storage =
      FirebaseStorage.instance.getReferenceFromUrl(referenceUrl);
  final File destinationFile = File(path);

  final FileDownloadTask task =
      FileDownloadTask._(storage, destinationFile, sendPort);

  receivePort.cast<List<dynamic>>().listen((List<dynamic> args) {
    final int id = args[0];
    final String method = args[1];
    bool result;
    if (method == 'cancel') {
      result = task.cancel();
    } else if (method == 'pause') {
      result = task.pause();
    } else if (method == 'resume') {
      result = task.resume();
    } else if (method == 'isCanceled') {
      result = task.isCompleted;
    } else if (method == 'isInProgress') {
      result = task.isInProgress;
    } else if (method == 'isPaused') {
      result = task.isPaused;
    }

    sendPort.send(<dynamic>[id, method, result]);
  });

  return task;
}

/// A task that downloads bytes of a GCS blob to a specified File.
@publicApi
class FileDownloadTask extends StorageTask<DownloadTaskSnapshot> {
  static const int kPreferredChunkSize = 256 * 1024; // 256KB
  static const String _tag = 'FileDownloadTask';

  @override
  final StorageReference storage;
  final File _destinationFile;

  dynamic _error;
  ExponentialBackoffSender _sender;
  String _eTagVerification;
  int _resumeOffset = 0;
  int _totalBytes = -1;
  int _resultCode = 0;
  int _bytesDownloaded;

  FileDownloadTask._(this.storage, this._destinationFile, SendPort sendPort)
      : _sender = ExponentialBackoffSender(
            storage.app, storage.storage.maxDownloadRetry),
        super(sendPort) {
    queue();
  }

  static Future<DownloadTaskSnapshot> schedule(
      StorageReference storage,
      File destinationFile,
      void onEvent(TaskEvent<DownloadTaskSnapshot> event)) {
    final ReceivePort receivePort = ReceivePort();
    final Stream<dynamic> received = receivePort.asBroadcastStream();

    FutureHandleImpl<DownloadTaskSnapshot> handle;
    SendPort taskPort;
    received.listen((dynamic data) {
      if (data is TaskEvent<DownloadTaskSnapshot>) {
        onEvent?.call(data);

        if (data.type == TaskEventType.success) {
          handle.complete(data.data);
        } else if (data.type == TaskEventType.error) {
          handle.completeError(data.data);
        }
      } else if (data is SendPort) {
        taskPort = data;
      } else if (data is List) {
        // this are method calls handled by the [FutureHandleImpl]
      } else {
        throw StateError('Something wrong came of the task ReceivePort. $data');
      }
    });

    StorageTaskScheduler.instance.scheduleDownload(_execute, <dynamic>[
      receivePort.sendPort,
      storage.toString(),
      destinationFile.path,
    ]).then((_) => receivePort.close());
    return handle = FutureHandleImpl<DownloadTaskSnapshot>(
        (dynamic message) => taskPort.send(message), received);
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
    return DownloadTaskSnapshot.base(
      storage.toString(),
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
        Observable<List<int>>(stream)
            .bufferCount(kPreferredChunkSize)
            .expand((List<List<int>> it) => it)
            .listen(
          (List<int> data) {
            output.add(data);
            _bytesDownloaded += data.length;
            if (_error != null) {
              Log.d(_tag, 'Exception occurred during file download. Retrying.');
              _error = null;
              success = false;
            }

            if (!tryChangeState(
                state: StorageTask.kInternalStateInProgress,
                userInitiated: false)) {
              success = false;
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
          GetNetworkRequest(storage.storageUri, storage.app, _resumeOffset);

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
          Log.e(_tag, 'Exception occurred during file write.  Aborting.');
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
  @publicApi
  void onCanceled() {
    _sender.cancel();
    _error = StorageException.fromErrorStatus(Status.resultCanceled);
  }

  bool _isValidHttpResponseCode(int code) {
    return code == 308 || (code >= 200 && code < 300);
  }
}
