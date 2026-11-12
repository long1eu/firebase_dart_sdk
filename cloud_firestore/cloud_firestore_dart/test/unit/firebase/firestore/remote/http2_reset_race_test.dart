// Characterisation test of a package:http2 behaviour that the client has to
// work around (seen with http2 2.3.1 and grpc 4.1.0).
//
// When a client resets a stream (RST_STREAM, which is what cancelling a gRPC
// call or the subscription of its responses does) while the server's trailers
// for that stream are on their way, package:http2 treats the late HEADERS
// frame as a connection error ("HTTP/2 clients cannot receive HEADER_FRAMEs as
// a connection attempt") and terminates the whole connection. Every other
// call on the channel fails, including calls the server already executed.
//
// This is why the client never cancels a call that the server may be
// finishing (see call_release.dart). If this test starts failing because the
// other call survives, package:http2 was fixed and the workaround can go.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/call_release.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/grpc_channel.dart';
import 'package:grpc/grpc.dart';
import 'package:grpc/grpc_connection_interface.dart' show ClientChannelBase;
import 'package:test/test.dart';

List<int> _encode(int value) => <int>[value];

int _decode(List<int> value) => value.isEmpty ? 0 : value.first;

class _TestService extends Service {
  _TestService() {
    // Never answers: stands for a call that is in flight.
    $addMethod(ServiceMethod<int, int>(
      'Hang',
      (ServiceCall call, Future<int> request) {
        hangCalls++;
        return StreamController<int>().stream;
      },
      false,
      true,
      _decode,
      _encode,
    ));
    // Sends one message and finishes right away, like BatchGetDocuments.
    $addMethod(ServiceMethod<int, int>(
      'One',
      (ServiceCall call, Future<int> request) => Stream<int>.value(7),
      false,
      true,
      _decode,
      _encode,
    ));
  }

  int hangCalls = 0;

  @override
  String get $name => 'test.Race';
}

class _TestClient extends Client {
  _TestClient(ClientChannelBase channel) : super(channel);

  static final ClientMethod<int, int> _hang =
      ClientMethod<int, int>('/test.Race/Hang', _encode, _decode);
  static final ClientMethod<int, int> _one =
      ClientMethod<int, int>('/test.Race/One', _encode, _decode);

  ResponseStream<int> hang() =>
      $createStreamingCall(_hang, Stream<int>.value(1));

  ResponseStream<int> one() => $createStreamingCall(_one, Stream<int>.value(1));
}

/// A TCP proxy that understands just enough HTTP/2 framing to delay the
/// trailers of a call: when the server ends a stream with a HEADERS frame, the
/// frame (and everything after it) is held back for [trailersDelay]. The
/// client receives the response message first and has time to react to it
/// before the trailers arrive, which makes the race deterministic.
class _TrailerDelayProxy {
  _TrailerDelayProxy._(this._server, this.trailersDelay);

  final ServerSocket _server;
  final Duration trailersDelay;
  final List<Socket> _sockets = <Socket>[];

  /// The number of stream-ending HEADERS frames that were delayed.
  int delayedTrailers = 0;

  int get port => _server.port;

  static Future<_TrailerDelayProxy> start(
      int targetPort, Duration trailersDelay) async {
    final ServerSocket server =
        await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final _TrailerDelayProxy proxy =
        _TrailerDelayProxy._(server, trailersDelay);
    server.listen((Socket client) async {
      final Socket upstream =
          await Socket.connect(InternetAddress.loopbackIPv4, targetPort);
      proxy._sockets
        ..add(client)
        ..add(upstream);
      client.listen(upstream.add,
          onError: (Object _) {}, onDone: upstream.destroy);
      proxy._pipeServerToClient(upstream, client);
    });
    return proxy;
  }

  void _pipeServerToClient(Socket from, Socket to) {
    final BytesBuilder pending = BytesBuilder();
    // Frames are forwarded in order: once one is delayed, later ones wait.
    Future<void> tail = Future<void>.value();

    void forward(Uint8List frame, {required bool delay}) {
      tail = tail.then((_) async {
        if (delay) {
          await Future<void>.delayed(trailersDelay);
        }
        try {
          to.add(frame);
        } catch (_) {
          // The client already closed the socket.
        }
      });
    }

    from.listen(
      (Uint8List data) {
        pending.add(data);
        Uint8List bytes = pending.takeBytes();
        // Frame header: length (3 bytes), type, flags, stream id (4 bytes).
        while (bytes.length >= 9) {
          final int length = (bytes[0] << 16) | (bytes[1] << 8) | bytes[2];
          if (bytes.length < 9 + length) {
            break;
          }
          final int type = bytes[3];
          final int flags = bytes[4];
          const int headersFrame = 0x1;
          const int endStream = 0x1;
          final bool trailers = type == headersFrame && flags & endStream != 0;
          if (trailers) {
            delayedTrailers++;
          }
          forward(Uint8List.sublistView(bytes, 0, 9 + length), delay: trailers);
          bytes = Uint8List.sublistView(bytes, 9 + length);
        }
        pending.add(bytes);
      },
      onError: (Object _) {},
      onDone: () => tail.then((_) => to.destroy()),
    );
  }

  Future<void> close() async {
    for (final Socket socket in _sockets) {
      socket.destroy();
    }
    await _server.close();
  }
}

void main() {
  late Server server;
  late _TestService service;
  late _TrailerDelayProxy proxy;
  late ClientChannelBase channel;
  late _TestClient client;

  setUp(() async {
    service = _TestService();
    server = Server.create(services: <Service>[service]);
    await server.serve(address: InternetAddress.loopbackIPv4, port: 0);
    proxy = await _TrailerDelayProxy.start(
        server.port!, const Duration(milliseconds: 300));
    channel = createGrpcChannel(
        host: '127.0.0.1', port: proxy.port, sslEnabled: false);
    client = _TestClient(channel);
  });

  tearDown(() async {
    await channel.terminate();
    await proxy.close();
    await server.shutdown();
  });

  /// Starts a call that stays in flight and returns the error that ends it.
  Future<Completer<Object>> startCallInFlight() async {
    final Completer<Object> failure = Completer<Object>();
    client.hang().listen((int _) {}, onError: (Object error) {
      if (!failure.isCompleted) {
        failure.complete(error);
      }
    });
    final Stopwatch stopwatch = Stopwatch()..start();
    while (service.hangCalls == 0) {
      if (stopwatch.elapsed > const Duration(seconds: 15)) {
        fail('The call in flight never reached the server');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    return failure;
  }

  test(
      'cancelling a call whose trailers are on their way terminates the '
      'connection and fails the other calls', () async {
    final Completer<Object> inFlight = await startCallInFlight();

    // Take the only message and cancel, as `stream.first` does.
    final ResponseStream<int> call = client.one();
    expect(await call.first, 7);

    final Object error =
        await inFlight.future.timeout(const Duration(seconds: 5));
    expect(proxy.delayedTrailers, 1);
    expect(
        error,
        isA<GrpcError>()
            .having((GrpcError e) => e.code, 'code', StatusCode.unknown)
            .having((GrpcError e) => e.message, 'message',
                contains('Connection is being forcefully terminated')));
  });

  test(
      'CallReleaser.first takes the first response without affecting other '
      'calls', () async {
    final Completer<Object> inFlight = await startCallInFlight();

    final CallReleaser releaser =
        CallReleaser(gracePeriod: const Duration(seconds: 5));
    final ResponseStream<int> call = client.one();
    expect(await releaser.first(call, call.cancel), 7);

    await Future<void>.delayed(const Duration(milliseconds: 800));
    expect(proxy.delayedTrailers, 1);
    expect(inFlight.isCompleted, isFalse);
    // The call closed by itself.
    expect(releaser.pendingCount, 0);
  });

  test('control: a call that is left to finish does not affect other calls',
      () async {
    final Completer<Object> inFlight = await startCallInFlight();

    // Drained to the end: the client never resets the stream.
    expect(await client.one().toList(), <int>[7]);
    expect(proxy.delayedTrailers, 1);

    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(inFlight.isCompleted, isFalse);
  });
}
