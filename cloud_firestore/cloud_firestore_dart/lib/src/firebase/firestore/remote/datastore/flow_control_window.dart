// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:async';
import 'dart:typed_data';

/// The HTTP/2 flow-control window that applies when nothing else was agreed, for the connection and for every
/// stream: 65,535 bytes (RFC 9113, section 6.9.2).
const int http2DefaultWindowSize = 65535;

/// The largest HTTP/2 flow-control window, 2^31 - 1 bytes.
const int http2MaxWindowSize = 0x7fffffff;

/// Gives an HTTP/2 client connection of package:http2 a receive window of [windowSize] bytes, for the connection as
/// a whole and not only per stream.
///
/// The Android and JS SDKs set the flow-control window of their gRPC channel to 256 KiB (`grpcFlowControlWindow`).
/// The window bounds how much the server may send before the client acknowledges it, so with the HTTP/2 default of
/// 64 KiB a large response is read at no more than 64 KiB per round trip. package:http2 (2.3.1, also 3.1.0) can only
/// announce the window of the streams (`ClientSettings.streamWindowSize`); the window of the connection, which all the
/// streams share, stays at 64 KiB. This class sits between the socket and the http2 connection:
///
/// * Outgoing, it adds one WINDOW_UPDATE for the connection after the initial SETTINGS of the client, which grows the
///   window of the connection to [windowSize] on the server's side.
/// * Incoming, it lets through only as much stream data as the http2 connection still allows itself (it mirrors that
///   window from the frames: DATA in, WINDOW_UPDATE out). package:http2 terminates the connection with a flow-control
///   error when it receives more than that, which can only happen while a response is not read (paused). The rest is
///   held here until package:http2 acknowledges data. The frames of a stream stay in order, but a stream does not
///   wait behind the held data of another one, and frames of the connection itself (SETTINGS, PING, GOAWAY,
///   WINDOW_UPDATE) are never held, so that keepalive pings keep working while data is held.
///
/// It also reports when the server acknowledged the client's SETTINGS ([settingsAcknowledged]). Calls must not start
/// before that: when package:http2 receives the acknowledgement of a larger stream window, it applies the difference
/// to the send windows of the streams that are open (instead of their receive windows), so a stream opened before
/// could send more than the server allows and receive less than the server sends.
class FlowControlWindow {
  /// [windowSize] must be positive and at most [http2MaxWindowSize]. The window of a connection can not shrink: below
  /// [http2DefaultWindowSize] only the window of the streams is smaller.
  FlowControlWindow(this.windowSize)
    : assert(windowSize > 0 && windowSize <= http2MaxWindowSize);

  /// The receive window, in bytes.
  final int windowSize;

  static const int _dataFrame = 0x0;
  static const int _settingsFrame = 0x4;
  static const int _goAwayFrame = 0x7;
  static const int _windowUpdateFrame = 0x8;
  static const int _ackFlag = 0x1;
  static const int _paddedFlag = 0x8;
  static const int _frameHeaderLength = 9;

  /// The client connection preface: `PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n`.
  static const int _prefaceLength = 24;

  final Completer<void> _settingsAcknowledged = Completer<void>();

  /// The connection window as package:http2 sees it: what it announced minus the stream data it received.
  int _libraryWindow = http2DefaultWindowSize;

  /// Frames of the streams that package:http2 can not take yet, in the order they arrived, and how many of them each
  /// stream has.
  final List<_HeldFrame> _held = <_HeldFrame>[];
  final Map<int, int> _heldPerStream = <int, int>{};
  int _heldBytes = 0;

  late final StreamController<List<int>> _incoming;
  StreamSubscription<List<int>>? _socketSubscription;
  Uint8List? _incomingRest;

  // Parser state of the outgoing bytes.
  int _outgoingPreface = _prefaceLength;
  final Uint8List _outgoingHeader = Uint8List(_frameHeaderLength);
  int _outgoingHeaderLength = 0;
  int _outgoingPayloadLeft = 0;
  bool _outgoingIsConnectionWindowUpdate = false;
  final Uint8List _outgoingIncrement = Uint8List(4);
  int _outgoingIncrementLength = 0;
  bool _outgoingSettingsSeen = false;
  bool _windowUpdateSent = false;

  /// Completes when the server acknowledged the initial SETTINGS of the client; completes with an error when the
  /// connection ends, or the server sends GOAWAY, before that.
  Future<void> get settingsAcknowledged => _settingsAcknowledged.future;

  /// The bytes of stream frames that are held back because package:http2 would not accept them yet.
  int get heldBytes => _heldBytes;

  /// The bytes received from the server, for package:http2.
  Stream<List<int>> bindIncoming(Stream<List<int>> socket) {
    _incoming = StreamController<List<int>>(
      onListen: () {
        _socketSubscription = socket.listen(
          _onIncoming,
          onError: _incoming.addError,
          onDone: _onIncomingDone,
        );
      },
      onPause: () => _socketSubscription?.pause(),
      onResume: () => _socketSubscription?.resume(),
      onCancel: () => _socketSubscription?.cancel(),
    );
    return _incoming.stream;
  }

  /// The sink package:http2 writes to; forwards to [socket].
  StreamSink<List<int>> bindOutgoing(StreamSink<List<int>> socket) =>
      _OutgoingSink(socket, this);

  void _onIncoming(List<int> data) {
    Uint8List bytes = data is Uint8List ? data : Uint8List.fromList(data);
    final Uint8List? rest = _incomingRest;
    if (rest != null) {
      // Less than one frame (at most 16 KiB, the default maximum frame size that package:http2 does not raise).
      bytes =
          (BytesBuilder(copy: false)
                ..add(rest)
                ..add(bytes))
              .takeBytes();
      _incomingRest = null;
    }
    int offset = 0;
    while (bytes.length - offset >= _frameHeaderLength) {
      final int length =
          (bytes[offset] << 16) | (bytes[offset + 1] << 8) | bytes[offset + 2];
      final int end = offset + _frameHeaderLength + length;
      if (end > bytes.length) {
        break;
      }
      _onIncomingFrame(Uint8List.sublistView(bytes, offset, end));
      offset = end;
    }
    if (offset < bytes.length) {
      _incomingRest = Uint8List.fromList(Uint8List.sublistView(bytes, offset));
    }
  }

  void _onIncomingFrame(Uint8List frame) {
    final int type = frame[3];
    final int streamId =
        ((frame[5] & 0x7f) << 24) |
        (frame[6] << 16) |
        (frame[7] << 8) |
        frame[8];
    if (streamId == 0) {
      if (!_settingsAcknowledged.isCompleted) {
        if (type == _settingsFrame && frame[4] & _ackFlag != 0) {
          _settingsAcknowledged.complete();
        } else if (type == _goAwayFrame) {
          // The server will not take a call on this connection.
          _settingsAcknowledged.completeError(
            StateError(
              'The server sent GOAWAY before acknowledging the settings',
            ),
          );
        }
      }
      _incoming.add(frame);
      return;
    }
    // The frames of a stream stay in order; a stream does not wait for the data of another one.
    if (!_heldPerStream.containsKey(streamId) &&
        _flowControlledLength(frame) <= _libraryWindow) {
      _forward(frame);
    } else {
      _held.add(_HeldFrame(streamId, frame));
      _heldPerStream[streamId] = (_heldPerStream[streamId] ?? 0) + 1;
      _heldBytes += frame.length;
    }
  }

  /// The bytes of [frame] that package:http2 counts against its window: the data of a DATA frame, without padding.
  static int _flowControlledLength(Uint8List frame) {
    if (frame[3] != _dataFrame) {
      return 0;
    }
    final int length = frame.length - _frameHeaderLength;
    if (frame[4] & _paddedFlag != 0 && length > 0) {
      return length - 1 - frame[_frameHeaderLength];
    }
    return length;
  }

  void _forward(Uint8List frame) {
    _libraryWindow -= _flowControlledLength(frame);
    _incoming.add(frame);
  }

  void _release() {
    if (_held.isEmpty) {
      return;
    }
    final Set<int> blocked = <int>{};
    final List<_HeldFrame> stillHeld = <_HeldFrame>[];
    for (final _HeldFrame held in _held) {
      if (blocked.contains(held.streamId) ||
          _flowControlledLength(held.frame) > _libraryWindow) {
        blocked.add(held.streamId);
        stillHeld.add(held);
        continue;
      }
      _heldBytes -= held.frame.length;
      final int left = _heldPerStream[held.streamId]! - 1;
      if (left == 0) {
        _heldPerStream.remove(held.streamId);
      } else {
        _heldPerStream[held.streamId] = left;
      }
      _forward(held.frame);
    }
    _held
      ..clear()
      ..addAll(stillHeld);
  }

  void _onIncomingDone() {
    // Whatever is held goes to package:http2, which reports the end of the connection to the streams.
    for (final _HeldFrame held in _held) {
      _incoming.add(held.frame);
    }
    _held.clear();
    _heldPerStream.clear();
    _heldBytes = 0;
    if (!_settingsAcknowledged.isCompleted) {
      _settingsAcknowledged.completeError(
        StateError(
          'The connection closed before the settings were acknowledged',
        ),
      );
    }
    _incoming.close();
  }

  /// Parses what package:http2 writes: notes its connection WINDOW_UPDATEs, and returns [data] with the WINDOW_UPDATE
  /// of this class inserted after the initial SETTINGS frame.
  List<List<int>> _onOutgoing(List<int> data) {
    int injectAt = -1;
    int i = 0;
    while (i < data.length) {
      if (_outgoingPreface > 0) {
        final int skip = _min(_outgoingPreface, data.length - i);
        _outgoingPreface -= skip;
        i += skip;
        continue;
      }
      if (_outgoingHeaderLength < _frameHeaderLength) {
        _outgoingHeader[_outgoingHeaderLength++] = data[i++];
        if (_outgoingHeaderLength == _frameHeaderLength) {
          _outgoingPayloadLeft =
              (_outgoingHeader[0] << 16) |
              (_outgoingHeader[1] << 8) |
              _outgoingHeader[2];
          final int streamId =
              ((_outgoingHeader[5] & 0x7f) << 24) |
              (_outgoingHeader[6] << 16) |
              (_outgoingHeader[7] << 8) |
              _outgoingHeader[8];
          _outgoingIsConnectionWindowUpdate =
              _outgoingHeader[3] == _windowUpdateFrame && streamId == 0;
          _outgoingIncrementLength = 0;
          if (_outgoingHeader[3] == _settingsFrame) {
            _outgoingSettingsSeen = true;
          }
          if (_outgoingPayloadLeft == 0) {
            injectAt = _frameEnded(i, injectAt);
          }
        }
        continue;
      }
      final int take = _min(_outgoingPayloadLeft, data.length - i);
      if (_outgoingIsConnectionWindowUpdate) {
        for (int j = 0; j < take && _outgoingIncrementLength < 4; j++) {
          _outgoingIncrement[_outgoingIncrementLength++] = data[i + j];
        }
      }
      i += take;
      _outgoingPayloadLeft -= take;
      if (_outgoingPayloadLeft == 0) {
        injectAt = _frameEnded(i, injectAt);
      }
    }
    if (injectAt < 0) {
      return <List<int>>[data];
    }
    return <List<int>>[
      if (injectAt > 0) _slice(data, 0, injectAt),
      _windowUpdate(windowSize - http2DefaultWindowSize),
      if (injectAt < data.length) _slice(data, injectAt, data.length),
    ];
  }

  /// A frame of the outgoing bytes ended at [position]. Returns where the WINDOW_UPDATE of this class goes, if it goes
  /// into this piece of data.
  int _frameEnded(int position, int injectAt) {
    _outgoingHeaderLength = 0;
    if (_outgoingIsConnectionWindowUpdate && _outgoingIncrementLength == 4) {
      final int increment =
          ((_outgoingIncrement[0] & 0x7f) << 24) |
          (_outgoingIncrement[1] << 16) |
          (_outgoingIncrement[2] << 8) |
          _outgoingIncrement[3];
      _libraryWindow += increment;
      _release();
    }
    if (_outgoingSettingsSeen &&
        !_windowUpdateSent &&
        windowSize > http2DefaultWindowSize) {
      // The SETTINGS frame must be the first frame of the client; the window can grow right after it.
      _windowUpdateSent = true;
      return position;
    }
    return injectAt;
  }

  static List<int> _slice(List<int> data, int start, int end) =>
      data is Uint8List
      ? Uint8List.sublistView(data, start, end)
      : data.sublist(start, end);

  static Uint8List _windowUpdate(int increment) {
    return Uint8List.fromList(<int>[
      0, 0, 4, // length
      _windowUpdateFrame,
      0, // flags
      0, 0, 0, 0, // stream 0: the connection
      (increment >> 24) & 0x7f,
      (increment >> 16) & 0xff,
      (increment >> 8) & 0xff,
      increment & 0xff,
    ]);
  }

  static int _min(int a, int b) => a < b ? a : b;
}

class _HeldFrame {
  _HeldFrame(this.streamId, this.frame);

  final int streamId;
  final Uint8List frame;
}

class _OutgoingSink implements StreamSink<List<int>> {
  _OutgoingSink(this._socket, this._window);

  final StreamSink<List<int>> _socket;
  final FlowControlWindow _window;

  @override
  void add(List<int> data) {
    _window._onOutgoing(data).forEach(_socket.add);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _socket.addError(error, stackTrace);

  @override
  Future<void> addStream(Stream<List<int>> stream) =>
      _socket.addStream(stream.expand(_window._onOutgoing));

  @override
  Future<void> close() async => _socket.close();

  @override
  Future<void> get done async => _socket.done;
}
