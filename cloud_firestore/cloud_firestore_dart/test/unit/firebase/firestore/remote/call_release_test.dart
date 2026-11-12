import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/empty_credentials_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/call_release.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/channel_options_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/datastore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/timer_task.dart';
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;
import 'package:grpc/grpc.dart' hide ResponseStream;
import 'package:test/test.dart';

import 'unused_transport.dart';

// ignore_for_file: close_sinks

const Duration grace = Duration(milliseconds: 200);

Future<void> afterGrace() =>
    Future<void>.delayed(grace + const Duration(milliseconds: 200));

Future<void> pump() => Future<void>.delayed(Duration.zero);

class _FakeResponse implements Response {
  int cancelCount = 0;

  @override
  Future<Map<String, String>> get headers =>
      Future<Map<String, String>>.value(<String, String>{});

  @override
  Future<Map<String, String>> get trailers =>
      Future<Map<String, String>>.value(<String, String>{});

  @override
  Future<void> cancel() async {
    cancelCount++;
  }
}

/// A fake Write call: records the requests, whether the client closed its
/// side, and whether the call was cancelled.
class _FakeClient extends FirestoreClient {
  _FakeClient()
      : super(
          UnusedTransport(),
          ChannelOptionsProvider(
            databaseId: DatabaseId.forProject('p'),
            credentialsProvider: EmptyCredentialsProvider(),
          ),
          callReleaser: CallReleaser(gracePeriod: grace),
        );

  final List<proto.WriteRequest> requests = <proto.WriteRequest>[];
  bool requestsClosed = false;
  final _FakeResponse call = _FakeResponse();
  StreamController<proto.WriteResponse> responses =
      StreamController<proto.WriteResponse>();

  @override
  Future<ResponseStream<proto.WriteResponse>> write(
      Stream<proto.WriteRequest> request) async {
    request.listen(requests.add, onDone: () => requestsClosed = true);
    return ResponseStream<proto.WriteResponse>(call, responses.stream);
  }
}

void main() {
  group('CallReleaser', () {
    late CallReleaser releaser;
    late StreamController<int> responses;
    late int cancelCount;

    Future<void> cancel() async {
      cancelCount++;
    }

    setUp(() {
      releaser = CallReleaser(gracePeriod: grace);
      responses = StreamController<int>();
      cancelCount = 0;
    });

    test('a released call that closes by itself is never cancelled', () async {
      final List<int> seen = <int>[];
      final StreamSubscription<int> subscription =
          responses.stream.listen(seen.add);
      responses.add(1);
      await pump();

      releaser.release(subscription, cancel);
      expect(releaser.pendingCount, 1);
      // What the call still delivers is ignored.
      responses.add(2);
      await responses.close();
      await pump();
      expect(releaser.pendingCount, 0);

      await afterGrace();
      expect(seen, <int>[1]);
      expect(cancelCount, 0);
    });

    test('a released call that fails is never cancelled', () async {
      final StreamSubscription<int> subscription =
          responses.stream.listen((int _) {});
      releaser.release(subscription, cancel);
      responses.addError(const GrpcError.unavailable());
      await pump();

      expect(releaser.pendingCount, 0);
      await afterGrace();
      expect(cancelCount, 0);
    });

    test('a released call that stays open is cancelled after the grace period',
        () async {
      final StreamSubscription<int> subscription =
          responses.stream.listen((int _) {});
      releaser.release(subscription, cancel);

      await pump();
      expect(cancelCount, 0);
      await afterGrace();
      expect(cancelCount, 1);
      expect(responses.hasListener, isFalse);
      expect(releaser.pendingCount, 0);
    });

    test('cancelAll cancels the released calls right away, once', () async {
      final StreamSubscription<int> subscription =
          responses.stream.listen((int _) {});
      releaser.release(subscription, cancel);

      releaser.cancelAll();
      expect(cancelCount, 1);
      expect(releaser.pendingCount, 0);
      await afterGrace();
      expect(cancelCount, 1);
    });

    test('first returns the first response without cancelling the call',
        () async {
      final Future<int> first = releaser.first(responses.stream, cancel);
      responses.add(7);
      expect(await first, 7);
      expect(cancelCount, 0);

      await responses.close();
      await afterGrace();
      expect(cancelCount, 0);
    });

    test('first reports the error of the call', () async {
      final Future<int> first = releaser.first(responses.stream, cancel);
      responses.addError(const GrpcError.permissionDenied('no'));
      await expectLater(first, throwsA(isA<GrpcError>()));
    });

    test('first throws a StateError when the call ends without a response',
        () async {
      final Future<int> first = releaser.first(responses.stream, cancel);
      await responses.close();
      await expectLater(first, throwsStateError);
    });
  });

  group('a stream stopped by the client', () {
    late _FakeClient client;
    late WriteStream stream;
    late List<StreamEvent> events;

    setUp(() async {
      client = _FakeClient();
      stream = WriteStream(
        client: client,
        scheduler: TaskScheduler('call-release'),
        serializer: RemoteSerializer(DatabaseId.forProject('p')),
      );
      events = <StreamEvent>[];
      stream.listen(events.add);
      await stream.start();
      stream.writeHandshake();
      client.responses.add(proto.WriteResponse()
        ..streamToken = Uint8List.fromList(<int>[1]));
      await pump();
      expect(stream.handshakeComplete, isTrue);
    });

    test('half-closes its call and leaves it to the backend to finish',
        () async {
      await stream.stop();
      await pump();

      // The final (empty) write tells the backend that the stream closes.
      expect(client.requests.last.writes, isEmpty);
      expect(client.requests.last.streamToken, <int>[1]);
      expect(client.requestsClosed, isTrue);
      expect(client.call.cancelCount, 0);
      expect(events.last, isA<CloseEvent>());

      // The backend finishes the call: nothing is cancelled and nothing of
      // the old call reaches the listener.
      final int eventCount = events.length;
      client.responses.add(proto.WriteResponse()
        ..streamToken = Uint8List.fromList(<int>[2]));
      await client.responses.close();
      await afterGrace();
      expect(client.call.cancelCount, 0);
      expect(events.length, eventCount);
      expect(stream.lastStreamToken, <int>[1]);
    });

    test('cancels its call when the backend keeps it open', () async {
      await stream.stop();
      expect(client.call.cancelCount, 0);
      await afterGrace();
      expect(client.call.cancelCount, 1);
    });

    test('can be started again while the old call is still closing', () async {
      await stream.stop();
      client.responses = StreamController<proto.WriteResponse>();
      await stream.start();
      await pump();

      expect(stream.isOpen, isTrue);
      stream.writeHandshake();
      client.responses.add(proto.WriteResponse()
        ..streamToken = Uint8List.fromList(<int>[3]));
      await pump();
      expect(stream.handshakeComplete, isTrue);
      await stream.stop();
    });

    test('a stream that failed still cancels its call', () async {
      client.responses.addError(const GrpcError.unavailable());
      await pump();
      expect(events.whereType<CloseEvent>(), hasLength(1));
      expect(client.call.cancelCount, 1);
    });
  });
}
