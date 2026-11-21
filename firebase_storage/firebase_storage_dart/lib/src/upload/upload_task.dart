import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../errors.dart';
import '../exception.dart';
import '../metadata.dart';
import '../reference.dart';
import '../request/requester.dart';
import 'upload_source.dart';

/// The state of an [UploadTask].
enum UploadState {
  /// Sending data, or waiting before it retries.
  running,

  /// Paused by [UploadTask.pause]; [UploadTask.resume] goes on where the server stopped.
  paused,

  /// Done: the object exists, [UploadTask.result] has its metadata.
  success,

  /// Stopped by [UploadTask.cancel]; [UploadTask.result] failed with `canceled`.
  canceled,

  /// Failed; [UploadTask.result] holds the error.
  error,
}

/// A snapshot of an [UploadTask], as emitted by [UploadTask.progress].
@immutable
final class UploadProgress {
  /// Creates a snapshot. The package creates them; you need this only in tests.
  const UploadProgress({
    required this.state,
    required this.bytesTransferred,
    required this.totalBytes,
    this.metadata,
  });

  /// The state of the task.
  final UploadState state;

  /// The bytes the server has confirmed so far.
  final int bytesTransferred;

  /// The size of the upload; -1 while it is unknown: a stream given to `Reference.startStreamUpload` without a
  /// `length`, until the task has read its end. The change has no event of its own: the next event (the
  /// confirmation of the last chunk, then success) is the first to carry the real size.
  final int totalBytes;

  /// The metadata of the new object, once [state] is [UploadState.success]; null before.
  final FullMetadata? metadata;

  @override
  bool operator ==(Object other) =>
      other is UploadProgress &&
      other.state == state &&
      other.bytesTransferred == bytesTransferred &&
      other.totalBytes == totalBytes &&
      other.metadata == metadata;

  @override
  int get hashCode =>
      Object.hash(state, bytesTransferred, totalBytes, metadata);

  @override
  String toString() {
    final String total = totalBytes < 0 ? '?' : '$totalBytes';
    return 'UploadProgress(${state.name}, $bytesTransferred/$total bytes)';
  }
}

/// The size above which an upload is resumable, and its first chunk: 256 KiB, as in the JS SDK.
@internal
const int resumableChunkSize = 256 * 1024;

/// The largest chunk when `FirebaseStorage.maxUploadChunkSize` is null: 16 MiB, the effective limit of the JS
/// SDK.
@internal
const int maxChunkSize = 16 * 1024 * 1024;

/// The shortest time between two progress events while a body is being sent.
const Duration _progressInterval = Duration(milliseconds: 100);

/// The longest wait between two attempts at a failing chunk.
const Duration _maxRetryWait = Duration(seconds: 64);

enum _Phase { running, pausing, paused, canceling, success, canceled, error }

/// An upload that can be paused, resumed and canceled, and reports its progress. It starts when it is created
/// (by `Reference.startUpload` or `Reference.startStreamUpload`); await [result] for the metadata of the new
/// object.
///
/// Up to 256 KiB the data goes in one multipart request, like `Reference.putBytes`. Larger data uses a
/// resumable upload session:
///
/// * On the VM, bytes (`Reference.startUpload`) and files (`putFile` of `package:firebase_storage_dart/io.dart`)
///   go in one streamed request with the rest of the data. After a failure or a pause the task asks the server
///   how much it has and streams the rest from there.
/// * A stream (`Reference.startStreamUpload`), everything on the web, and every upload of a `FirebaseStorage`
///   with a `maxUploadChunkSize` go in chunks: they start at 256 KiB and double after each one that succeeds,
///   up to 16 MiB (or `maxUploadChunkSize`). A stream needs chunks because the chunk is what is sent again
///   after a failure; the web, because the browser reports no progress inside a request.
/// * A stream without a `length` always uses a session, whatever its size. The session starts without the
///   total, [totalBytes] is -1 until the stream ended, and each chunk is sent once the task has read one
///   stream event past it (or the end), so that the last chunk carries `upload, finalize`.
///
/// When a request fails with a network error or a retryable status (5xx, 408, 429), the task waits (1 s,
/// doubling up to 64 s), asks the server how much it has, and goes on from there (with a 256 KiB chunk when
/// chunked); it gives up with `retry-limit-exceeded` once the failures have lasted the `upload` time of the
/// `StorageRetryPolicy`. A success resets both the wait and that time.
///
/// At most `FirebaseStorage.maxConcurrentUploads` uploads of one instance run at once. A task over the limit
/// waits its turn in [UploadState.running] with 0 bytes; [pause] and [cancel] work while it waits, and a
/// paused task gives its turn to the next one (it queues again when resumed).
///
/// ```dart
/// final UploadTask task = storage.ref('videos/clip.mp4').startUpload(bytes);
/// task.progress.listen((UploadProgress p) {
///   print('${p.state.name}: ${p.bytesTransferred} of ${p.totalBytes} bytes');
/// });
/// final FullMetadata metadata = await task.result;
/// ```
///
/// On the VM, [progress] also reports the bytes as they are written while a request is being sent, at most once per 64 KiB and per 100 ms, and always when the server confirms a
/// chunk. When a chunk fails, [bytesTransferred] goes back to what the server confirmed, with an event. On the
/// web the browser gives no upload progress, so the events come once per confirmed chunk.
///
/// The task is not a `Future`; pausing aborts the request in flight and resuming asks the server where it
/// stopped. [cancel] works while running and while paused.
final class UploadTask {
  /// Starts an upload of [source] to [ref] with [metadata]. Use `Reference.startUpload` or
  /// `Reference.startStreamUpload` instead.
  ///
  /// With [existingSessionUri] it resumes that session: it asks the server how much data it has first. Throws
  /// `invalid-argument` when that URI is not on the host of `ref.storage`.
  @internal
  UploadTask.start(
    this.ref,
    UploadSource source,
    SettableMetadata? metadata, {
    Uri? existingSessionUri,
  }) : _source = source,
       _metadata = metadata,
       _total = source.length {
    if (existingSessionUri != null) {
      if (!_onStorageHost(existingSessionUri)) {
        throw invalidArgument(
          'existingSessionUri is not an upload session of '
          '${ref.storage.origin}.',
        );
      }
      _sessionUrl = existingSessionUri;
      _needStatus = true;
      _adoptedSession = true;
    }
    _lastEventAt = _requester.now();
    _result.future.ignore();
    unawaited(_run());
  }

  /// The reference the data goes to.
  final Reference ref;

  /// The size of the upload in bytes; -1 while it is unknown (a stream given to `Reference.startStreamUpload`
  /// without a `length`, until the task has read its end). It changes to the size without an event on
  /// [progress]; the next event carries it.
  int get totalBytes => _total ?? -1;

  final UploadSource _source;

  /// The size of the data, once known.
  int? _total;
  final SettableMetadata? _metadata;
  final Completer<FullMetadata> _result = Completer<FullMetadata>();
  final StreamController<UploadProgress> _events =
      StreamController<UploadProgress>.broadcast();

  _Phase _phase = _Phase.running;
  int _transferred = 0;
  int _confirmed = 0;

  /// The end of the data handed to the client for this session so far; the server cannot have more.
  int _sent = 0;

  /// Whether the session came from `existingSessionUri` and its first query has not answered yet: until then
  /// the server may have bytes that this task never sent.
  bool _adoptedSession = false;
  DateTime? _lastEventAt;
  FullMetadata? _uploaded;
  bool _looping = false;

  Uri? _sessionUrl;
  bool _needStatus = false;
  bool _needMetadata = false;
  int _chunkSize = resumableChunkSize;
  Duration _retryWait = Duration.zero;
  bool _waitBeforeNextStep = false;
  DateTime? _failingSince;
  Completer<void>? _abort;
  bool _holdsSlot = false;
  (Object, StackTrace)? _sourceFailure;

  /// The state of the task.
  UploadState get state => switch (_phase) {
    _Phase.running || _Phase.pausing || _Phase.canceling => UploadState.running,
    _Phase.paused => UploadState.paused,
    _Phase.success => UploadState.success,
    _Phase.canceled => UploadState.canceled,
    _Phase.error => UploadState.error,
  };

  /// The bytes sent so far: those the server has confirmed, plus (on the VM) those of the chunk being sent. It
  /// goes back to the confirmed bytes when a chunk fails.
  int get bytesTransferred => _transferred;

  /// The current state as an [UploadProgress].
  UploadProgress get snapshot => UploadProgress(
    state: state,
    bytesTransferred: _transferred,
    totalBytes: totalBytes,
    metadata: _uploaded,
  );

  /// The progress of the upload: the current [snapshot] when you listen, then events while data is sent (on
  /// the VM at most one per 64 KiB and 100 ms, plus one per confirmed chunk; on the web one per chunk) and on
  /// each change of state ([UploadState.paused], back to [UploadState.running], and the final one). The
  /// stream closes after the final event; errors are not sent on it but in [result]. It can be listened to
  /// any number of times, and earlier events are not replayed.
  ///
  /// The stream can close before an event you wait for arrives: an upload can finish before a pause takes
  /// effect, and then no [UploadState.paused] event comes. `progress.firstWhere(...)` then throws a
  /// [StateError] ("No element"). Check what [pause] returns, or wait with an `orElse`:
  ///
  /// ```dart
  /// if (task.pause()) {
  ///   final UploadProgress paused = await task.progress.firstWhere(
  ///     (UploadProgress p) => p.state == UploadState.paused,
  ///     orElse: () => task.snapshot, // finished or failed meanwhile
  ///   );
  /// }
  /// ```
  Stream<UploadProgress> get progress => Stream<UploadProgress>.multi((
    MultiStreamController<UploadProgress> controller,
  ) {
    controller.add(snapshot);
    if (_events.isClosed) {
      controller.close();
      return;
    }
    final StreamSubscription<UploadProgress> subscription = _events.stream
        .listen(controller.add, onDone: controller.close);
    controller.onCancel = subscription.cancel;
  }, isBroadcast: true);

  /// Completes with the metadata of the new object, or fails with a `FirebaseStorageException` (`canceled`
  /// after [cancel]). An error of the data stream of `Reference.startStreamUpload` is passed on as it is.
  Future<FullMetadata> get result => _result.future;

  /// The URI of the resumable upload session, once the server has created it; null for a one-shot upload (up
  /// to 256 KiB) and before the session exists.
  ///
  /// Keep it to resume the upload after a restart: pass it as `existingSessionUri` to `Reference.startUpload`
  /// or `Reference.startStreamUpload` with the same data and reference. Anyone who has it can write to that
  /// session until it expires (a week on Google's servers), so store it like a credential.
  Uri? get sessionUri => _sessionUrl;

  /// Pauses a running task: the request in flight is aborted. Returns false when the task is not running,
  /// for example when it already finished, as `UploadTask.pause` of the JS SDK does. After true, the paused
  /// event follows on [progress] unless the task ends first (see [progress]).
  bool pause() {
    if (_phase != _Phase.running) {
      return false;
    }
    _phase = _Phase.pausing;
    _abortInFlight();
    return true;
  }

  /// Resumes a paused task; it first asks the server how much data it has. Returns false when the task is not
  /// paused (or pausing).
  bool resume() {
    switch (_phase) {
      case _Phase.paused:
        _phase = _Phase.running;
        _waitBeforeNextStep = false;
        _emit();
        unawaited(_run());
        return true;
      case _Phase.pausing:
        _phase = _Phase.running;
        return true;
      case _Phase.running ||
          _Phase.canceling ||
          _Phase.success ||
          _Phase.canceled ||
          _Phase.error:
        return false;
    }
  }

  /// Cancels a running or paused task: [result] fails with `canceled`. Returns false when the task already
  /// ended (or is being canceled).
  bool cancel() {
    switch (_phase) {
      case _Phase.running || _Phase.pausing:
        _phase = _Phase.canceling;
        _abortInFlight();
        return true;
      case _Phase.paused:
        _end(_Phase.canceled, canceled());
        return true;
      case _Phase.canceling ||
          _Phase.success ||
          _Phase.canceled ||
          _Phase.error:
        return false;
    }
  }

  Requester get _requester => ref.storage.requester;

  Future<void> _run() async {
    if (_looping) {
      return;
    }
    _looping = true;
    try {
      while (_phase == _Phase.running) {
        _abort = Completer<void>();
        try {
          await _step();
        } on Object catch (error, stackTrace) {
          _onStepError(error, stackTrace);
        }
      }
      switch (_phase) {
        case _Phase.pausing:
          _releaseSlot();
          _phase = _Phase.paused;
          _emit();
        case _Phase.canceling:
          _end(_Phase.canceled, canceled());
        case _Phase.running ||
            _Phase.paused ||
            _Phase.success ||
            _Phase.canceled ||
            _Phase.error:
          break;
      }
    } finally {
      _looping = false;
      _abort = null;
    }
  }

  Future<void> _step() {
    if (!_holdsSlot) {
      return _takeSlot();
    }
    final int? total = _total;
    if (_sessionUrl == null && total != null && total <= resumableChunkSize) {
      return _oneShot(total);
    }
    if (_sessionUrl == null) {
      return _createSession();
    }
    if (_waitBeforeNextStep) {
      return _wait();
    }
    if (_needStatus) {
      return _queryStatus();
    }
    if (_needMetadata) {
      return _fetchMetadata();
    }
    return _uploadChunk();
  }

  /// Waits for a slot of `FirebaseStorage.maxConcurrentUploads`; a pause or a cancel leaves the queue.
  Future<void> _takeSlot() async {
    final bool taken = await ref.storage.uploadSlots.acquire(
      abortTrigger: _abortTrigger,
    );
    if (!taken) {
      throw canceled();
    }
    _holdsSlot = true;
    _throwIfStopped();
  }

  void _releaseSlot() {
    if (_holdsSlot) {
      _holdsSlot = false;
      ref.storage.uploadSlots.release();
    }
  }

  /// Whether the rest of the data goes in one streamed request (see the class documentation).
  bool get _singleRequest =>
      streamsRequestBodies &&
      _source.openFrom != null &&
      ref.storage.maxUploadChunkSize == null;

  Future<void> _oneShot(int totalBytes) async {
    final Uint8List data = await _read(0, totalBytes);
    _throwIfStopped();
    final StorageRequest request = ref.multipartRequest(data, _metadata);
    final int bodyLength = request.body?.length ?? 0;
    final StorageResponse response = await _requester.send(
      request,
      abortTrigger: _abortTrigger,
      onBodyProgress: streamsRequestBodies && bodyLength > 0
          ? (int sent) {
              // The body holds the metadata part too: count the data in proportion.
              if (sent < bodyLength) {
                _reportSending(sent * totalBytes ~/ bodyLength);
              }
            }
          : null,
    );
    final FullMetadata metadata = ref.metadataOf(response);
    _setProgress(totalBytes);
    _succeed(metadata);
  }

  Future<void> _createSession() async {
    final Map<String, Object?> json = SettableMetadata.uploadJson(
      ref.fullPath,
      _metadata,
    );
    final StorageResponse response = await _requester.send(
      StorageRequest(
        method: 'POST',
        url: ref.uploadUrl,
        headers: <String, String>{
          'X-Goog-Upload-Protocol': 'resumable',
          'X-Goog-Upload-Command': 'start',
          // Optional in the protocol: a stream of unknown length starts without it.
          if (_total case final int total)
            'X-Goog-Upload-Header-Content-Length': '$total',
          'X-Goog-Upload-Header-Content-Type': '${json['contentType']}',
          'Content-Type': 'application/json; charset=utf-8',
        },
        body: utf8.encode(jsonEncode(json)),
        timeout: ref.storage.retry.upload,
        errorMapper: _errors,
      ),
      abortTrigger: _abortTrigger,
    );
    final Uri? url = Uri.tryParse(response.headers['x-goog-upload-url'] ?? '');
    if (_uploadStatus(response) != 'active' || url == null) {
      throw unknownResponse(
        'the upload session was not started.',
        httpStatus: response.statusCode,
      );
    }
    if (!_onStorageHost(url)) {
      throw unknownResponse(
        'the upload session is on another host than ${ref.storage.origin}.',
        httpStatus: response.statusCode,
      );
    }
    _sessionUrl = url;
  }

  Future<void> _wait() async {
    await _requester.wait(_retryWait, abortTrigger: _abortTrigger);
    _throwIfStopped();
    _waitBeforeNextStep = false;
  }

  Future<void> _queryStatus() async {
    final StorageResponse response = await _requester.send(
      StorageRequest(
        method: 'POST',
        url: _sessionUrl!,
        headers: const <String, String>{'X-Goog-Upload-Command': 'query'},
        timeout: ref.storage.retry.upload,
        errorMapper: _errors,
      ),
      abortTrigger: _abortTrigger,
    );
    final String? status = _uploadStatus(response);
    final String receivedHeader =
        response.headers['x-goog-upload-size-received'] ?? '';
    final int? received = RegExp(r'^[0-9]{1,15}$').hasMatch(receivedHeader)
        ? int.parse(receivedHeader)
        : null;
    if ((status != 'active' && status != 'final') || received == null) {
      throw unknownResponse(
        'the status of the upload session cannot be read.',
        httpStatus: response.statusCode,
      );
    }
    final int? total = _total;
    if (received < _confirmed ||
        (total != null && received > total) ||
        (total != null && status == 'final' && received != total)) {
      throw _wrongSize(received);
    }
    if (!_adoptedSession && received > _sent) {
      throw internalError(
        'the upload session has $received bytes, but only $_sent were sent.',
        httpStatus: response.statusCode,
      );
    }
    if (status == 'final') {
      // An adopted session of a stream of unknown length: the server's size is the size of the object.
      _total ??= received;
    }
    _adoptedSession = false;
    _sent = math.max(_sent, received);
    _setProgress(received);
    _needStatus = false;
    _needMetadata = status == 'final';
  }

  Future<void> _fetchMetadata() async {
    final StorageResponse response = await _requester.send(
      StorageRequest(
        method: 'GET',
        url: ref.objectUrl(),
        timeout: ref.storage.retry.operation,
        errorMapper: objectErrorMapper(ref.bucket, ref.fullPath),
      ),
      abortTrigger: _abortTrigger,
    );
    _succeed(_checkSize(ref.metadataOf(response)));
  }

  Future<void> _uploadChunk() async {
    final int offset = _confirmed;
    final int? knownTotal = _total;
    final bool single =
        _singleRequest && knownTotal != null && knownTotal > offset;
    final int wanted = knownTotal == null
        ? _chunkSize
        : math.min(knownTotal - offset, _chunkSize);
    final Uint8List? data = single ? null : await _read(offset, wanted);
    // A stream of unknown length knows its size once a read reached its end.
    final int? total = _total ??= _source.length;
    final int size = data?.length ?? knownTotal! - offset;
    if (data != null &&
        size != wanted &&
        !(size < wanted && total != null && offset + size == total)) {
      throw internalError(
        'the data source gave $size bytes at offset $offset instead of '
        '$wanted.',
      );
    }
    _throwIfStopped();
    _sourceFailure = null;
    final bool last = total != null && offset + size == total;
    final String command = switch (size) {
      0 when last => 'finalize',
      _ when last => 'upload, finalize',
      _ => 'upload',
    };
    _sent = math.max(_sent, offset + size);
    final StorageResponse response;
    try {
      response = await _requester.send(
        StorageRequest(
          method: 'POST',
          url: _sessionUrl!,
          headers: <String, String>{
            'X-Goog-Upload-Command': command,
            'X-Goog-Upload-Offset': '$offset',
          },
          body: data,
          // A single attempt: a request that fails is retried only after a query, here.
          timeout: Duration.zero,
          retryOnStatus: false,
          errorMapper: _errors,
        ),
        abortTrigger: _abortTrigger,
        streamedBody: single
            ? RequestBody(size, () => _openFrom(offset))
            : null,
        onBodyProgress: streamsRequestBodies && size > 0
            ? (int sent) {
                if (sent < size) {
                  _reportSending(offset + sent);
                }
              }
            : null,
      );
    } on Object catch (error) {
      // A failure of the data itself (a file that changed, a read error) is not a network error.
      final (Object, StackTrace)? source = _sourceFailure;
      if (source != null) {
        Error.throwWithStackTrace(source.$1, source.$2);
      }
      if (error is FirebaseStorageException &&
          (error.code == 'retry-limit-exceeded' ||
              isRetryStatus(error.httpStatus ?? 0))) {
        _scheduleRetry(error);
        return;
      }
      rethrow;
    }
    final String? status = _uploadStatus(response);
    if (status != 'active' && status != 'final') {
      throw unknownResponse(
        'the upload session answered a chunk without a status.',
        httpStatus: response.statusCode,
      );
    }
    _chunkSize = math.min(
      _chunkSize * 2,
      ref.storage.maxUploadChunkSize ?? maxChunkSize,
    );
    _retryWait = Duration.zero;
    _failingSince = null;
    _setProgress(offset + size);
    if (status == 'final') {
      if (!last) {
        throw _wrongSize(offset + size);
      }
      _succeed(_checkSize(ref.metadataOf(response)));
    }
  }

  /// The data from [offset] to the end, for one streamed request; it must end exactly at [totalBytes]. A
  /// failure of the source is kept in [_sourceFailure], so that it fails the task instead of being retried.
  Stream<List<int>> _openFrom(int offset) async* {
    final int expected = totalBytes - offset;
    int seen = 0;
    try {
      await for (final List<int> event in _source.openFrom!(offset)) {
        seen += event.length;
        if (seen > expected) {
          throw invalidArgument(
            'The data has more than its length of $totalBytes bytes.',
          );
        }
        yield event;
      }
      if (seen < expected) {
        throw invalidArgument(
          'The data ended after ${offset + seen} bytes, before its length of '
          '$totalBytes bytes.',
        );
      }
    } on Object catch (error, stackTrace) {
      _sourceFailure ??= (error, stackTrace);
      rethrow;
    }
  }

  /// Reads from the source, giving up (with `canceled`) when the task is paused or canceled meanwhile: a stream
  /// can stall.
  Future<Uint8List> _read(int offset, int size) {
    final Completer<Uint8List> result = Completer<Uint8List>();
    _source
        .read(offset, size)
        .then(
          (Uint8List data) {
            if (!result.isCompleted) {
              result.complete(data);
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!result.isCompleted) {
              result.completeError(error, stackTrace);
            }
          },
        );
    _abortTrigger?.then((_) {
      if (!result.isCompleted) {
        result.completeError(canceled());
      }
    });
    return result.future;
  }

  void _scheduleRetry(FirebaseStorageException error) {
    final DateTime now = _requester.now();
    final DateTime since = _failingSince ??= now;
    if (now.difference(since) >= ref.storage.retry.upload) {
      throw retryLimitExceeded(httpStatus: error.httpStatus, cause: error);
    }
    final Duration doubled = _retryWait * 2;
    _retryWait = doubled < const Duration(seconds: 1)
        ? const Duration(seconds: 1)
        : (doubled > _maxRetryWait ? _maxRetryWait : doubled);
    _chunkSize = resumableChunkSize;
    _rollBack();
    _waitBeforeNextStep = true;
    _needStatus = true;
  }

  void _onStepError(Object error, StackTrace stackTrace) {
    _chunkSize = resumableChunkSize;
    if (error is FirebaseStorageException && error.code == 'canceled') {
      // Our own abort (pause, cancel): where the server stopped is unknown.
      _needStatus = _sessionUrl != null;
      _rollBack();
      return;
    }
    _transferred = _confirmed;
    _end(_Phase.error, error, stackTrace);
  }

  void _throwIfStopped() {
    if (_phase != _Phase.running) {
      throw canceled();
    }
  }

  void _abortInFlight() {
    final Completer<void>? abort = _abort;
    if (abort != null && !abort.isCompleted) {
      abort.complete();
    }
  }

  Future<void>? get _abortTrigger => _abort?.future;

  StorageErrorMapper get _errors => sharedErrorMapper(ref.bucket, ref.fullPath);

  static String? _uploadStatus(StorageResponse response) =>
      response.headers['x-goog-upload-status'];

  FullMetadata _checkSize(FullMetadata metadata) {
    final int? size = metadata.size;
    final int? total = _total;
    if (size != null && total != null && size != total) {
      throw _wrongSize(size);
    }
    return metadata;
  }

  FirebaseStorageException _wrongSize(int serverSize) {
    final String has = _total == null
        ? '$serverSize bytes, before the end of the data'
        : '$serverSize of $_total bytes';
    return FirebaseStorageException(
      code: 'server-file-wrong-size',
      message:
          'Server recorded incorrect upload file size, please retry the '
          'upload. It has $has.',
    );
  }

  /// The server has [confirmed] bytes.
  void _setProgress(int confirmed) {
    _confirmed = confirmed;
    if (confirmed == _transferred) {
      return;
    }
    _transferred = confirmed;
    _emit();
  }

  /// [transferred] bytes have been handed to the client; an event at most every 64 KiB and 100 ms. Lower
  /// values (a body sent again after a 401) are ignored.
  void _reportSending(int transferred) {
    if (_phase != _Phase.running ||
        transferred - _transferred < bodySliceSize) {
      return;
    }
    final DateTime? last = _lastEventAt;
    if (last != null && _requester.now().difference(last) < _progressInterval) {
      return;
    }
    _transferred = transferred;
    _emit();
  }

  /// Back to the confirmed bytes after a failed or aborted request, with an event when that changes them.
  void _rollBack() => _setProgress(_confirmed);

  void _succeed(FullMetadata metadata) {
    _releaseSlot();
    _uploaded = metadata;
    _phase = _Phase.success;
    _emit();
    unawaited(_events.close());
    unawaited(_source.close());
    _result.complete(metadata);
  }

  void _end(_Phase phase, Object error, [StackTrace? stackTrace]) {
    if (phase == _Phase.canceled) {
      _cancelSession();
    }
    _releaseSlot();
    _phase = phase;
    _emit();
    unawaited(_events.close());
    unawaited(_source.close());
    _result.completeError(error, stackTrace);
  }

  void _emit() {
    _lastEventAt = _requester.now();
    _events.add(snapshot);
  }

  /// Tells the server to drop the session, without waiting and ignoring the outcome: the task is canceled
  /// either way, and the session expires by itself.
  void _cancelSession() {
    final Uri? url = _sessionUrl;
    if (url == null || _needMetadata || _requester.isClosed) {
      return;
    }
    _requester
        .send(
          StorageRequest(
            method: 'POST',
            url: url,
            headers: const <String, String>{'X-Goog-Upload-Command': 'cancel'},
            timeout: Duration.zero,
            retryOnStatus: false,
            errorMapper: _errors,
          ),
        )
        .ignore();
  }

  /// Whether [uri] has the scheme, host and port of the REST API of `ref.storage`, so that the data and the
  /// tokens go nowhere else.
  bool _onStorageHost(Uri uri) {
    final Uri origin = Uri.parse(ref.storage.origin);
    return uri.scheme == origin.scheme &&
        uri.host.toLowerCase() == origin.host.toLowerCase() &&
        uri.port == origin.port &&
        uri.userInfo.isEmpty &&
        uri.path.startsWith('/v0/b/');
  }
}
