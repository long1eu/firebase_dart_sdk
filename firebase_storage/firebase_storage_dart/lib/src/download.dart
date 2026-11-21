/// Streamed downloads (`Reference.openRead`), after `getStreamInternal` of the JS SDK.
@internal
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import 'errors.dart';
import 'exception.dart';
import 'media_headers_stub.dart' if (dart.library.io) 'media_headers_io.dart';
import 'reference.dart';
import 'request/requester.dart';

/// The content of [ref] from byte [start] (inclusive, default 0) to byte [end] (exclusive, default the end of
/// the object), as a single-subscription stream. See `Reference.openRead`.
@internal
Stream<List<int>> openReadStream(Reference ref, int? start, int? end) {
  return _Download(ref, start ?? 0, end).stream;
}

/// The GET of the content of [ref] from byte [start] (inclusive) to byte [end] (exclusive, null for the end of
/// the object), with a `Range` header unless it is the whole object. A ranged request also accepts 206 and
/// 416 (the range starts at or after the end of the object); see [rangeSkip]. On the VM it asks for the
/// identity encoding (see `media_headers_io.dart`).
@internal
StorageRequest mediaRequest(Reference ref, int start, int? end) {
  final bool ranged = start > 0 || end != null;
  final String last = end == null ? '' : '${end - 1}';
  return StorageRequest(
    method: 'GET',
    url: ref.objectUrl(media: true),
    headers: <String, String>{
      ...mediaRequestHeaders,
      if (ranged) 'Range': 'bytes=$start-$last',
    },
    successCodes: ranged ? const <int>{200, 206, 416} : const <int>{200},
    timeout: ref.storage.retry.download,
    errorMapper: objectErrorMapper(ref.bucket, ref.fullPath),
  );
}

/// How many bytes to drop from the body of a response with [status] to a [mediaRequest] that started at
/// [start]: [start] for a 200 (the whole object: the emulator ignores ranges it cannot satisfy), 0 for a 206,
/// and -1 for a 416, which has no content to read.
@internal
int rangeSkip(int status, int start) => switch (status) {
  200 => start,
  416 => -1,
  _ => 0,
};

/// Whether a response body that failed with [error] broke on the network (a closed connection, the idle
/// timeout), so that requesting the rest again can succeed.
@internal
bool isTransientBodyError(Object error) =>
    error is http.ClientException || error is TimeoutException;

/// One download: the request starts when the stream is listened to.
///
/// Failures before the first byte reaches the listener (the request, or the body breaking before it delivered
/// anything) are retried with the backoff of the request layer until the download retry time runs out. Once
/// bytes were delivered a failure ends the stream with an error, since retrying would repeat bytes.
final class _Download {
  _Download(this._ref, this._start, this._end) {
    _controller = StreamController<List<int>>(
      onListen: _run,
      onPause: () => _body?.pause(),
      onResume: () => _body?.resume(),
      onCancel: _cancel,
    );
  }

  final Reference _ref;
  final int _start;

  final int? _end;

  /// How many bytes the caller asked for; null up to the end of the object.
  int? get _wanted {
    final int? end = _end;
    return end == null ? null : end - _start;
  }

  late final StreamController<List<int>> _controller;
  final Completer<void> _abort = Completer<void>();
  StreamSubscription<List<int>>? _body;
  int _delivered = 0;
  bool _canceled = false;

  Stream<List<int>> get stream => _controller.stream;

  Requester get _requester => _ref.storage.requester;

  Future<void> _run() async {
    try {
      await _download();
    } on Object catch (error, stackTrace) {
      if (!_canceled) {
        _controller.addError(error, stackTrace);
      }
    }
    if (!_canceled) {
      await _controller.close();
    }
  }

  Future<void> _download() async {
    _ref.throwIfRoot('openRead');
    if (_start < 0) {
      throw invalidArgument(
        "Invalid value for 'start'. Expected 0 or greater.",
      );
    }
    final int? end = _end;
    if (end != null && end < _start) {
      throw invalidArgument(
        "Invalid value for 'end'. Expected 'start' ($_start) or greater.",
      );
    }
    if (_wanted == 0) {
      return;
    }
    final DateTime deadline = _requester.now().add(_ref.storage.retry.download);
    int waitSeconds = 1;
    while (!_canceled) {
      final http.StreamedResponse response = await _requester.open(
        mediaRequest(_ref, _start, _end),
        abortTrigger: _abort.future,
      );
      final Object? failure = await _pipe(response);
      if (failure == null) {
        return;
      }
      final DateTime now = _requester.now();
      if (!now.isBefore(deadline)) {
        throw retryLimitExceeded(cause: failure);
      }
      if (waitSeconds < 64) {
        waitSeconds *= 2;
      }
      Duration wait = Duration(
        milliseconds: ((waitSeconds + _requester.random()) * 1000).round(),
      );
      final Duration remaining = deadline.difference(now);
      if (wait > remaining) {
        wait = remaining;
      }
      await _requester.wait(wait, abortTrigger: _abort.future);
    }
  }

  /// Forwards the body of [response] to the listener. Returns null when the download is over (complete,
  /// failed after delivering bytes, or canceled) and the error when the body broke before its first byte was
  /// delivered, which is retried.
  Future<Object?> _pipe(http.StreamedResponse response) {
    final Completer<Object?> outcome = Completer<Object?>();
    int skip = rangeSkip(response.statusCode, _start);
    final StreamSubscription<List<int>> body = response.stream
        .timeout(_requester.requestTimeout)
        .listen(null);
    _body = body;
    if (_controller.isPaused) {
      body.pause();
    }

    void finish(Object? result) {
      _body = null;
      if (!outcome.isCompleted) {
        outcome.complete(result);
      }
    }

    if (skip < 0) {
      body.cancel().ignore();
      finish(null);
      return outcome.future;
    }

    body
      ..onData((List<int> chunk) {
        List<int> data = chunk;
        if (skip > 0) {
          final int dropped = skip < data.length ? skip : data.length;
          skip -= dropped;
          data = Uint8List.sublistView(_bytes(data), dropped);
        }
        final int? wanted = _wanted;
        final bool last = wanted != null && _delivered + data.length >= wanted;
        if (last) {
          data = Uint8List.sublistView(_bytes(data), 0, wanted - _delivered);
        }
        if (data.isNotEmpty) {
          _delivered += data.length;
          _controller.add(data);
        }
        if (last) {
          body.cancel().ignore();
          _stopRequest();
          finish(null);
        }
      })
      ..onError((Object error, StackTrace stackTrace) {
        body.cancel().ignore();
        if (_canceled) {
          finish(null);
        } else if (_delivered == 0 && isTransientBodyError(error)) {
          finish(error);
        } else {
          _controller.addError(_interrupted(error), stackTrace);
          finish(null);
        }
      })
      ..onDone(() => finish(null));
    return outcome.future;
  }

  /// Aborts the HTTP request of a download that has all its bytes, so the connection is not read to its end.
  void _stopRequest() {
    if (!_abort.isCompleted) {
      _abort.complete();
    }
  }

  Future<void> _cancel() async {
    _canceled = true;
    _stopRequest();
    final StreamSubscription<List<int>>? body = _body;
    _body = null;
    await body?.cancel();
  }

  Object _interrupted(Object error) {
    if (error is FirebaseStorageException) {
      return error;
    }
    return FirebaseStorageException(
      code: 'unknown',
      message:
          "The download of '${_ref.fullPath}' stopped after $_delivered "
          'bytes: $error',
    );
  }

  static Uint8List _bytes(List<int> data) =>
      data is Uint8List ? data : Uint8List.fromList(data);
}
