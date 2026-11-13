// A rejected token (UNAUTHENTICATED) is invalidated by the listen and write
// streams only while they are not healthy (open for less than 10 seconds), as
// in the Android and JS SDKs; unary calls invalidate it on every
// UNAUTHENTICATED.

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/empty_credentials_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/channel_options_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/datastore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/firestore_transport.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/timer_task.dart';
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;
import 'package:grpc/grpc.dart' hide ResponseStream;
import 'package:protobuf/protobuf.dart';
import 'package:test/test.dart';

class _Credentials extends EmptyCredentialsProvider {
  int invalidations = 0;

  @override
  void invalidateToken() {
    invalidations++;
    super.invalidateToken();
  }
}

class _NoHeaders implements Response {
  @override
  Future<Map<String, String>> get headers async => <String, String>{};

  @override
  Future<Map<String, String>> get trailers async => <String, String>{};

  @override
  Future<void> cancel() async {}
}

/// Every call fails with [error] once the test calls [fail].
class _FailingTransport implements FirestoreTransport {
  final List<StreamController<Object>> calls = <StreamController<Object>>[];

  @override
  ResponseStream<Res> startCall<
    Req extends GeneratedMessage,
    Res extends GeneratedMessage
  >(FirestoreRpc<Req, Res> rpc, Stream<Req> requests, {CallOptions? options}) {
    requests.listen((_) {});
    final StreamController<Res> responses = StreamController<Res>();
    calls.add(responses as StreamController<Object>);
    return ResponseStream<Res>(_NoHeaders(), responses.stream);
  }

  void fail(GrpcError error) {
    for (final StreamController<Object> call in calls) {
      call.addError(error);
    }
    calls.clear();
  }

  @override
  Future<void> shutdown() async {}
}

Future<void> pump() => Future<void>.delayed(Duration.zero);

void main() {
  late _Credentials credentials;
  late _FailingTransport transport;
  late FirestoreClient client;
  late TaskScheduler scheduler;
  late WatchStream stream;
  late List<StreamEvent> events;

  setUp(() {
    credentials = _Credentials();
    transport = _FailingTransport();
    client = FirestoreClient(
      transport,
      ChannelOptionsProvider(
        databaseId: DatabaseId.forProject('p'),
        credentialsProvider: credentials,
      ),
    );
    scheduler = TaskScheduler('stream-token');
    stream = WatchStream(
      client: client,
      scheduler: scheduler,
      serializer: RemoteSerializer(DatabaseId.forProject('p')),
    );
    events = <StreamEvent>[];
    stream.listen(events.add);
  });

  tearDown(() => stream.stop());

  Future<GrpcError> failWith(GrpcError error) async {
    transport.fail(error);
    await pump();
    await pump();
    return events.whereType<CloseEvent>().single.error;
  }

  test('UNAUTHENTICATED before the stream is healthy invalidates the token '
      'once', () async {
    await stream.start();
    expect(stream.isOpen, isTrue);
    expect(scheduler.getTask(TaskId.listenStreamHealthCheck), isNotNull);

    final GrpcError error = await failWith(const GrpcError.unauthenticated());
    expect(error.code, StatusCode.unauthenticated);
    // Only by the stream: the client does not invalidate for the streams.
    expect(credentials.invalidations, 1);
    // The close cancels the health check.
    expect(scheduler.getTask(TaskId.listenStreamHealthCheck), isNull);
  });

  test('UNAUTHENTICATED once the stream is healthy keeps the token', () async {
    await stream.start();
    scheduler.runUntil(TaskId.listenStreamHealthCheck);
    expect(stream.isOpen, isTrue);
    expect(stream.isStarted, isTrue);

    await failWith(const GrpcError.unauthenticated());
    expect(credentials.invalidations, 0);
    expect(stream.isOpen, isFalse);
  });

  test('another error keeps the token', () async {
    await stream.start();
    await failWith(const GrpcError.unavailable());
    expect(credentials.invalidations, 0);
  });

  test('a unary call invalidates the token on UNAUTHENTICATED', () async {
    final Future<proto.CommitResponse> commit = client.commit(
      proto.CommitRequest(),
    );
    transport.fail(const GrpcError.unauthenticated());
    await expectLater(commit, throwsA(anything));
    expect(credentials.invalidations, 1);
  });
}
