/// The data of an `UploadTask`: bytes in memory, a seekable source such as a file, or a stream (of known or
/// unknown length) read one chunk at a time.
@internal
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../errors.dart';
import '../exception.dart';

/// The data of an upload, read by offset.
@internal
abstract interface class UploadSource {
  /// The data in [bytes].
  factory UploadSource.bytes(Uint8List bytes) = _BytesSource;

  /// The data of [stream], which must have exactly [length] bytes; with a null [length], all the bytes the
  /// stream produces.
  ///
  /// Only the chunk being sent is kept in memory (plus the rest of the last event of the stream), so a chunk
  /// can be sent again from any offset inside it, but not from an earlier one. Without a [length], a read also
  /// pulls the stream one event past the chunk, to tell whether the chunk is the last; [length] is null until
  /// the stream ended. The bytes of each event are copied once as they are read, so the producer may reuse
  /// its buffer for the next event.
  factory UploadSource.stream(Stream<List<int>> stream, int? length) =
      _StreamSource;

  /// [length] bytes that [openFrom] reads from any offset to the end, such as a file
  /// (`(int offset) => file.openRead(offset)`).
  factory UploadSource.seekable(
    int length,
    Stream<List<int>> Function(int offset) openFrom,
  ) = _SeekableSource;

  /// Opens the data from an offset to its end, for sources that can be read again from anywhere (bytes and
  /// files); null for a stream. The upload task checks that the stream ends exactly at [length].
  Stream<List<int>> Function(int offset)? get openFrom;

  /// The size of the data; null for a stream of unknown length until a read reached its end.
  int? get length;

  /// The [size] bytes at [offset]. Fewer only for a stream of unknown length that ended before
  /// [offset] + [size]; [length] is then set.
  Future<Uint8List> read(int offset, int size);

  /// Releases the data (cancels the stream).
  Future<void> close();
}

final class _BytesSource implements UploadSource {
  _BytesSource(this._bytes);

  final Uint8List _bytes;

  @override
  int get length => _bytes.length;

  @override
  Future<Uint8List> read(int offset, int size) async =>
      Uint8List.sublistView(_bytes, offset, offset + size);

  @override
  Stream<List<int>> Function(int offset) get openFrom =>
      (int offset) =>
          Stream<List<int>>.value(Uint8List.sublistView(_bytes, offset));

  @override
  Future<void> close() async {}
}

final class _SeekableSource implements UploadSource {
  _SeekableSource(this.length, this._open);

  @override
  final int length;

  final Stream<List<int>> Function(int offset) _open;

  @override
  Stream<List<int>> Function(int offset) get openFrom => _open;

  @override
  Future<Uint8List> read(int offset, int size) async {
    final BytesBuilder builder = BytesBuilder(copy: false);
    if (size > 0) {
      await for (final List<int> event in _open(offset)) {
        builder.add(event);
        if (builder.length >= size) {
          break;
        }
      }
    }
    if (builder.length < size) {
      throw invalidArgument(
        'The data ended after ${offset + builder.length} bytes, before its '
        'length of $length bytes.',
      );
    }
    return Uint8List.sublistView(builder.takeBytes(), 0, size);
  }

  @override
  Future<void> close() async {}
}

final class _StreamSource implements UploadSource {
  _StreamSource(Stream<List<int>> stream, this._declared)
    : _input = StreamIterator<List<int>>(stream);

  /// The length the caller gave, or null.
  final int? _declared;

  /// The length found at the end of a stream of unknown length.
  int? _found;

  @override
  int? get length => _declared ?? _found;

  @override
  Stream<List<int>> Function(int offset)? get openFrom => null;

  final StreamIterator<List<int>> _input;

  /// The bytes read from the stream that may be needed again (the chunk being sent, and what was read after
  /// it) are `_buffer[_head.._tail]`, the stream bytes from [_windowStart].
  ///
  /// Each event is copied into [_buffer] once as it is read: a producer may reuse its buffer for the next
  /// event. Bytes once handed out by [read] are never written again; the buffer only grows past [_tail], or
  /// is replaced by a new one that holds the live bytes.
  Uint8List _buffer = Uint8List(0);
  int _head = 0;
  int _tail = 0;
  int _windowStart = 0;

  bool _ended = false;

  /// The error of the stream, once it failed. Every later read throws it again: a read that the task stopped
  /// waiting for (a pause) can meet it, and the stream reports nothing after an error.
  (Object, StackTrace)? _failure;
  Future<void> _previousRead = Future<void>.value();

  int get _windowLength => _tail - _head;

  int get _windowEnd => _windowStart + _windowLength;

  /// Reads one after the other: a read that the task stopped waiting for still owns the stream until it ends.
  @override
  Future<Uint8List> read(int offset, int size) {
    final Future<Uint8List> read = _previousRead.then(
      (_) => _read(offset, size),
    );
    _previousRead = read.then((_) {}, onError: (Object _) {});
    return read;
  }

  Future<Uint8List> _read(int offset, int size) async {
    if (_failure case (final Object error, final StackTrace stackTrace)) {
      Error.throwWithStackTrace(error, stackTrace);
    }
    if (offset < _windowStart) {
      throw FirebaseStorageException(
        code: 'server-file-wrong-size',
        message:
            'Server recorded incorrect upload file size, please retry the '
            'upload. It asked for byte $offset of a stream that is past '
            '$_windowStart.',
      );
    }
    await _dropBefore(offset, offset + size);
    final bool full = await _fill(offset + size);
    final int? declared = _declared;
    if (declared != null) {
      if (!full) {
        throw _endedBefore(_windowEnd, declared);
      }
      if (_windowEnd > declared ||
          (offset + size == declared && await _fill(declared + 1))) {
        throw invalidArgument(
          'The data stream has more than its length of $declared bytes.',
        );
      }
    } else {
      if (full && _windowEnd == offset + size) {
        // Read ahead: whether this chunk is the last one decides its command.
        await _fill(_windowEnd + 1);
      }
      if (_ended) {
        _found = _windowEnd;
      }
    }
    return Uint8List.sublistView(
      _buffer,
      _head,
      _head + math.min(size, _windowLength),
    );
  }

  /// Forgets the bytes before [offset]. When a resumed session already has more than was read, the stream is
  /// skipped up to [offset] without copying: only the part of the event that crosses it is kept, in a buffer
  /// sized for a chunk that ends at [end].
  Future<void> _dropBefore(int offset, int end) async {
    if (offset <= _windowEnd) {
      _head += offset - _windowStart;
      _windowStart = offset;
      return;
    }
    int position = _windowEnd;
    _buffer = Uint8List(0);
    _head = 0;
    _tail = 0;
    while (true) {
      if (!await _next()) {
        throw _declared == null
            ? invalidArgument(
                'The data stream ended after $position bytes, before the '
                '$offset bytes that the upload session already has.',
              )
            : _endedBefore(position, _declared);
      }
      final List<int> event = _input.current;
      if (position + event.length > offset) {
        _windowStart = offset;
        _append(event, end, from: offset - position);
        return;
      }
      position += event.length;
    }
  }

  /// Reads the stream until the window reaches [end]; false when the stream ended before.
  Future<bool> _fill(int end) async {
    while (_windowEnd < end && !_ended) {
      if (await _next()) {
        _append(_input.current, end);
      }
    }
    return _windowEnd >= end;
  }

  /// The next event of the stream; false at its end. An error of the stream is kept in [_failure].
  Future<bool> _next() async {
    try {
      if (await _input.moveNext()) {
        return true;
      }
    } on Object catch (error, stackTrace) {
      _failure = (error, stackTrace);
      _ended = true;
      rethrow;
    }
    _ended = true;
    return false;
  }

  /// Copies [event] from [from] after the window. When the buffer has no room, the live bytes move to a new
  /// buffer sized for the window up to [end], plus room for one more event like this one (at least 64 KiB, at
  /// most the size of the chunk), so that the next fills of this chunk copy nothing again.
  void _append(List<int> event, int end, {int from = 0}) {
    final int length = event.length - from;
    if (length <= 0) {
      return;
    }
    if (_tail + length > _buffer.length) {
      final int live = _windowLength;
      final int chunk = end - _windowStart;
      final int slack = math.max(64 * 1024, math.min(length, chunk));
      final int capacity = math.max(chunk + slack, live + length);
      _buffer = Uint8List(capacity)..setRange(0, live, _buffer, _head);
      _head = 0;
      _tail = live;
    }
    _buffer.setRange(_tail, _tail + length, event, from);
    _tail += length;
  }

  static FirebaseStorageException _endedBefore(int position, int length) =>
      invalidArgument(
        'The data stream ended after $position bytes, before its length of '
        '$length bytes.',
      );

  @override
  Future<void> close() async {
    if (!_ended) {
      _ended = true;
      await _input.cancel();
    }
  }
}
