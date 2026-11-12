import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/empty_credentials_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/database_info.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/channel_options_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/datastore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/grpc_transport.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/timer_task.dart';
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;
import 'package:grpc/grpc.dart';
import 'package:test/test.dart';

/// Returns a local port nothing listens on.
Future<int> closedPort() async {
  final ServerSocket socket = await ServerSocket.bind('127.0.0.1', 0);
  final int port = socket.port;
  await socket.close();
  return port;
}

/// A Listen endpoint that either finishes the call right away (clean close with
/// status OK) or keeps it open until the client goes away.
class _ListenService extends Service {
  _ListenService(this.closeImmediately) {
    $addMethod(ServiceMethod<proto.ListenRequest, proto.ListenResponse>(
      'Listen',
      _listen,
      true,
      true,
      proto.ListenRequest.fromBuffer,
      (proto.ListenResponse v) => v.writeToBuffer(),
    ));
  }

  final bool closeImmediately;

  Stream<proto.ListenResponse> _listen(
      ServiceCall call, Stream<proto.ListenRequest> requests) async* {
    if (closeImmediately) {
      return;
    }
    await for (final proto.ListenRequest _ in requests) {}
  }

  @override
  String get $name => 'google.firestore.v1.Firestore';
}

Future<(Server, Datastore, ClientChannel)> serve(bool closeImmediately) async {
  final Server server =
      Server.create(services: <Service>[_ListenService(closeImmediately)]);
  await server.serve(address: '127.0.0.1', port: 0);
  final ClientChannel channel = ClientChannel('127.0.0.1',
      port: server.port!,
      options:
          const ChannelOptions(credentials: ChannelCredentials.insecure()));
  final Datastore datastore = Datastore(
    TaskScheduler(''),
    DatabaseInfo(DatabaseId.forDatabase('p', '(default)'), 'key', '127.0.0.1',
        sslEnabled: false, port: server.port!),
    EmptyCredentialsProvider(),
    transportFactory: (ChannelOptionsProvider options) =>
        GrpcTransport(channel, options),
  );
  return (server, datastore, channel);
}

void main() {
  test('a clean close by the server is reported as a stream close', () async {
    final (Server server, Datastore datastore, ClientChannel channel) =
        await serve(true);
    try {
      final WatchStream stream = datastore.watchStream;
      final Future<StreamEvent> close =
          stream.where((StreamEvent e) => e is CloseEvent).first;
      await stream.start();
      final CloseEvent event =
          await close.timeout(const Duration(seconds: 5)) as CloseEvent;
      expect(event.error.code, isNot(StatusCode.ok));
      expect(stream.isOpen, isFalse);
      expect(stream.isStarted, isFalse,
          reason: 'error state, awaiting restart');
    } finally {
      await channel.terminate();
      await server.shutdown();
    }
  });

  test('start() while a stop() is still releasing the call is safe', () async {
    final (Server server, Datastore datastore, ClientChannel channel) =
        await serve(false);
    try {
      final WatchStream stream = datastore.watchStream;
      final List<StreamEvent> events = <StreamEvent>[];
      stream.listen(events.add);
      await stream.start();
      expect(stream.isOpen, isTrue);

      final Future<void> stopped = stream.stop();
      // stop() flips the state synchronously: a caller may now start again.
      expect(stream.isStarted, isFalse);
      await stream.start();
      await stopped;

      expect(stream.isOpen, isTrue, reason: 'the new call must stay open');
      stream.writeRequest(proto.ListenRequest());
      await stream.stop();
      expect(stream.isStarted, isFalse);
      expect(events.whereType<CloseEvent>(), hasLength(1));
    } finally {
      await channel.terminate();
      await server.shutdown();
    }
  });

  late ClientChannel channel;
  late Datastore datastore;

  setUp(() async {
    final int port = await closedPort();
    channel = ClientChannel('127.0.0.1',
        port: port,
        options:
            const ChannelOptions(credentials: ChannelCredentials.insecure()));
    datastore = Datastore(
      TaskScheduler(''),
      DatabaseInfo(DatabaseId.forDatabase('p', '(default)'), 'key', '127.0.0.1',
          sslEnabled: false, port: port),
      EmptyCredentialsProvider(),
      transportFactory: (ChannelOptionsProvider options) =>
          GrpcTransport(channel, options),
    );
  });

  tearDown(() async {
    await channel.terminate();
  });

  // A failed connection must surface as a stream close with an error (so the
  // backoff and the online state tracking kick in) instead of hanging start().
  test('watch stream start returns and reports UNAVAILABLE when unreachable',
      () async {
    final WatchStream stream = datastore.watchStream;
    final Future<StreamEvent> close =
        stream.where((StreamEvent e) => e is CloseEvent).first;

    await stream.start().timeout(const Duration(seconds: 2));

    final CloseEvent event =
        await close.timeout(const Duration(seconds: 5)) as CloseEvent;
    expect(event.error.code, StatusCode.unavailable);
    await stream.stop();
  });

  test('write stream start returns and reports UNAVAILABLE when unreachable',
      () async {
    final WriteStream stream = datastore.writeStream;
    final Future<StreamEvent> close =
        stream.where((StreamEvent e) => e is CloseEvent).first;

    await stream.start().timeout(const Duration(seconds: 2));

    final CloseEvent event =
        await close.timeout(const Duration(seconds: 5)) as CloseEvent;
    expect(event.error.code, StatusCode.unavailable);
    await stream.stop();
  });
}
