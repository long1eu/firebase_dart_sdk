/// The data of an `UploadTask`: bytes in memory, a seekable source such as a file, or a stream of known
/// length read one chunk at a time.
@internal
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../errors.dart';
import '../exception.dart';

/// The data of an upload, read by offset.
@internal
abstract interface class UploadSource {
  /// The data in [bytes].
  factory UploadSource.bytes(Uint8List bytes) = _BytesSource;

  /// The data of [stream], which must have exactly [length] bytes.
  ///
  /// Only the chunk being sent is kept in memory (plus the rest of the last event of the stream), so a chunk
  /// can be sent again from any offset inside it, but not from an earlier one.
  factory UploadSource.stream(Stream<List<int>> stream, int length) =
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

  /// The size of the data.
  int get length;

  /// The [size] bytes at [offset].
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
  _StreamSource(Stream<List<int>> stream, this.length)
    : _input = StreamIterator<List<int>>(stream);

  @override
  final int length;

  @override
  Stream<List<int>> Function(int offset)? get openFrom => null;

  final StreamIterator<List<int>> _input;

  /// The bytes from [_bufferStart] that were read from the stream and may be needed again.
  Uint8List _buffer = Uint8List(0);
  int _bufferStart = 0;
  bool _ended = false;
  Future<void> _previousRead = Future<void>.value();

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
    if (offset < _bufferStart) {
      throw FirebaseStorageException(
        code: 'server-file-wrong-size',
        message:
            'Server recorded incorrect upload file size, please retry the '
            'upload. It asked for byte $offset of a stream that is past '
            '$_bufferStart.',
      );
    }
    final BytesBuilder builder = BytesBuilder(copy: false)
      ..add(await _skipTo(offset));
    while (builder.length < size) {
      if (!await _input.moveNext()) {
        _ended = true;
        throw _endedAt(offset + builder.length);
      }
      builder.add(_input.current);
    }
    _buffer = builder.takeBytes();
    _bufferStart = offset;
    if (_bufferStart + _buffer.length > length ||
        (offset + size == length && await _hasMore())) {
      throw invalidArgument(
        'The data stream has more than its length of $length bytes.',
      );
    }
    return Uint8List.sublistView(_buffer, 0, size);
  }

  /// The bytes from [offset] that were already read: from the buffer, or after skipping the stream to
  /// [offset] (when a resumed session already has the bytes before it).
  Future<Uint8List> _skipTo(int offset) async {
    int position = _bufferStart + _buffer.length;
    if (offset <= position) {
      return Uint8List.sublistView(_buffer, offset - _bufferStart);
    }
    _buffer = Uint8List(0);
    Uint8List kept = Uint8List(0);
    while (position < offset) {
      if (!await _input.moveNext()) {
        _ended = true;
        throw _endedAt(position);
      }
      final List<int> event = _input.current;
      if (position + event.length > offset) {
        kept = Uint8List.fromList(event.sublist(offset - position));
      }
      position += event.length;
    }
    return kept;
  }

  FirebaseStorageException _endedAt(int position) => invalidArgument(
    'The data stream ended after $position bytes, before its length of '
    '$length bytes.',
  );

  Future<bool> _hasMore() async {
    while (!_ended && await _input.moveNext()) {
      if (_input.current.isNotEmpty) {
        return true;
      }
    }
    _ended = true;
    return false;
  }

  @override
  Future<void> close() async {
    if (!_ended) {
      _ended = true;
      await _input.cancel();
    }
  }
}
