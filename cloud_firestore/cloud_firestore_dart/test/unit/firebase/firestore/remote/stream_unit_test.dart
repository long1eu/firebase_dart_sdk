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

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/empty_credentials_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_purpose.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/channel_options_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/datastore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/watch_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/timer_task.dart';
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;
import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart' hide ResponseStream;
import 'package:test/test.dart';

import '../../../../util/test_util.dart' as util;
import 'unused_transport.dart';

// ignore_for_file: close_sinks

/// Unit tests for [WatchStream] and [WriteStream] against a fake gRPC client
/// (no emulator): requests sent, responses decoded into stream events and the
/// open / stop life cycle. Upstream tests these through the emulator-backed
/// StreamTest (which the Dart port has as an integration test).
class _FakeResponse implements Response {
  @override
  Future<Map<String, String>> get headers =>
      Future<Map<String, String>>.value(<String, String>{});

  @override
  Future<Map<String, String>> get trailers =>
      Future<Map<String, String>>.value(<String, String>{});

  @override
  Future<void> cancel() async {}
}

class _FakeClient extends FirestoreClient {
  _FakeClient()
      : super(
          UnusedTransport(),
          ChannelOptionsProvider(
            databaseId: DatabaseId.forProject('p'),
            credentialsProvider: EmptyCredentialsProvider(),
          ),
        );

  final List<proto.WriteRequest> writeRequests = <proto.WriteRequest>[];
  final List<proto.ListenRequest> listenRequests = <proto.ListenRequest>[];
  final StreamController<proto.WriteResponse> writeResponses =
      StreamController<proto.WriteResponse>();
  final StreamController<proto.ListenResponse> listenResponses =
      StreamController<proto.ListenResponse>();

  /// When set, the listen call reports its connection through
  /// [ResponseStream.connected], as the WebChannel transport does.
  Completer<void>? listenConnected;

  @override
  Future<ResponseStream<proto.WriteResponse>> write(
      Stream<proto.WriteRequest> request) async {
    request.listen(writeRequests.add);
    return ResponseStream<proto.WriteResponse>(
        _FakeResponse(), writeResponses.stream);
  }

  @override
  Future<ResponseStream<proto.ListenResponse>> listen(
      Stream<proto.ListenRequest> request) async {
    request.listen(listenRequests.add);
    return ResponseStream<proto.ListenResponse>(
        _FakeResponse(), listenResponses.stream,
        connected: listenConnected?.future);
  }
}

Future<void> pump() => Future<void>.delayed(Duration.zero);

void main() {
  final DatabaseId databaseId = DatabaseId.forProject('p');
  late TaskScheduler scheduler;
  late _FakeClient client;
  late RemoteSerializer serializer;

  setUp(() {
    scheduler = TaskScheduler('stream-unit');
    client = _FakeClient();
    serializer = RemoteSerializer(databaseId);
  });

  group('WatchStream', () {
    late WatchStream stream;
    late List<StreamEvent> events;

    setUp(() {
      stream = WatchStream(
          client: client, scheduler: scheduler, serializer: serializer);
      events = <StreamEvent>[];
      stream.listen(events.add);
    });

    tearDown(() async {
      await stream.stop();
      await client.listenResponses.close();
    });

    test('start opens the stream and raises an OpenEvent', () async {
      expect(stream.isStarted, isFalse);
      await stream.start();
      await pump();

      expect(stream.isStarted, isTrue);
      expect(stream.isOpen, isTrue);
      expect(events.single, isA<OpenEvent>());
    });

    test('watchQuery sends an add-target request with the listen label',
        () async {
      await stream.start();
      final QueryData data = util.queryData(4, QueryPurpose.listen, 'rooms');
      stream.watchQuery(data);
      await pump();

      final proto.ListenRequest request = client.listenRequests.single;
      expect(request.database, 'projects/p/databases/(default)');
      expect(request.hasAddTarget(), isTrue);
      expect(request.addTarget.targetId, 4);
      expect(request.labels, isEmpty);
    });

    test('limbo resolution queries carry the limbo label', () async {
      await stream.start();
      stream.watchQuery(
          util.queryData(6, QueryPurpose.limboResolution, 'rooms/a'));
      await pump();

      expect(client.listenRequests.single.labels['goog-listen-tags'],
          'limbo-document');
    });

    test('unwatchTarget sends a remove-target request', () async {
      await stream.start();
      stream.unwatchTarget(7);
      await pump();

      final proto.ListenRequest request = client.listenRequests.single;
      expect(request.hasRemoveTarget(), isTrue);
      expect(request.removeTarget, 7);
      expect(request.database, 'projects/p/databases/(default)');
    });

    test('responses are decoded into OnWatchChange events', () async {
      await stream.start();
      client.listenResponses.add(proto.ListenResponse(
        targetChange: proto.TargetChange(
          targetChangeType: proto.TargetChange_TargetChangeType.CURRENT,
          targetIds: <int>[2],
          resumeToken: <int>[9, 9],
        ),
      ));
      await pump();

      final OnWatchChange change = events.whereType<OnWatchChange>().single;
      final WatchChangeWatchTargetChange target =
          change.watchChange as WatchChangeWatchTargetChange;
      expect(target.changeType, WatchTargetChangeType.current);
      expect(target.targetIds, <int>[2]);
      expect(target.resumeToken, Uint8List.fromList(<int>[9, 9]));
      // A change for specific targets carries no global snapshot version.
      expect(change.snapshotVersion, SnapshotVersion.none);
    });

    // firebase-js-sdk #8145: the stream reports its connection before the
    // first message. Without a signal of the transport (gRPC) the first message
    // is the connection, as the JS gRPC connection emulates it.
    test('the first message raises a ConnectedEvent before the change',
        () async {
      await stream.start();
      client.listenResponses.add(proto.ListenResponse(
        targetChange: proto.TargetChange(
          targetChangeType: proto.TargetChange_TargetChangeType.CURRENT,
          targetIds: <int>[2],
        ),
      ));
      client.listenResponses.add(proto.ListenResponse(
        targetChange: proto.TargetChange(
          targetChangeType: proto.TargetChange_TargetChangeType.NO_CHANGE,
          targetIds: <int>[2],
        ),
      ));
      await pump();

      expect(events, <Matcher>[
        isA<OpenEvent>(),
        isA<ConnectedEvent>(),
        isA<OnWatchChange>(),
        isA<OnWatchChange>(),
      ]);
    });

    test('a connection of the transport raises the ConnectedEvent, once',
        () async {
      client.listenConnected = Completer<void>();
      await stream.start();
      await pump();
      expect(events, <Matcher>[isA<OpenEvent>()]);

      // The WebChannel handshake succeeded: no message yet.
      client.listenConnected!.complete();
      await pump();
      expect(events, <Matcher>[isA<OpenEvent>(), isA<ConnectedEvent>()]);

      client.listenResponses.add(proto.ListenResponse(
        targetChange: proto.TargetChange(
          targetChangeType: proto.TargetChange_TargetChangeType.CURRENT,
          targetIds: <int>[2],
        ),
      ));
      await pump();
      expect(events.whereType<ConnectedEvent>(), hasLength(1));
      expect(events.last, isA<OnWatchChange>());
    });

    test('a connection after the stream stopped raises nothing', () async {
      client.listenConnected = Completer<void>();
      await stream.start();
      await stream.stop();
      client.listenConnected!.complete();
      await pump();
      expect(events.whereType<ConnectedEvent>(), isEmpty);
    });

    test('a global target change carries the read time as version', () async {
      await stream.start();
      client.listenResponses.add(proto.ListenResponse(
        targetChange: proto.TargetChange(
          readTime: proto.Timestamp(seconds: Int64(5)),
        ),
      ));
      await pump();

      final OnWatchChange change = events.whereType<OnWatchChange>().single;
      expect(change.snapshotVersion, util.version(5000000));
    });

    test('stop closes the stream without a CloseEvent error', () async {
      await stream.start();
      await stream.stop();
      await pump();

      expect(stream.isStarted, isFalse);
      expect(stream.isOpen, isFalse);
      final CloseEvent close = events.whereType<CloseEvent>().single;
      expect(close.error.code, StatusCode.ok);
    });

    test('a server error closes the stream and is no longer open', () async {
      await stream.start();
      client.listenResponses
          .addError(const GrpcError.unavailable('down'), StackTrace.current);
      await pump();
      await pump();

      final CloseEvent close = events.whereType<CloseEvent>().single;
      expect(close.error.code, StatusCode.unavailable);
      expect(stream.isOpen, isFalse);
    });
  });

  group('WriteStream', () {
    late WriteStream stream;
    late List<StreamEvent> events;

    setUp(() {
      stream = WriteStream(
          client: client, scheduler: scheduler, serializer: serializer);
      events = <StreamEvent>[];
      stream.listen(events.add);
    });

    tearDown(() async {
      scheduler.getTask(TaskId.writeStreamIdle)?.cancel();
      await stream.stop();
      await client.writeResponses.close();
    });

    test('start opens the stream and resets the handshake', () async {
      stream.handshakeComplete = true;
      await stream.start();
      await pump();

      expect(stream.isOpen, isTrue);
      expect(stream.handshakeComplete, isFalse);
      expect(events.single, isA<OpenEvent>());
    });

    test('writeHandshake sends only the database name', () async {
      await stream.start();
      stream.writeHandshake();
      await pump();

      final proto.WriteRequest request = client.writeRequests.single;
      expect(request.database, 'projects/p/databases/(default)');
      expect(request.writes, isEmpty);
      expect(request.streamToken, isEmpty);
    });

    test('the first response completes the handshake and stores the token',
        () async {
      await stream.start();
      stream.writeHandshake();
      client.writeResponses
          .add(proto.WriteResponse(streamToken: <int>[1, 2, 3]));
      await pump();

      expect(stream.handshakeComplete, isTrue);
      expect(stream.lastStreamToken, <int>[1, 2, 3]);
      expect(events.whereType<HandshakeCompleteEvent>(), hasLength(1));
      expect(events.whereType<OnWriteResponse>(), isEmpty);
    });

    test('writeMutations sends the encoded writes with the last token',
        () async {
      await stream.start();
      stream.writeHandshake();
      client.writeResponses.add(proto.WriteResponse(streamToken: <int>[4, 5]));
      await pump();

      final Mutation mutation =
          util.setMutation('rooms/eros', <String, Object?>{'a': 1});
      stream.writeMutations(<Mutation>[mutation]);
      await pump();

      final proto.WriteRequest request = client.writeRequests.last;
      expect(request.streamToken, <int>[4, 5]);
      expect(
          request.writes, <proto.Write>[serializer.encodeMutation(mutation)]);
      // The handshake request has no database in later requests.
      expect(request.database, isEmpty);
    });

    test('later responses are decoded into an OnWriteResponse', () async {
      await stream.start();
      stream.writeHandshake();
      client.writeResponses.add(proto.WriteResponse(streamToken: <int>[1]));
      await pump();

      client.writeResponses.add(proto.WriteResponse(
        streamToken: <int>[2],
        commitTime: proto.Timestamp(seconds: Int64(5)),
        writeResults: <proto.WriteResult>[
          proto.WriteResult(updateTime: proto.Timestamp(seconds: Int64(5))),
          proto.WriteResult(),
        ],
      ));
      await pump();

      final OnWriteResponse response =
          events.whereType<OnWriteResponse>().single;
      expect(response.version, util.version(5000000));
      expect(response.results.length, 2);
      expect(response.results[0].version, util.version(5000000));
      // Results without an update time (deletes) use the commit version.
      expect(response.results[1].version, util.version(5000000));
      expect(stream.lastStreamToken, <int>[2]);
    });

    test(
        'stop with a completed handshake flushes the token with an empty write',
        () async {
      await stream.start();
      stream.writeHandshake();
      client.writeResponses.add(proto.WriteResponse(streamToken: <int>[8]));
      await pump();

      await stream.stop();
      await pump();

      final proto.WriteRequest last = client.writeRequests.last;
      expect(last.writes, isEmpty);
      expect(last.streamToken, <int>[8]);
      expect(events.whereType<CloseEvent>().single.error.code, StatusCode.ok);
    });

    test('stop while in backoff after a failed run does not write', () async {
      await stream.start();
      stream.writeHandshake();
      client.writeResponses.add(proto.WriteResponse(streamToken: <int>[8]));
      await pump();
      expect(stream.handshakeComplete, isTrue);
      final int requestsBefore = client.writeRequests.length;

      client.writeResponses.addError(const GrpcError.unavailable('down'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(stream.isOpen, isFalse);
      // Starting a stream that closed with an error waits for the backoff.
      await stream.start();
      expect(stream.isStarted, isTrue, reason: 'waiting for the backoff');
      expect(stream.handshakeComplete, isFalse,
          reason: 'start resets the handshake of the failed run');

      await stream.stop();
      await pump();

      expect(stream.isStarted, isFalse);
      expect(client.writeRequests.length, requestsBefore);
    });

    test('stop without handshake sends nothing', () async {
      await stream.start();
      await stream.stop();
      await pump();

      expect(client.writeRequests, isEmpty);
      expect(stream.isStarted, isFalse);
    });
  });
}
