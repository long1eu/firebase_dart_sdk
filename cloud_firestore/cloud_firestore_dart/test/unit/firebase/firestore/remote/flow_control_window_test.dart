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

// The HTTP/2 flow-control window of the gRPC channel (grpcFlowControlWindow, 256 KiB by default as in the Android and
// JS SDKs). Frame-level tests of FlowControlWindow, then a channel against a local package:grpc server through a proxy
// that counts the bytes the server sends and can add latency.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/flow_control_window.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/grpc_channel.dart';
import 'package:grpc/grpc.dart';
import 'package:grpc/grpc_connection_interface.dart' show ClientChannelBase;
import 'package:http2/transport.dart' show ServerTransportConnection;
import 'package:test/test.dart';

Uint8List _frame(int type, int flags, int streamId, List<int> payload) {
  return Uint8List.fromList(<int>[
    (payload.length >> 16) & 0xff,
    (payload.length >> 8) & 0xff,
    payload.length & 0xff,
    type,
    flags,
    (streamId >> 24) & 0x7f,
    (streamId >> 16) & 0xff,
    (streamId >> 8) & 0xff,
    streamId & 0xff,
    ...payload,
  ]);
}

Uint8List _data(int streamId, int length) =>
    _frame(0x0, 0, streamId, List<int>.filled(length, streamId));

Uint8List _windowUpdate(int streamId, int increment) =>
    _frame(0x8, 0, streamId, <int>[
      (increment >> 24) & 0x7f,
      (increment >> 16) & 0xff,
      (increment >> 8) & 0xff,
      increment & 0xff,
    ]);

final Uint8List _preface = Uint8List.fromList(
  'PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n'.codeUnits,
);

/// The SETTINGS of the client: INITIAL_WINDOW_SIZE and ENABLE_PUSH.
final Uint8List _clientSettings = _frame(0x4, 0, 0, <int>[
  0, 4, 0, 4, 0, 0, //
  0, 2, 0, 0, 0, 0,
]);

final Uint8List _settingsAck = _frame(0x4, 0x1, 0, <int>[]);

/// The frames in [chunks], as (type, stream id, payload length).
List<(int, int, int)> _frames(List<List<int>> chunks) {
  final List<int> bytes = <int>[for (final List<int> c in chunks) ...c];
  final List<(int, int, int)> frames = <(int, int, int)>[];
  int offset = 0;
  while (offset + 9 <= bytes.length) {
    final int length =
        (bytes[offset] << 16) | (bytes[offset + 1] << 8) | bytes[offset + 2];
    final int streamId =
        ((bytes[offset + 5] & 0x7f) << 24) |
        (bytes[offset + 6] << 16) |
        (bytes[offset + 7] << 8) |
        bytes[offset + 8];
    frames.add((bytes[offset + 3], streamId, length));
    offset += 9 + length;
  }
  expect(offset, bytes.length, reason: 'whole frames');
  return frames;
}

class _CapturingSink implements StreamSink<List<int>> {
  final List<List<int>> chunks = <List<int>>[];
  final Completer<void> _done = Completer<void>();

  @override
  void add(List<int> data) => chunks.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.forEach(add);

  @override
  Future<void> close() async {
    if (!_done.isCompleted) {
      _done.complete();
    }
  }

  @override
  Future<void> get done => _done.future;
}

// --- The channel against a local server. ---

const int _messageSize = 128 * 1024;

List<int> _encodeCount(int count) => <int>[count];

int _decodeCount(List<int> bytes) => bytes.first;

List<int> _identity(List<int> bytes) => bytes;

/// Message [i] of a response: [_messageSize] bytes of value i.
List<int> _message(int i) =>
    Uint8List(_messageSize)..fillRange(0, _messageSize, i);

class _BigService extends Service {
  _BigService() {
    // Streams the requested number of messages.
    $addMethod(
      ServiceMethod<int, List<int>>(
        'Big',
        (ServiceCall call, Future<int> request) async* {
          final int count = await request;
          for (int i = 0; i < count; i++) {
            yield _message(i);
          }
        },
        false,
        true,
        _decodeCount,
        _identity,
      ),
    );
  }

  @override
  String get $name => 'test.Flow';
}

class _BigClient extends Client {
  _BigClient(ClientChannelBase super.channel);

  static final ClientMethod<int, List<int>> _big = ClientMethod<int, List<int>>(
    '/test.Flow/Big',
    _encodeCount,
    _identity,
  );

  ResponseStream<List<int>> big(int count) =>
      $createStreamingCall(_big, Stream<int>.value(count));
}

/// A TCP proxy that counts the bytes from the server to the client and delays everything by [latency] each way
/// (without limiting the throughput).
class _Proxy {
  _Proxy._(this._server, this.latency);

  final ServerSocket _server;
  final Duration latency;
  final List<Socket> _sockets = <Socket>[];

  int bytesToClient = 0;

  int get port => _server.port;

  static Future<_Proxy> start(
    int targetPort, {
    Duration latency = Duration.zero,
  }) async {
    final ServerSocket server = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final _Proxy proxy = _Proxy._(server, latency);
    server.listen((Socket client) async {
      final Socket upstream = await Socket.connect(
        InternetAddress.loopbackIPv4,
        targetPort,
      );
      proxy._sockets
        ..add(client)
        ..add(upstream);
      proxy._pipe(client, upstream, count: false);
      proxy._pipe(upstream, client, count: true);
    });
    return proxy;
  }

  void _pipe(Socket from, Socket to, {required bool count}) {
    // Timers of the same duration fire in the order they were created: the bytes stay in order.
    void later(void Function() action) =>
        latency == Duration.zero ? action() : Timer(latency, action);
    from.listen(
      (Uint8List data) => later(() {
        if (count) {
          bytesToClient += data.length;
        }
        try {
          to.add(data);
        } catch (_) {
          // Closed.
        }
      }),
      onError: (Object _) {},
      onDone: () => later(to.destroy),
    );
  }

  /// Waits until no bytes went to the client for [quiet].
  Future<int> settled({
    Duration quiet = const Duration(milliseconds: 400),
  }) async {
    final Stopwatch total = Stopwatch()..start();
    int last = -1;
    while (bytesToClient != last &&
        total.elapsed < const Duration(seconds: 10)) {
      last = bytesToClient;
      await Future<void>.delayed(quiet);
    }
    return bytesToClient;
  }

  Future<void> close() async {
    for (final Socket socket in _sockets) {
      socket.destroy();
    }
    await _server.close();
  }
}

void main() {
  group('FlowControlWindow', () {
    test(
      'grows the connection window right after the SETTINGS of the client',
      () {
        final FlowControlWindow window = FlowControlWindow(256 * 1024);
        final _CapturingSink socket = _CapturingSink();
        final StreamSink<List<int>> sink = window.bindOutgoing(socket);
        sink
          ..add(_preface)
          // The SETTINGS frame split across writes, followed by another frame in the same write.
          ..add(Uint8List.sublistView(_clientSettings, 0, 5))
          ..add(<int>[
            ...Uint8List.sublistView(_clientSettings, 5),
            ..._windowUpdate(0, 100),
          ]);

        final List<int> bytes = <int>[
          for (final List<int> c in socket.chunks) ...c,
        ];
        expect(bytes.sublist(0, 24), _preface);
        expect(_frames(<List<int>>[bytes.sublist(24)]), <(int, int, int)>[
          (0x4, 0, 12),
          (0x8, 0, 4), // added: 256 KiB - 65535
          (0x8, 0, 4), // of package:http2
        ]);
        final int injectedAt = 24 + 9 + 12 + 9;
        final int increment =
            (bytes[injectedAt] << 24) |
            (bytes[injectedAt + 1] << 16) |
            (bytes[injectedAt + 2] << 8) |
            bytes[injectedAt + 3];
        expect(increment, 256 * 1024 - http2DefaultWindowSize);
      },
    );

    test('adds nothing for a window not larger than the default', () {
      final FlowControlWindow window = FlowControlWindow(
        http2DefaultWindowSize,
      );
      final _CapturingSink socket = _CapturingSink();
      window.bindOutgoing(socket)
        ..add(_preface)
        ..add(_clientSettings);
      final List<int> bytes = <int>[
        for (final List<int> c in socket.chunks) ...c,
      ];
      expect(_frames(<List<int>>[bytes.sublist(24)]), <(int, int, int)>[
        (0x4, 0, 12),
      ]);
    });

    test('reports the acknowledgement of the settings', () async {
      final FlowControlWindow window = FlowControlWindow(256 * 1024);
      final StreamController<List<int>> socket = StreamController<List<int>>();
      final List<List<int>> received = <List<int>>[];
      window.bindIncoming(socket.stream).listen(received.add);
      bool acknowledged = false;
      unawaited(window.settingsAcknowledged.then((_) => acknowledged = true));

      // The server's own SETTINGS are not the acknowledgement.
      socket.add(_frame(0x4, 0, 0, <int>[]));
      await pumpEventQueue();
      expect(acknowledged, isFalse);
      // Split in the middle of the frame header.
      socket
        ..add(Uint8List.sublistView(_settingsAck, 0, 4))
        ..add(Uint8List.sublistView(_settingsAck, 4));
      await pumpEventQueue();
      expect(acknowledged, isTrue);
      expect(_frames(received), <(int, int, int)>[(0x4, 0, 0), (0x4, 0, 0)]);
      await socket.close();
    });

    test(
      'fails the wait for the acknowledgement on GOAWAY or the end of the connection',
      () async {
        final FlowControlWindow goAway = FlowControlWindow(256 * 1024);
        final StreamController<List<int>> socket =
            StreamController<List<int>>();
        goAway.bindIncoming(socket.stream).listen((_) {});
        socket.add(_frame(0x7, 0, 0, List<int>.filled(8, 0)));
        await expectLater(goAway.settingsAcknowledged, throwsStateError);
        await socket.close();

        final FlowControlWindow closed = FlowControlWindow(256 * 1024);
        final StreamController<List<int>> socket2 =
            StreamController<List<int>>();
        closed.bindIncoming(socket2.stream).listen((_) {});
        await socket2.close();
        await expectLater(closed.settingsAcknowledged, throwsStateError);
      },
    );

    test(
      'holds the stream data that package:http2 would not accept, and lets it through when it acknowledges data',
      () async {
        final FlowControlWindow window = FlowControlWindow(256 * 1024);
        window.settingsAcknowledged.ignore();
        final StreamController<List<int>> socket =
            StreamController<List<int>>();
        final List<List<int>> received = <List<int>>[];
        window.bindIncoming(socket.stream).listen(received.add);
        final _CapturingSink out = _CapturingSink();
        final StreamSink<List<int>> sink = window.bindOutgoing(out)
          ..add(_preface)
          ..add(_clientSettings);

        // 4 frames of 16000 bytes fit in the 65535 bytes package:http2 allows itself, the fifth does not.
        for (int i = 0; i < 5; i++) {
          socket.add(_data(1, 16000));
        }
        // The data of stream 3 does not fit either (65600 bytes).
        socket
          ..add(_data(3, 1600))
          // Frames of the connection are never held.
          ..add(_frame(0x6, 0x1, 0, List<int>.filled(8, 0))) // PING ack
          // A frame without data of stream 5, which has nothing held, is not held.
          ..add(_frame(0x1, 0x4, 5, <int>[0x88]))
          // A frame without data of stream 1 stays behind its data.
          ..add(_frame(0x1, 0x5, 1, <int>[0x88]));
        await pumpEventQueue();
        expect(_frames(received), <(int, int, int)>[
          (0x0, 1, 16000),
          (0x0, 1, 16000),
          (0x0, 1, 16000),
          (0x0, 1, 16000),
          (0x6, 0, 8),
          (0x1, 5, 1),
        ]);
        expect(window.heldBytes, (9 + 16000) + (9 + 1600) + (9 + 1));

        // package:http2 acknowledges 16 KiB of the connection: the fifth frame and the frame of stream 3 fit. A
        // WINDOW_UPDATE of a stream does not count.
        received.clear();
        sink
          ..add(_windowUpdate(1, 16 * 1024))
          ..add(_windowUpdate(0, 16 * 1024));
        await pumpEventQueue();
        expect(_frames(received), <(int, int, int)>[
          (0x0, 1, 16000),
          (0x0, 3, 1600),
          (0x1, 1, 1),
        ]);
        expect(window.heldBytes, 0);
        await socket.close();
      },
    );

    test('counts the data of a padded frame without its padding', () async {
      final FlowControlWindow window = FlowControlWindow(256 * 1024);
      window.settingsAcknowledged.ignore();
      final StreamController<List<int>> socket = StreamController<List<int>>();
      final List<List<int>> received = <List<int>>[];
      window.bindIncoming(socket.stream).listen(received.add);
      // 65535 bytes of data, of which 3 frames carry 255 bytes of padding each (16384 bytes per frame at most).
      for (int i = 0; i < 3; i++) {
        socket.add(
          _frame(0x0, 0x8, 1, <int>[
            255,
            ...List<int>.filled(16128, 1),
            ...List<int>.filled(255, 0),
          ]),
        );
      }
      socket
        ..add(_data(1, 16000))
        ..add(_data(1, http2DefaultWindowSize - 3 * 16128 - 16000));
      await pumpEventQueue();
      expect(received, hasLength(5));
      expect(window.heldBytes, 0);
      socket.add(_data(1, 1));
      await pumpEventQueue();
      expect(received, hasLength(5));
      expect(window.heldBytes, 10);
      await socket.close();
    });
  });

  group('a server that does not follow the protocol', () {
    /// A window of 256 KiB with the settings acknowledged; returns the socket, what package:http2 received and the
    /// errors it got.
    (
      StreamController<List<int>>,
      List<List<int>>,
      List<Object>,
      FlowControlWindow,
    )
    open() {
      final FlowControlWindow window = FlowControlWindow(256 * 1024);
      window.settingsAcknowledged.ignore();
      final StreamController<List<int>> socket = StreamController<List<int>>();
      final List<List<int>> received = <List<int>>[];
      final List<Object> errors = <Object>[];
      window
          .bindIncoming(socket.stream)
          .listen(received.add, onError: errors.add);
      return (socket, received, errors, window);
    }

    test('more data than the window allows ends the connection', () async {
      final (
        StreamController<List<int>> socket,
        List<List<int>> received,
        List<Object> errors,
        FlowControlWindow window,
      ) = open();
      // 65535 bytes reach package:http2; 256 KiB - 64 KiB more may be held while it does not read.
      final int allowed = 256 * 1024 - http2DefaultWindowSize;
      for (int sent = 0; sent < http2DefaultWindowSize; sent += 16000) {
        socket.add(
          _data(
            1,
            sent + 16000 > http2DefaultWindowSize
                ? http2DefaultWindowSize - sent
                : 16000,
          ),
        );
      }
      for (int held = 0; held < allowed; held += 16000) {
        socket.add(_data(1, held + 16000 > allowed ? allowed - held : 16000));
      }
      await pumpEventQueue();
      expect(errors, isEmpty);
      expect(window.heldBytes, greaterThan(allowed));

      // One byte more than the server was allowed to send.
      socket.add(_data(1, 1));
      await pumpEventQueue();
      expect(errors, hasLength(1));
      expect(window.heldBytes, 0);
      final int count = received.length;
      socket.add(_data(1, 1000));
      await pumpEventQueue();
      expect(received, hasLength(count), reason: 'nothing after the error');
      expect(
        socket.hasListener,
        isFalse,
        reason: 'the socket is no longer read',
      );
    });

    test(
      'a frame larger than the maximum frame size ends the connection at its header',
      () async {
        final (
          StreamController<List<int>> socket,
          List<List<int>> received,
          List<Object> errors,
          FlowControlWindow window,
        ) = open();
        // The header of a frame of 16 MiB - 1, and the first bytes of its payload.
        socket.add(<int>[0xff, 0xff, 0xff, 0x0, 0, 0, 0, 0, 1, 1, 2, 3]);
        await pumpEventQueue();
        expect(errors, hasLength(1));
        expect(received, isEmpty);
        await expectLater(window.settingsAcknowledged, throwsStateError);
      },
    );

    test('frames without data held behind data are limited too', () async {
      final (
        StreamController<List<int>> socket,
        List<List<int>> received,
        List<Object> errors,
        FlowControlWindow window,
      ) = open();
      for (int sent = 0; sent < http2DefaultWindowSize; sent += 16000) {
        socket.add(
          _data(
            1,
            sent + 16000 > http2DefaultWindowSize
                ? http2DefaultWindowSize - sent
                : 16000,
          ),
        );
      }
      socket.add(_data(1, 1)); // held
      // CONTINUATION frames of stream 1, held behind its data.
      // 1 MiB is FlowControlWindow.maxHeldControlBytes.
      for (int i = 0; i * 16000 <= 1024 * 1024; i++) {
        socket.add(_frame(0x9, 0, 1, List<int>.filled(16000, 0)));
      }
      await pumpEventQueue();
      expect(errors, hasLength(1));
      expect(window.heldBytes, 0);
    });
  });

  group('the channel', () {
    late Server server;
    late _Proxy proxy;
    final List<ClientChannelBase> channels = <ClientChannelBase>[];

    Future<void> startServer({Duration latency = Duration.zero}) async {
      server = Server.create(services: <Service>[_BigService()]);
      await server.serve(address: InternetAddress.loopbackIPv4, port: 0);
      proxy = await _Proxy.start(server.port!, latency: latency);
    }

    _BigClient client(int window) {
      final ClientChannelBase channel = createGrpcChannel(
        host: '127.0.0.1',
        port: proxy.port,
        sslEnabled: false,
        flowControlWindow: window,
      );
      channels.add(channel);
      return _BigClient(channel);
    }

    tearDown(() async {
      for (final ClientChannelBase channel in channels) {
        await channel.terminate();
      }
      channels.clear();
      await proxy.close();
      // See http2_reset_race_test.dart: let the server notice the closed sockets before shutting it down.
      final Stopwatch stopwatch = Stopwatch()..start();
      // ignore: invalid_use_of_visible_for_testing_member
      while (server.handlers.isNotEmpty &&
          stopwatch.elapsed < const Duration(seconds: 10)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      // ignore: invalid_use_of_visible_for_testing_member
      for (final ServerTransportConnection connection
          in server.handlers.keys.toList()) {
        await connection.terminate();
      }
      await server.shutdown();
    });

    for (final int window in <int>[
      http2DefaultWindowSize,
      256 * 1024,
      1024 * 1024,
    ]) {
      test(
        'lets the server send a whole window of $window bytes to a call that is not read, and nothing more',
        () async {
          await startServer();
          final _BigClient big = client(window);
          final List<List<int>> messages = <List<int>>[];
          final Completer<void> done = Completer<void>();
          // 40 messages of 128 KiB (5 MiB); not read until resumed.
          final StreamSubscription<List<int>> subscription =
              big
                  .big(40)
                  .listen(
                    messages.add,
                    onError: done.completeError,
                    onDone: done.complete,
                  )
                ..pause();

          final int sent = await proxy.settled();
          // HTTP/2 framing, the gRPC prefixes and the headers come on top of the window.
          expect(sent, greaterThanOrEqualTo(window));
          expect(sent, lessThan(window + 8 * 1024));
          expect(messages, isEmpty);

          subscription.resume();
          await done.future.timeout(const Duration(seconds: 20));
          expect(messages, hasLength(40));
          for (int i = 0; i < 40; i++) {
            expect(messages[i].length, _messageSize);
            expect(
              messages[i].every((int b) => b == i),
              isTrue,
              reason: 'message $i',
            );
          }
          // The connection still works.
          expect(await big.big(2).length, 2);
        },
      );
    }

    test(
      'reads a large response faster over a connection with a long round trip',
      () async {
        // 50 ms round trip; 32 messages of 128 KiB (4 MiB). 64 KiB per round trip need about 3.2 s, 256 KiB about 0.8 s.
        await startServer(latency: const Duration(milliseconds: 25));
        Future<Duration> read(int window) async {
          final _BigClient big = client(window);
          // Connected (and the window acknowledged) before the clock starts.
          expect(await big.big(1).length, 1);
          final Stopwatch stopwatch = Stopwatch()..start();
          expect(await big.big(32).length, 32);
          return stopwatch.elapsed;
        }

        final Duration small = await read(http2DefaultWindowSize);
        final Duration large = await read(256 * 1024);
        // ignore: avoid_print
        print(
          '64 KiB window: ${small.inMilliseconds} ms, 256 KiB window: ${large.inMilliseconds} ms',
        );
        expect(large * 2, lessThan(small));
      },
    );
  });
}
