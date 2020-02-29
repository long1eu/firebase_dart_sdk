/*
// File created by
// Lung Razvan <long1eu>
// on 20/10/2018

import 'dart:math';
import 'dart:typed_data';

import 'package:firebase_common/firebase_common.dart';

/// AdaptiveStreamBuffer is a wrapper around ByteBuffer that reads all data into a local buffer. It
/// provides access to the underlying buffer and methods to manipulate its state.
class AdaptiveStreamBuffer {
  static const String _tag = 'AdaptiveStreamBuffer';

  final ByteBuffer _source;
  final GetMemoryInfo memoryInfo;

  Uint8List buffer;

  /// Returns the number of available bytes in the buffer.
  int availableBytes = 0;

  bool _reachedEnd = false;
  bool _adaptiveMode = true;

  AdaptiveStreamBuffer(this._source, int initialBufferSize, this.memoryInfo)
      : buffer = Uint8List(initialBufferSize);

  /// Moves the buffer forward by 'bytes' and disregards its data. [bytes] is
  /// the number of bytes to advance.
  /// Returns the number of bytes we were able to advance.
  int advance(int bytes) {
    int bytesAdvanced;

    if (bytes <= availableBytes) {
      availableBytes -= bytes;
      buffer = _source.asUint8List(bytes, availableBytes);
      bytesAdvanced = bytes;
    } else {
      // We disregard all bytes in the buffer before advancing the underlying
      // stream.
      availableBytes = 0;
      bytesAdvanced = availableBytes;

      _source.lengthInBytes;

      while (bytesAdvanced < bytes) {
        final int currentSkip = _source.skip(bytes - bytesAdvanced);

        if (currentSkip > 0) {
          bytesAdvanced += currentSkip;
        } else if (currentSkip == 0) {
          // skip() can return 0 when it has no more data cached locally, even
          // though the stream
          // has not yet reached its end.
          if (_source.read() == -1) {
            break;
          } else {
            ++bytesAdvanced;
          }
        }
      }
    }

    return bytesAdvanced;
  }

  /// Load the buffer with up to [targetSize] number of bytes. Actual load may
  /// be higher or lower than requested.
  ///
  /// [targetSize] is the number of bytes that should be loaded into the buffer.
  /// Returns the number of bytes actually in buffer.
  int fill(int targetSize) {
    int size = targetSize;
    if (size > buffer.length) {
      size = min(size, _resize(size));
    }

    while (availableBytes < size) {
      final int currentRead =
          _source.read(buffer, availableBytes, size - availableBytes);

      if (currentRead == -1) {
        _reachedEnd = true;
        break;
      } else {
        availableBytes += currentRead;
      }
    }

    return availableBytes;
  }

  int _resize(int targetSize) {
    final int newBufferSize = max(buffer.length * 2, targetSize);

    final MemoryInfo info = memoryInfo();

    final int currentFootprint = info.totalMemory - info.freeMemory;
    final int availableMemory = info.maxMemory - currentFootprint;

    if (_adaptiveMode && newBufferSize < availableMemory) {
      try {
        buffer = buffer.buffer.asUint8List(0, availableBytes);
      } on OutOfMemoryError catch (_) {
        Log.w(_tag, 'Turning off adaptive buffer resizing due to low memory.');
        _adaptiveMode = false;
      }
    } else {
      Log.w(_tag, 'Turning off adaptive buffer resizing to conserve memory.');
    }

    return buffer.length;
  }

  /// Whether we have reached the end of the stream and there is no more data to
  /// put into the buffer.
  bool isFinished() => _reachedEnd;
}

/// Contains the needed data to decide whether we should continue using the
/// adaptive buffer
class MemoryInfo {
  final int totalMemory;
  final int freeMemory;
  final int maxMemory;

  const MemoryInfo(this.totalMemory, this.freeMemory, this.maxMemory);
}

typedef GetMemoryInfo = MemoryInfo Function();
*/
