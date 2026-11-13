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

// Terminating the channel right after the peer dropped the connection, before the client read that it was dropped.
// package:http2 then closes its side and waits for the socket to be done, which never happens: the read side is
// cancelled, so the socket never learns that the peer is gone. Found by the scale soak (a client terminated right
// after its network was cut): terminate never completed, and the socket kept the isolate alive.

@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/grpc_channel.dart';
import 'package:grpc/grpc.dart';
import 'package:grpc/grpc_connection_interface.dart' show ClientChannelBase;
import 'package:test/test.dart';

/// A server streaming method that never answers: it keeps the call open.
class _HangService extends Service {
  _HangService() {
    $addMethod(
      ServiceMethod<int, int>(
        'Hang',
        (ServiceCall call, Future<int> request) =>
            StreamController<int>().stream,
        false,
        true,
        (List<int> value) => value.isEmpty ? 0 : value.first,
        (int value) => <int>[value],
      ),
    );
  }

  @override
  String get $name => 'test.Hang';
}

class _TestClient extends Client {
  _TestClient(super.channel);

  static final ClientMethod<int, int> _hang = ClientMethod<int, int>(
    '/test.Hang/Hang',
    (int value) => <int>[value],
    (List<int> value) => value.isEmpty ? 0 : value.first,
  );

  ResponseStream<int> hang() =>
      $createStreamingCall(_hang, Stream<int>.value(1));
}

/// A TCP proxy whose connections can be dropped at once, as a network that goes away does.
class _DroppingProxy {
  _DroppingProxy._(this._server);

  final ServerSocket _server;
  final List<Socket> _sockets = <Socket>[];

  int get port => _server.port;

  static Future<_DroppingProxy> start(int targetPort) async {
    final ServerSocket server = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final _DroppingProxy proxy = _DroppingProxy._(server);
    server.listen((Socket client) async {
      final Socket upstream = await Socket.connect(
        InternetAddress.loopbackIPv4,
        targetPort,
      );
      proxy._sockets
        ..add(client)
        ..add(upstream);
      void pipe(Socket from, Socket to) {
        from.listen(
          (Uint8List data) => to.add(data),
          onError: (Object _) {},
          onDone: to.destroy,
        );
      }

      pipe(client, upstream);
      pipe(upstream, client);
    });
    return proxy;
  }

  /// Drops every connection.
  void drop() {
    for (final Socket socket in _sockets) {
      socket.destroy();
    }
    _sockets.clear();
  }

  Future<void> close() async {
    drop();
    await _server.close();
  }
}

void main() {
  late Server server;
  late _DroppingProxy proxy;

  setUp(() async {
    server = Server.create(services: <Service>[_HangService()]);
    await server.serve(address: InternetAddress.loopbackIPv4, port: 0);
    proxy = await _DroppingProxy.start(server.port!);
  });

  tearDown(() async {
    await proxy.close();
    await server.shutdown();
  });

  test('terminate completes when the peer just dropped the connection', () async {
    for (int round = 0; round < 5; round++) {
      final ClientChannelBase channel = createGrpcChannel(
        host: InternetAddress.loopbackIPv4.address,
        port: proxy.port,
        sslEnabled: false,
      );
      final ResponseStream<int> call = _TestClient(channel).hang();
      final Completer<void> callEnded = Completer<void>();
      call.listen(
        (_) {},
        onError: (Object _) => callEnded.complete(),
        onDone: () {
          if (!callEnded.isCompleted) {
            callEnded.complete();
          }
        },
      );
      // Wait for the call to be on the wire.
      await Future<void>.delayed(const Duration(milliseconds: 200));

      // A request is on its way out when the peer goes away, and the client terminates before it read so.
      _TestClient(channel).hang().listen((_) {}, onError: (Object _) {});
      await Future<void>.delayed(Duration.zero);
      proxy.drop();
      final Stopwatch watch = Stopwatch()..start();
      await channel.terminate().timeout(
        const Duration(seconds: 10),
        onTimeout: () => fail('round $round: terminate did not complete'),
      );
      expect(
        watch.elapsed,
        lessThan(const Duration(seconds: 5)),
        reason: 'round $round',
      );
      await callEnded.future.timeout(const Duration(seconds: 5));
    }
  });

  Future<void> expectNoTimerLeftByTerminate({required bool dropFirst}) async {
    // The timers created by the channel, its connection and its calls.
    final List<Timer> timers = <Timer>[];
    await runZoned(
      () async {
        final ClientChannelBase channel = createGrpcChannel(
          host: InternetAddress.loopbackIPv4.address,
          port: proxy.port,
          sslEnabled: false,
        );
        _TestClient(channel).hang().listen((_) {}, onError: (Object _) {});
        // Wait for the call to be on the wire.
        await Future<void>.delayed(const Duration(milliseconds: 200));
        if (dropFirst) {
          _TestClient(channel).hang().listen((_) {}, onError: (Object _) {});
          await Future<void>.delayed(Duration.zero);
          proxy.drop();
        }
        await channel.terminate().timeout(const Duration(seconds: 5));
      },
      zoneSpecification: ZoneSpecification(
        createTimer:
            (
              Zone self,
              ZoneDelegate parent,
              Zone zone,
              Duration duration,
              void Function() callback,
            ) {
              final Timer timer = parent.createTimer(zone, duration, callback);
              timers.add(timer);
              return timer;
            },
      ),
    );
    // What the terminated connection still had to do is done by now.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(
      timers.where((Timer timer) => timer.isActive),
      isEmpty,
      reason: 'an active timer keeps the isolate alive after terminate',
    );
  }

  test('terminate with a call in flight leaves no timer behind', () async {
    await expectNoTimerLeftByTerminate(dropFirst: false);
  });

  test('terminate after the peer dropped the connection leaves no timer '
      'behind', () async {
    await expectNoTimerLeftByTerminate(dropFirst: true);
  });
}
