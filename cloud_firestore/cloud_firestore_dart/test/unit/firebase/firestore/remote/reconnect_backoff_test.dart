// A backend that accepts connections and then lets the client down (closes
// them, or sends GOAWAY) must not make the client reconnect in a tight loop:
// the attempts have to follow the exponential backoff of the streams.
//
// Before the fix in KeepAliveTransportConnector, package:grpc kept the calls
// that were waiting for a connection and connected again at once, about 43
// times per second (1300 connections in 30 seconds), in every variant below.

import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/database_info.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/channel_options_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/datastore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/keep_alive_transport.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/web/web_channel_transport.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/firestore.pbgrpc.dart'
    as proto;
import 'package:firebase_app_dart/internal.dart' show InternalLogLevel;
import 'package:grpc/grpc.dart';
import 'package:test/test.dart';

import '../../../../util/integration_test_util.dart';
import '../../../../util/io_web_http_client.dart';
import '../../../../util/misbehaving_server.dart';
import '../../../../util/self_signed_certificate.dart';

/// How long the client is left alone with the server. 30 seconds with
/// `RECONNECT_OUTAGE_SECONDS=30`.
final Duration outage = Duration(
  seconds: int.parse(Platform.environment['RECONNECT_OUTAGE_SECONDS'] ?? '10'),
);

/// The most attempts one stream can make in [duration]: its backoff starts at
/// 1 second and grows by 1.5, and the jitter can halve every delay.
int maxAttemptsOfOneStream(Duration duration) {
  int attempts = 1;
  double base = 1;
  double elapsed = 0;
  while (true) {
    elapsed += base / 2;
    if (elapsed > duration.inMilliseconds / 1000) {
      return attempts;
    }
    attempts++;
    base = base * 1.5 > 60 ? 60 : base * 1.5;
  }
}

/// A backend that answers every Listen call with one empty response.
class _FakeFirestoreService extends proto.FirestoreServiceBase {
  @override
  Stream<proto.ListenResponse> listen(
    ServiceCall call,
    Stream<proto.ListenRequest> request,
  ) async* {
    // The requests are read (the client of these tests ends them at once): a
    // server connection that terminates with unread messages of a stream fails
    // an assertion of package:http2 (ConnectionMessageQueueIn.onTerminated,
    // '_stream2messageQueue.isEmpty'), about one run in 50 when the server
    // shuts down.
    await request.drain<void>();
    yield proto.ListenResponse();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw const GrpcError.unimplemented();
}

void main() {
  IntegrationTestUtil.currentDatabasePath = 'unit/reconnect_backoff';

  tearDown(IntegrationTestUtil.tearDown);

  group('a whole client', () {
    /// Runs a client with a listener and a pending write against a server
    /// with [misbehavior] for [outage] and returns the server.
    Future<MisbehavingServer> runAgainst(Misbehavior misbehavior) async {
      final MisbehavingServer server = await MisbehavingServer.start(
        misbehavior,
      );
      addTearDown(server.close);
      final Firestore db = await IntegrationTestUtil.testFirestoreInstance(
        'reconnect-backoff',
        InternalLogLevel.w,
        FirestoreSettings(
          host: server.host,
          port: server.port,
          sslEnabled: false,
        ),
        IntegrationTestUtil.currentDatabasePath,
      );
      final StreamSubscription<QuerySnapshot<Map<String, Object?>>>
      subscription = db
          .collection('coll')
          .snapshots
          .listen((_) {}, onError: (Object _) {});
      addTearDown(subscription.cancel);
      // Both streams are in use.
      unawaited(
        db
            .collection('coll')
            .doc('doc')
            .set(<String, Object?>{'a': 1})
            .catchError((Object _) {}),
      );

      await Future<void>.delayed(outage);
      return server;
    }

    test(
      'backs off in every way a server can let it down',
      () async {
        // The variants run at the same time, each with its own client.
        final List<MisbehavingServer> servers =
            await Future.wait(<Future<MisbehavingServer>>[
              runAgainst(Misbehavior.closeAtOnce),
              runAgainst(Misbehavior.closeAfterPreface),
              runAgainst(Misbehavior.goAwayAtOnce),
            ]);

        // The listen and the write stream back off independently.
        final int bound = 2 * maxAttemptsOfOneStream(outage) + 4;
        for (final MisbehavingServer server in servers) {
          // ignore: avoid_print
          print(
            '${server.misbehavior.name}: ${server.connections} connections '
            'in ${outage.inSeconds} s (at most $bound allowed), longest gap '
            '${server.longestGap.inMilliseconds} ms',
          );
          expect(
            server.connections,
            greaterThan(1),
            reason: '${server.misbehavior.name}: the client keeps trying',
          );
          expect(
            server.connections,
            lessThanOrEqualTo(bound),
            reason:
                '${server.misbehavior.name}: the attempts follow the '
                'backoff of the streams',
          );
          // The delays grow: the client is not trying at a constant pace.
          expect(
            server.longestGap,
            greaterThan(const Duration(seconds: 1)),
            reason: server.misbehavior.name,
          );
        }
      },
      timeout: Timeout(outage + const Duration(seconds: 30)),
    );
  });

  group('the channel', () {
    late KeepAliveTransportConnector connector;
    late ClientTransportConnectorChannel channel;

    /// With [certificate] the connection uses TLS and trusts only that
    /// (self-signed) certificate.
    void connectTo(
      String host,
      int port, {
      SelfSignedCertificate? certificate,
    }) {
      final ChannelCredentials credentials = certificate != null
          ? ChannelCredentials.secure(
              certificates: certificate.certificate,
              authority: 'localhost',
            )
          : const ChannelCredentials.insecure();
      connector = KeepAliveTransportConnector(
        host: host,
        port: port,
        credentials: credentials,
        pingInterval: const Duration(seconds: 30),
        pingTimeout: const Duration(seconds: 20),
        connectTimeout: const Duration(seconds: 5),
      );
      channel = ClientTransportConnectorChannel(
        connector,
        options: ChannelOptions(credentials: credentials),
      );
      addTearDown(() => channel.terminate());
    }

    /// The responses of a Listen call on [channel].
    Future<List<proto.ListenResponse>> listen() async {
      final StreamController<proto.ListenRequest> requests =
          StreamController<proto.ListenRequest>();
      // The call ends when the requests end.
      unawaited(requests.close());
      return proto.FirestoreClient(
        channel,
      ).listen(requests.stream).toList().timeout(const Duration(seconds: 10));
    }

    /// The error of a Listen call on [channel].
    Future<GrpcError> listenFails() async {
      try {
        await listen();
      } on GrpcError catch (e) {
        return e;
      }
      fail('The call did not fail');
    }

    for (final Misbehavior misbehavior in Misbehavior.values) {
      test(
        'fails the waiting call instead of reconnecting: ${misbehavior.name}',
        () async {
          // The certificate and its key are made here, with openssl.
          SelfSignedCertificate? certificate;
          if (misbehavior == Misbehavior.closeAfterTlsHandshake) {
            certificate = SelfSignedCertificate.create(
              'localhost',
              ips: <String>['127.0.0.1'],
            );
            addTearDown(certificate.delete);
          }
          final MisbehavingServer server = await MisbehavingServer.start(
            misbehavior,
            certificate: certificate,
          );
          addTearDown(server.close);
          connectTo(server.host, server.port, certificate: certificate);

          final GrpcError error = await listenFails();
          expect(error.code, StatusCode.unavailable);
          expect(connector.connectionsOpened, 1);
          expect(connector.attemptsFailedFast, 1);

          // Nothing reconnects by itself.
          await Future<void>.delayed(const Duration(seconds: 1));
          expect(server.connections, 1);

          // A new call (a stream that is retried after its backoff) connects
          // again: every attempt of the caller is one connection.
          await listenFails();
          expect(connector.connectionsOpened, 2);
          expect(server.connections, 2);
        },
        skip: misbehavior == Misbehavior.closeAfterTlsHandshake
            ? SelfSignedCertificate.unavailableReason
            : null,
      );
    }

    test('connects again at once after a connection that worked', () async {
      Future<Server> serve(int port) async {
        final Server server = Server.create(
          services: <Service>[_FakeFirestoreService()],
        );
        await server.serve(address: InternetAddress.loopbackIPv4, port: port);
        return server;
      }

      Server server = await serve(0);
      final int port = server.port!;
      connectTo('127.0.0.1', port);

      // The backend answers: the connection works.
      expect(await listen(), hasLength(1));
      expect(connector.connectionsOpened, 1);

      // The backend restarts right away.
      await server.shutdown();
      // Once the client saw its connection end: a call started before that
      // goes out on the old connection, which refuses it with a GOAWAY that
      // package:grpc reports as UNKNOWN instead of retrying the call on a new
      // connection (about one run in 150).
      await connector.done.timeout(const Duration(seconds: 5));
      server = await serve(port);
      addTearDown(() => server.shutdown());

      expect(
        await listen(),
        hasLength(1),
        reason: 'the call reached the restarted backend',
      );
      expect(connector.connectionsOpened, 2);
      expect(connector.attemptsFailedFast, 0);
    });

    test('a connection that is refused is not affected', () async {
      // A port on which nothing listens.
      final ServerSocket socket = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final int port = socket.port;
      await socket.close();
      connectTo('127.0.0.1', port);

      expect((await listenFails()).code, StatusCode.unavailable);
      expect((await listenFails()).code, StatusCode.unavailable);
      expect(connector.connectionsOpened, 0);
      expect(connector.attemptsFailedFast, 0);
    });
  });

  group('the web transport', () {
    // The same exposure on the web: a proxy or a captive portal that answers
    // every request of the WebChannel at once, with something useless.
    tearDown(() => Datastore.transportOverride = null);

    /// Runs a client on the web transport, with a listener and a pending
    /// write, for [outage] against an HTTP server that answers every request
    /// with [answer], and returns the times of the requests by path.
    Future<Map<String, List<Duration>>> runAgainst(
      void Function(HttpRequest request) answer,
    ) async {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => server.close(force: true));
      final Stopwatch stopwatch = Stopwatch()..start();
      final Map<String, List<Duration>> requests = <String, List<Duration>>{};
      server.listen((HttpRequest request) {
        final String rpc = request.uri.pathSegments.firstWhere(
          (String s) => s == 'Listen' || s == 'Write',
          orElse: () => request.uri.path,
        );
        requests.putIfAbsent(rpc, () => <Duration>[]).add(stopwatch.elapsed);
        answer(request);
      });

      Datastore.transportOverride =
          (DatabaseInfo databaseInfo, ChannelOptionsProvider options) =>
              WebChannelTransport(IoWebHttpClient(), databaseInfo, options);
      final Firestore db = await IntegrationTestUtil.testFirestoreInstance(
        'reconnect-backoff',
        InternalLogLevel.w,
        FirestoreSettings(
          host: '127.0.0.1',
          port: server.port,
          sslEnabled: false,
        ),
        IntegrationTestUtil.currentDatabasePath,
      );
      final StreamSubscription<QuerySnapshot<Map<String, Object?>>>
      subscription = db
          .collection('coll')
          .snapshots
          .listen((_) {}, onError: (Object _) {});
      addTearDown(subscription.cancel);
      unawaited(
        db
            .collection('coll')
            .doc('doc')
            .set(<String, Object?>{'a': 1})
            .catchError((Object _) {}),
      );

      await Future<void>.delayed(outage);
      return requests;
    }

    final Map<String, void Function(HttpRequest)> answers =
        <String, void Function(HttpRequest)>{
          'an empty 200': (HttpRequest request) => request.response.close(),
          'a 500': (HttpRequest request) {
            request.response.statusCode = HttpStatus.internalServerError;
            unawaited(request.response.close());
          },
          'a 200 that is not a WebChannel': (HttpRequest request) {
            request.response
              ..headers.contentType = ContentType.html
              ..write('<html><body>Please log in to the Wi-Fi</body></html>');
            unawaited(request.response.close());
          },
          'a connection that is closed': (HttpRequest request) {
            unawaited(
              request.response
                  .detachSocket(writeHeaders: false)
                  .then(
                    (Socket socket) => socket.destroy(),
                    onError: (Object _) {},
                  ),
            );
          },
        };

    test(
      'backs off whatever useless answer every request gets',
      () async {
        // The variants run at the same time, each with its own client.
        final List<Map<String, List<Duration>>> results = await Future.wait(
          answers.values.map(runAgainst),
        );
        final int bound = maxAttemptsOfOneStream(outage) + 4;
        for (int i = 0; i < results.length; i++) {
          final String name = answers.keys.elementAt(i);
          final Map<String, List<Duration>> requests = results[i];
          // ignore: avoid_print
          print(
            'web, $name: ${<String, int>{for (final MapEntry<String, List<Duration>> e in requests.entries) e.key: e.value.length}} requests in ${outage.inSeconds} s (at most $bound per stream)',
          );
          expect(
            requests.keys,
            containsAll(<String>['Listen', 'Write']),
            reason: name,
          );
          for (final MapEntry<String, List<Duration>> entry
              in requests.entries) {
            expect(
              entry.value.length,
              greaterThan(1),
              reason: '$name, ${entry.key}: the client keeps trying',
            );
            expect(
              entry.value.length,
              lessThanOrEqualTo(bound),
              reason: '$name, ${entry.key}: the attempts follow the backoff',
            );
          }
        }
      },
      timeout: Timeout(outage + const Duration(seconds: 30)),
    );
  });
}
