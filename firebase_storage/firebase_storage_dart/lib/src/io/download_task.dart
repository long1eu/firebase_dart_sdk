/// A download into a file that can be paused, resumed and canceled, and resumes after a failure.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_storage_dart/src/download.dart';
import 'package:firebase_storage_dart/src/errors.dart';
import 'package:firebase_storage_dart/src/exception.dart';
import 'package:firebase_storage_dart/src/metadata.dart';
import 'package:firebase_storage_dart/src/reference.dart';
import 'package:firebase_storage_dart/src/request/requester.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

/// The state of a [DownloadTask].
enum DownloadState {
  /// Reading the metadata or the content, or waiting before it retries.
  running,

  /// Paused by [DownloadTask.pause]; [DownloadTask.resume] goes on from the bytes already written.
  paused,

  /// Done: the file holds the object, [DownloadTask.result] has its metadata.
  success,

  /// Stopped by [DownloadTask.cancel]; [DownloadTask.result] failed with `canceled`.
  canceled,

  /// Failed; [DownloadTask.result] holds the error.
  error,
}

/// A snapshot of a [DownloadTask], as emitted by [DownloadTask.progress].
@immutable
final class DownloadProgress {
  /// Creates a snapshot. The package creates them; you need this only in tests.
  const DownloadProgress({
    required this.state,
    required this.bytesTransferred,
    required this.totalBytes,
  });

  /// The state of the task.
  final DownloadState state;

  /// The bytes written to the file so far.
  final int bytesTransferred;

  /// The size of the object; 0 until its metadata is read.
  final int totalBytes;

  @override
  bool operator ==(Object other) =>
      other is DownloadProgress &&
      other.state == state &&
      other.bytesTransferred == bytesTransferred &&
      other.totalBytes == totalBytes;

  @override
  int get hashCode => Object.hash(state, bytesTransferred, totalBytes);

  @override
  String toString() =>
      'DownloadProgress(${state.name}, $bytesTransferred/$totalBytes bytes)';
}

/// The shortest time between two progress events while a body is being read.
const Duration _progressInterval = Duration(milliseconds: 100);

/// The longest wait between two attempts after the body broke.
const Duration _maxRetryWait = Duration(seconds: 64);

/// The response header with the generation of the object whose bytes a media response carries.
const String _generationHeader = 'x-goog-generation';

final math.Random _random = math.Random.secure();

enum _Phase { running, pausing, paused, canceling, success, canceled, error }

/// The end of reading one response body.
enum _BodyEnd { complete, stopped, broken }

/// A download of an object into a file that can be paused, resumed and canceled, and reports its progress. It
/// starts when it is created (by `startDownloadToFile` of `package:firebase_storage_dart/io.dart`); await
/// [result] for the metadata of the object.
///
/// The task reads the metadata of the object first (its size and generation), then writes the content to a
/// new file next to the target (`<file>.<random>.part`, created exclusively), and renames it over the target
/// once it holds exactly the size of the metadata. When the task fails or is canceled, the partial file is
/// deleted and the target is left untouched. The partial file is opened by its path right after the exclusive
/// create, so someone who can write to the directory could swap it in between; keep downloads in a directory
/// that only your program writes to.
///
/// Requests ask for `Accept-Encoding: identity`, so offsets count stored bytes. An object stored with
/// `Content-Encoding: gzip` arrives unzipped by the server, which ignores ranges for it: the task asks for the
/// whole object again after a pause or a failure and skips the bytes it has, and does not compare the length
/// with the stored size.
///
/// [pause] closes the connection, since a server times out a response that is held open. [resume] asks for
/// the rest with `Range: bytes=<written>-`. When the body breaks on the network (a closed connection, the idle
/// timeout of `FirebaseStorage.requestTimeout`), the task waits (1 s, doubling up to 64 s) and asks for the
/// rest the same way; it gives up with `retry-limit-exceeded` once the failures have lasted the `download` time
/// of the `StorageRetryPolicy`. A response that brought bytes resets both the wait and that time.
///
/// Each response is checked against the generation of the metadata (its `x-goog-generation` header), so the
/// file is never joined from two versions of the object: an object overwritten during the download fails the
/// task with `object-changed`. A server that does not send the header gets a metadata read before each
/// resumed request and once more before the rename. A server that answers a ranged request with the whole
/// object (status 200, as the emulator does for ranges it cannot satisfy) is read past the bytes already
/// written; a partial answer (206) that does not start at the offset asked for fails the task with `unknown`.
///
/// ```dart
/// final DownloadTask task = storage.ref('videos/clip.mp4').startDownloadToFile(File('clip.mp4'));
/// task.progress.listen((DownloadProgress p) {
///   print('${p.state.name}: ${p.bytesTransferred} of ${p.totalBytes} bytes');
/// });
/// final FullMetadata metadata = await task.result;
/// ```
final class DownloadTask {
  /// Starts a download of [ref] into [file]. Use `startDownloadToFile` of `package:firebase_storage_dart/io.dart`
  /// instead.
  @internal
  DownloadTask.start(this.ref, this.file) {
    _lastEventAt = _requester.now();
    _result.future.ignore();
    unawaited(_run());
  }

  /// The reference of the object being downloaded.
  final Reference ref;

  /// The file the object goes to.
  final File file;

  final Completer<FullMetadata> _result = Completer<FullMetadata>();
  final StreamController<DownloadProgress> _events =
      StreamController<DownloadProgress>.broadcast();

  _Phase _phase = _Phase.running;
  bool _looping = false;
  Completer<void>? _abort;

  FullMetadata? _metadata;

  /// Whether the object is stored with `Content-Encoding: gzip`, which the server unzips (transcodes) for a
  /// request that accepts only `identity`.
  bool _transcoded = false;
  String _generation = '';
  int _total = 0;
  File? _part;
  RandomAccessFile? _output;
  int _written = 0;
  int _reported = 0;
  DateTime? _lastEventAt;

  /// Whether bytes were written from a response that did not name its generation, since the generation was
  /// last confirmed.
  bool _unverified = false;
  bool _bodyComplete = false;
  Duration _retryWait = Duration.zero;
  bool _waitBeforeNextStep = false;
  DateTime? _failingSince;

  /// The state of the task.
  DownloadState get state => switch (_phase) {
    _Phase.running ||
    _Phase.pausing ||
    _Phase.canceling => DownloadState.running,
    _Phase.paused => DownloadState.paused,
    _Phase.success => DownloadState.success,
    _Phase.canceled => DownloadState.canceled,
    _Phase.error => DownloadState.error,
  };

  /// The bytes written to the partial file so far; they stay there across pauses and failures.
  int get bytesTransferred => _written;

  /// The size of the object from its metadata; 0 until the metadata is read. When the server sends more than
  /// that (an object stored with `Content-Encoding: gzip` arrives decompressed), it follows the bytes written.
  int get totalBytes => _total;

  /// The current state as a [DownloadProgress].
  DownloadProgress get snapshot => DownloadProgress(
    state: state,
    bytesTransferred: _written,
    totalBytes: _total,
  );

  /// The progress of the download: the current [snapshot] when you listen, then events while bytes are written
  /// (at most one per 64 KiB and 100 ms), when the metadata gives the size, and on each change of state
  /// ([DownloadState.paused], back to [DownloadState.running], and the final one). The stream closes after the
  /// final event; errors are not sent on it but in [result]. It can be listened to any number of times, and
  /// earlier events are not replayed.
  ///
  /// As with `UploadTask.progress`, the download can finish before a pause takes effect; check what [pause]
  /// returns, or wait for an event with an `orElse`.
  Stream<DownloadProgress> get progress => Stream<DownloadProgress>.multi((
    MultiStreamController<DownloadProgress> controller,
  ) {
    controller.add(snapshot);
    if (_events.isClosed) {
      controller.close();
      return;
    }
    final StreamSubscription<DownloadProgress> subscription = _events.stream
        .listen(controller.add, onDone: controller.close);
    controller.onCancel = subscription.cancel;
  }, isBroadcast: true);

  /// Completes with the metadata of the object once the file is in place, or fails: with a
  /// `FirebaseStorageException` (`canceled` after [cancel], `object-changed` when the object was overwritten
  /// during the download), or with a [FileSystemException] when the file cannot be written.
  Future<FullMetadata> get result => _result.future;

  /// Pauses a running task: the connection is closed, the bytes written so far stay. Returns false when the
  /// task is not running. After true, the paused event follows on [progress] unless the task ends first.
  bool pause() {
    if (_phase != _Phase.running) {
      return false;
    }
    _phase = _Phase.pausing;
    _abortInFlight();
    return true;
  }

  /// Resumes a paused task from the bytes already written. Returns false when the task is not paused (or
  /// pausing).
  bool resume() {
    switch (_phase) {
      case _Phase.paused:
        _phase = _Phase.running;
        _waitBeforeNextStep = false;
        // Time spent paused is not time spent failing.
        _failingSince = null;
        _retryWait = Duration.zero;
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

  /// Cancels a running or paused task: the partial file is deleted and [result] fails with `canceled`. Returns
  /// false when the task already ended (or is being canceled).
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
    if (_metadata == null) {
      return _readMetadata();
    }
    if (_part == null) {
      return _openPart();
    }
    if (_waitBeforeNextStep) {
      return _wait();
    }
    // Before a resumed request and before the rename, unless a response header confirmed the generation.
    if (_unverified && (_written > 0 || _bodyComplete)) {
      return _checkGeneration();
    }
    if (_bodyComplete) {
      return _finish();
    }
    return _receive();
  }

  Future<FullMetadata> _fetchMetadata() async {
    final StorageResponse response = await _requester.send(
      StorageRequest(
        method: 'GET',
        url: ref.objectUrl(),
        timeout: ref.storage.retry.operation,
        errorMapper: objectErrorMapper(ref.bucket, ref.fullPath),
      ),
      abortTrigger: _abortTrigger,
    );
    return ref.metadataOf(response);
  }

  Future<void> _readMetadata() async {
    final FullMetadata metadata = await _fetchMetadata();
    final int? size = metadata.size;
    final String? generation = metadata.generation;
    if (size == null || generation == null) {
      throw unknownResponse(
        'the metadata of the object has no size or generation.',
      );
    }
    _metadata = metadata;
    _generation = generation;
    _transcoded = metadata.contentEncoding?.trim().toLowerCase() == 'gzip';
    if (size != _total) {
      _total = size;
      _emit();
    }
  }

  /// Creates the partial file. Its name cannot be guessed and it is created exclusively, so a file or link
  /// planted at that path fails the download instead of receiving its bytes.
  Future<void> _openPart() async {
    final File part = await File(
      '${file.path}.${_hex(8)}.part',
    ).create(exclusive: true);
    _part = part;
    _output = await part.open(mode: FileMode.writeOnly);
    _throwIfStopped();
  }

  Future<void> _wait() async {
    await _requester.wait(_retryWait, abortTrigger: _abortTrigger);
    _throwIfStopped();
    _waitBeforeNextStep = false;
  }

  /// Reads the metadata again and fails with `object-changed` when the generation is not the one the download
  /// started with. Two reads with the same generation prove that every response between them came from that
  /// generation, since a generation never comes back.
  Future<void> _checkGeneration() async {
    final FullMetadata metadata = await _fetchMetadata();
    _checkSameGeneration(metadata.generation ?? '');
    _unverified = false;
  }

  void _checkSameGeneration(String actual) {
    if (actual != _generation) {
      throw objectChanged(
        ref.fullPath,
        'generation $_generation, now ${actual.isEmpty ? 'none' : actual}',
      );
    }
  }

  /// Requests the content from the bytes already written and writes the body to the partial file.
  Future<void> _receive() async {
    final int offset = _written;
    // The server unzips a gzip-stored object itself and ignores a Range for it: ask for all of it and skip.
    final int start = _transcoded ? 0 : offset;
    final http.StreamedResponse response = await _requester.open(
      mediaRequest(ref, start, null),
      abortTrigger: _abortTrigger,
    );
    if (response.statusCode == 416) {
      // Nothing at or after the offset. Complete when the object has no more bytes than that.
      _discard(response);
      if (offset < _sizeOf(_metadata!)) {
        throw objectChanged(
          ref.fullPath,
          'it now ends at or before byte $offset of its ${_sizeOf(_metadata!)}',
        );
      }
      _bodyComplete = true;
      return;
    }
    _checkResponse(response, offset);
    final int skip = rangeSkip(response.statusCode, start) + offset - start;
    final (_BodyEnd end, Object? failure) = await _writeBody(response, skip);
    switch (end) {
      case _BodyEnd.complete:
        _bodyComplete = true;
      case _BodyEnd.stopped:
        throw canceled();
      case _BodyEnd.broken:
        _onBodyBroken(failure!, progressed: _written > offset);
    }
  }

  /// Checks that [response] comes from the generation the download started with and, for a 206, that it starts
  /// at [offset]; a part from elsewhere in the object is never appended.
  void _checkResponse(http.StreamedResponse response, int offset) {
    final String? generation = response.headers[_generationHeader];
    if (generation != null) {
      if (generation != _generation) {
        _discard(response);
        _checkSameGeneration(generation);
      }
      _unverified = false;
    } else {
      _unverified = true;
    }
    if (response.statusCode != 206) {
      return;
    }
    final String range = response.headers['content-range'] ?? '';
    final Match? match = RegExp(r'^bytes ([0-9]{1,15})-').firstMatch(range);
    final int? from = match == null ? null : int.parse(match[1]!);
    if (from != offset) {
      _discard(response);
      throw unknownResponse(
        'the partial content for byte $offset starts at '
        '${from == null ? 'an unknown byte' : 'byte $from'} '
        "(Content-Range: '$range').",
        httpStatus: 206,
      );
    }
  }

  /// Writes the body of [response] to the partial file, dropping its first [skip] bytes. The body is pulled
  /// only as fast as the file takes it, and dropped at once when the task is paused or canceled.
  Future<(_BodyEnd, Object?)> _writeBody(
    http.StreamedResponse response,
    int skip,
  ) async {
    final StreamIterator<List<int>> body = StreamIterator<List<int>>(
      response.stream.timeout(_requester.requestTimeout),
    );
    bool stopped = false;
    final Future<void>? abortTrigger = _abortTrigger;
    if (abortTrigger != null) {
      unawaited(
        abortTrigger.then((_) {
          stopped = true;
          body.cancel().ignore();
        }),
      );
    }
    int toSkip = skip;
    try {
      while (true) {
        final bool more;
        try {
          more = await body.moveNext();
        } on Object catch (error) {
          // A RequestAbortedException comes only from our own abort.
          if (stopped || error is http.RequestAbortedException) {
            return (_BodyEnd.stopped, null);
          }
          return (_BodyEnd.broken, error);
        }
        if (stopped) {
          return (_BodyEnd.stopped, null);
        }
        if (!more) {
          return (_BodyEnd.complete, null);
        }
        List<int> data = body.current;
        if (toSkip > 0) {
          final int dropped = math.min(toSkip, data.length);
          toSkip -= dropped;
          data = data.sublist(dropped);
        }
        if (data.isNotEmpty) {
          await _output!.writeFrom(data);
          _onWritten(data.length);
        }
      }
    } finally {
      body.cancel().ignore();
    }
  }

  /// A body that broke on the network is asked for again from the bytes written, after a wait; anything else
  /// fails the task.
  void _onBodyBroken(Object error, {required bool progressed}) {
    if (!isTransientBodyError(error)) {
      if (error is FirebaseStorageException) {
        throw error;
      }
      throw FirebaseStorageException(
        code: 'unknown',
        message:
            "The download of '${ref.fullPath}' stopped after $_written bytes: "
            '${error.runtimeType}.',
        cause: error,
      );
    }
    if (progressed) {
      _failingSince = null;
      _retryWait = Duration.zero;
    }
    final DateTime now = _requester.now();
    final DateTime since = _failingSince ??= now;
    if (now.difference(since) >= ref.storage.retry.download) {
      throw retryLimitExceeded(cause: _describe(error));
    }
    final Duration doubled = _retryWait * 2;
    _retryWait = doubled < const Duration(seconds: 1)
        ? const Duration(seconds: 1)
        : (doubled > _maxRetryWait ? _maxRetryWait : doubled);
    _waitBeforeNextStep = true;
  }

  Future<void> _finish() async {
    await _closeOutput();
    if (_phase == _Phase.canceling) {
      // cancel() returned true: the target must not be replaced.
      throw canceled();
    }
    final FullMetadata metadata = _metadata!;
    final int size = _sizeOf(metadata);
    // A gzip-stored object arrives unzipped, with another length than the size it is stored with.
    if (!_transcoded && _written != size) {
      throw unknownResponse(
        "the download of '${ref.fullPath}' ended after $_written of its $size bytes.",
      );
    }
    await _part!.rename(file.path);
    _phase = _Phase.success;
    _emit();
    unawaited(_events.close());
    _result.complete(metadata);
  }

  void _onStepError(Object error, StackTrace stackTrace) {
    if (error is FirebaseStorageException && error.code == 'canceled') {
      // Our own abort (pause, cancel): the loop decides what comes next.
      return;
    }
    if (_phase == _Phase.canceling) {
      return;
    }
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

  /// [count] more bytes are in the partial file; an event at most every 64 KiB and 100 ms.
  void _onWritten(int count) {
    _written += count;
    if (_written > _total) {
      _total = _written;
    }
    if (_written - _reported < bodySliceSize) {
      return;
    }
    final DateTime? last = _lastEventAt;
    if (last != null && _requester.now().difference(last) < _progressInterval) {
      return;
    }
    _emit();
  }

  void _emit() {
    _lastEventAt = _requester.now();
    _reported = _written;
    _events.add(snapshot);
  }

  /// Ends the task with [error]: the final event goes out at once, [result] fails once the partial file is
  /// deleted.
  void _end(_Phase phase, Object error, [StackTrace? stackTrace]) {
    _phase = phase;
    _emit();
    unawaited(_events.close());
    unawaited(
      _deletePart().whenComplete(
        () => _result.completeError(error, stackTrace),
      ),
    );
  }

  Future<void> _closeOutput() async {
    final RandomAccessFile? output = _output;
    _output = null;
    await output?.close();
  }

  Future<void> _deletePart() async {
    try {
      await _closeOutput();
    } on FileSystemException {
      // The error that ends the task is the one that matters.
    }
    final File? part = _part;
    if (part == null) {
      return;
    }
    try {
      await part.delete();
    } on FileSystemException {
      // Already gone.
    }
  }

  /// The size in [metadata], checked when it was read.
  static int _sizeOf(FullMetadata metadata) => metadata.size!;

  static void _discard(http.StreamedResponse response) {
    response.stream.listen(null, onError: (Object _) {}).cancel().ignore();
  }

  /// [error] for a message: its type and message, never a URL (the query can hold a download token).
  static String _describe(Object error) => switch (error) {
    http.ClientException(:final String message) =>
      '${error.runtimeType}: $message',
    _ => '${error.runtimeType}',
  };

  static String _hex(int bytes) => <String>[
    for (int i = 0; i < bytes; i++)
      _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();
}
