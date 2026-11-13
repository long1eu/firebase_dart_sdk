// Review follow-up H1, the remaining client-side resets: calls that are read to their end (queries, commits) used to
// be cancelled when a response could not be used (a decoding error, a second commit response), and a stream call
// built after its stream was stopped was cancelled. Cancelling sends RST_STREAM; when it races the trailers of the
// call, package:http2 terminates the whole connection (see http2_reset_race_test.dart). They are now released.

import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/empty_credentials_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/call_release.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/channel_options_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/datastore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/firestore_transport.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/grpc_status.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/timer_task.dart';
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;
import 'package:protobuf/protobuf.dart';
import 'package:test/test.dart';

// ignore_for_file: close_sinks

const Duration grace = Duration(milliseconds: 200);

Future<void> afterGrace() =>
    Future<void>.delayed(grace + const Duration(milliseconds: 200));

Future<void> pump() => Future<void>.delayed(Duration.zero);

class _Call implements Response {
  _Call(this.rpc) {
    // As package:grpc: cancelling the subscription of the responses cancels the call.
    responses.onCancel = () {
      if (!responses.isClosed) {
        cancelCount++;
      }
    };
  }

  final String rpc;
  final StreamController<GeneratedMessage> responses =
      StreamController<GeneratedMessage>();

  /// Resets of the call: [cancel], or a cancelled subscription of a call that has not ended.
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

/// Every call is scripted by the test through [calls].
class _ScriptedTransport implements FirestoreTransport {
  final List<_Call> calls = <_Call>[];
  final StreamController<_Call> started = StreamController<_Call>.broadcast();

  @override
  ResponseStream<Res> startCall<
    Req extends GeneratedMessage,
    Res extends GeneratedMessage
  >(FirestoreRpc<Req, Res> rpc, Stream<Req> requests, {CallOptions? options}) {
    final _Call call = _Call(rpc.name);
    calls.add(call);
    started.add(call);
    requests.listen((_) {}, onError: (Object _) {});
    return ResponseStream<Res>(call, call.responses.stream.cast<Res>());
  }

  @override
  Future<void> shutdown() async {}
}

void main() {
  late _ScriptedTransport transport;
  late FirestoreClient client;
  final RemoteSerializer serializer = RemoteSerializer(
    DatabaseId.forProject('p'),
  );

  setUp(() {
    transport = _ScriptedTransport();
    client = FirestoreClient(
      transport,
      ChannelOptionsProvider(
        databaseId: DatabaseId.forProject('p'),
        credentialsProvider: EmptyCredentialsProvider(),
      ),
      callReleaser: CallReleaser(gracePeriod: grace),
    );
  });

  group('CallReleaser.forEach', () {
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

    test('passes every response and completes when the call ends', () async {
      final List<int> seen = <int>[];
      final Future<void> done = releaser.forEach(
        responses.stream,
        cancel,
        seen.add,
      );
      responses
        ..add(1)
        ..add(2);
      await responses.close();
      await done;
      expect(seen, <int>[1, 2]);
      expect(cancelCount, 0);
    });

    test('reports the error of the call', () async {
      final Future<void> done = releaser.forEach(
        responses.stream,
        cancel,
        (int _) {},
      );
      responses.addError(const GrpcError.permissionDenied('no'));
      await expectLater(done, throwsA(isA<GrpcError>()));
      expect(cancelCount, 0);
    });

    test('a response that can not be used fails it without cancelling a call '
        'that then ends', () async {
      final List<int> seen = <int>[];
      final Future<void> done = releaser.forEach(responses.stream, cancel, (
        int response,
      ) {
        if (response == 2) {
          throw const FormatException('undecodable');
        }
        seen.add(response);
      });
      responses
        ..add(1)
        ..add(2)
        ..add(3);
      await expectLater(done, throwsFormatException);
      await responses.close();
      await afterGrace();
      expect(seen, <int>[1]);
      expect(cancelCount, 0);
      expect(releaser.pendingCount, 0);
    });

    test('a call that stays open after such a response is cancelled after '
        'the grace period', () async {
      final Future<void> done = releaser.forEach(
        responses.stream,
        cancel,
        (int _) => throw StateError('bad'),
      );
      responses.add(1);
      await expectLater(done, throwsStateError);
      expect(cancelCount, 0);
      await afterGrace();
      expect(cancelCount, 1);
    });
  });

  test(
    'a commit with a second response fails without resetting the call',
    () async {
      final Future<proto.CommitResponse> commit = client.commit(
        proto.CommitRequest(),
      );
      final _Call call = transport.calls.single;
      call.responses
        ..add(proto.CommitResponse())
        ..add(proto.CommitResponse());
      await expectLater(
        commit,
        throwsA(
          isA<GrpcError>().having(
            (GrpcError e) => e.code,
            'code',
            StatusCode.unimplemented,
          ),
        ),
      );
      await call.responses.close();
      await afterGrace();
      expect(call.cancelCount, 0);
    },
  );

  test('a commit with one response still works', () async {
    final Future<proto.CommitResponse> commit = client.commit(
      proto.CommitRequest(),
    );
    final _Call call = transport.calls.single;
    call.responses.add(proto.CommitResponse()..commitTime = proto.Timestamp());
    await call.responses.close();
    expect((await commit).hasCommitTime(), isTrue);
    expect(call.cancelCount, 0);
  });

  test('a query in a transaction with an undecodable document fails without '
      'resetting the call', () async {
    final TransactionClient transactions = TransactionClient(
      client,
      serializer,
    );
    final Future<Object?> result = transactions.runQuery(
      Query(ResourcePath.fromString('coll')),
      Uint8List.fromList(<int>[1]),
    );
    final _Call call = transport.calls.single;
    call.responses
      // A document of another database can not be decoded.
      .add(
        proto.RunQueryResponse(
          document: proto.Document(
            name: 'projects/other/databases/(default)/documents/coll/a',
          ),
          readTime: proto.Timestamp(),
        ),
      );
    await expectLater(result, throwsA(anything));
    await call.responses.close();
    await afterGrace();
    expect(call.cancelCount, 0);
  });

  test('a stream call built after its stream was stopped is half-closed and '
      'released, not cancelled', () async {
    final WriteStream stream = WriteStream(
      client: client,
      scheduler: TaskScheduler('call-release-full-reads'),
      serializer: serializer,
    );
    stream.listen((_) {});
    // start() awaits the call; stop() runs before it is attached.
    final Future<void> starting = stream.start();
    final Future<void> stopping = stream.stop();
    await starting;
    await stopping;
    final _Call call = transport.calls.single;
    expect(call.cancelCount, 0);
    // The backend ends the call it got no requests for.
    await call.responses.close();
    await afterGrace();
    expect(call.cancelCount, 0);
  });
}
