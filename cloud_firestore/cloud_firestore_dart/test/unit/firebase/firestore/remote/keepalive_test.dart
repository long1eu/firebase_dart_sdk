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
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/channel_options_provider.dart';
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

/// A tiny TCP proxy that can start black-holing traffic without closing any
/// socket, which looks like a half-dead connection to the client.
class _BlackholeProxy {
  _BlackholeProxy._(this._server);

  final ServerSocket _server;
  final List<Socket> _sockets = <Socket>[];
  bool blackhole = false;

  int get port => _server.port;

  static Future<_BlackholeProxy> start(int targetPort) async {
    final ServerSocket server = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final _BlackholeProxy proxy = _BlackholeProxy._(server);
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
          (Uint8List data) {
            if (!proxy.blackhole) {
              to.add(data);
            }
          },
          onError: (Object _) {},
          onDone: () => to.destroy(),
        );
      }

      pipe(client, upstream);
      pipe(upstream, client);
    });
    return proxy;
  }

  Future<void> close() async {
    for (Socket socket in _sockets) {
      socket.destroy();
    }
    await _server.close();
  }
}

class _TestClient extends Client {
  _TestClient(ClientChannelBase channel) : super(channel);

  static final ClientMethod<int, int> _hang = ClientMethod<int, int>(
    '/test.Hang/Hang',
    (int value) => <int>[value],
    (List<int> value) => value.isEmpty ? 0 : value.first,
  );

  ResponseStream<int> hang() =>
      $createStreamingCall(_hang, Stream<int>.value(1));
}

void main() {
  group('channel defaults', () {
    test('use the same keepalive as the Android SDK', () {
      // Android: ManagedChannelBuilder.keepAliveTime(30, SECONDS), grpc-java
      // defaults for the timeout (20 s) and for permitWithoutCalls (false).
      expect(ChannelOptionsProvider.defaultKeepAlivePingInterval,
          const Duration(seconds: 30));
      expect(ChannelOptionsProvider.defaultKeepAliveTimeout,
          const Duration(seconds: 20));
    });

    test('give up on connection attempts after 15 seconds', () {
      expect(ChannelOptionsProvider.defaultConnectTimeout,
          const Duration(seconds: 15));
    });

    test('the channel options carry the connect timeout and the credentials',
        () {
      final ChannelOptions secure =
          ChannelOptionsProvider.channelOptions(sslEnabled: true);
      final ChannelOptions insecure =
          ChannelOptionsProvider.channelOptions(sslEnabled: false);

      expect(secure.connectTimeout, const Duration(seconds: 15));
      expect(secure.credentials.isSecure, isTrue);
      expect(insecure.credentials.isSecure, isFalse);
    });
  });

  group('with a local server', () {
    const Duration pingInterval = Duration(milliseconds: 100);
    const Duration pingTimeout = Duration(milliseconds: 200);

    late Server server;
    late _BlackholeProxy proxy;
    late ClientChannelBase channel;
    final List<StreamSubscription<int>> subscriptions =
        <StreamSubscription<int>>[];

    StreamSubscription<int> hang(void Function(Object error) onError) {
      final StreamSubscription<int> subscription =
          _TestClient(channel).hang().listen((int _) {}, onError: onError);
      subscriptions.add(subscription);
      return subscription;
    }

    Future<void> start(
        ClientChannelBase Function(int port) createChannel) async {
      server = Server.create(services: <Service>[_HangService()]);
      await server.serve(address: InternetAddress.loopbackIPv4, port: 0);
      proxy = await _BlackholeProxy.start(server.port!);
      channel = createChannel(proxy.port);
    }

    ClientChannelBase firestoreChannel(int port) =>
        ChannelOptionsProvider.createChannel(
          host: '127.0.0.1',
          port: port,
          sslEnabled: false,
          keepAlivePingInterval: pingInterval,
          keepAliveTimeout: pingTimeout,
        );

    tearDown(() async {
      for (StreamSubscription<int> subscription in subscriptions) {
        await subscription.cancel();
      }
      subscriptions.clear();
      await channel.terminate();
      await proxy.close();
      await server.shutdown();
    });

    test('a half-dead connection is detected by the keepalive pings', () async {
      await start(firestoreChannel);

      final Completer<Object> failure = Completer<Object>();
      hang(failure.complete);

      // Let the call get established, then silently drop all traffic.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      proxy.blackhole = true;

      final Object error =
          await failure.future.timeout(const Duration(seconds: 5));
      // The connection is terminated, the calls fail with a gRPC error that is
      // not a permanent one, so the Firestore streams get re-established.
      expect(error, isA<GrpcError>());
      expect(<int>[StatusCode.unavailable, StatusCode.unknown],
          contains((error as GrpcError).code));
    });

    test('a healthy connection is not closed by the keepalive pings', () async {
      await start(firestoreChannel);

      Object? failure;
      hang((Object error) => failure = error);

      await Future<void>.delayed(const Duration(seconds: 1));

      expect(failure, isNull);
    });

    test('the channel reconnects after a dead connection was dropped',
        () async {
      await start(firestoreChannel);

      final Completer<Object> failure = Completer<Object>();
      hang(failure.complete);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      proxy.blackhole = true;
      await failure.future.timeout(const Duration(seconds: 5));

      // The network is back: a new call goes through a fresh connection.
      proxy.blackhole = false;
      Object? secondFailure;
      hang((Object error) => secondFailure = error);
      await Future<void>.delayed(const Duration(milliseconds: 600));

      expect(secondFailure, isNull);
    });

    test(
        'control: grpc\'s own ClientKeepAliveOptions only finish the connection '
        'gracefully, so a call that is in flight hangs', () async {
      Object? failure;
      // grpc leaves the ping future unhandled when the connection is
      // terminated: swallow that, it is not what is under test.
      await runZonedGuarded(() async {
        await start((int port) => ClientChannel(
              '127.0.0.1',
              port: port,
              options: const ChannelOptions(
                credentials: ChannelCredentials.insecure(),
                keepAlive: ClientKeepAliveOptions(
                  pingInterval: pingInterval,
                  timeout: pingTimeout,
                ),
              ),
            ));

        hang((Object error) => failure = error);
        await Future<void>.delayed(const Duration(milliseconds: 300));
        proxy.blackhole = true;
        await Future<void>.delayed(const Duration(seconds: 2));
        for (StreamSubscription<int> subscription in subscriptions) {
          await subscription.cancel();
        }
        await channel.terminate();
      }, (Object error, StackTrace stackTrace) {});

      expect(failure, isNull,
          reason: 'if grpc starts terminating dead connections, the custom '
              'KeepAliveTransportConnector is no longer needed');
    });
  });
}
