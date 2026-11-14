// The web transport end to end over a fake HTTP layer: proto messages in,
// REST / WebChannel requests out, and the recorded emulator responses back.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/empty_credentials_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/database_info.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/channel_options_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/firestore_transport.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/web/rest_client.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/web/rpc_error.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/web/web_channel_transport.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/grpc_status.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as proto;
import 'package:fixnum/fixnum.dart';
import 'package:test/test.dart';

import 'fake_http_client.dart';

const String database = 'projects/demo-test/databases/(default)';

class _TokenProvider extends EmptyCredentialsProvider {
  @override
  Future<String?> get token async => 'owner';
}

Future<void> pump() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeHttpClient http;
  late WebChannelTransport transport;

  setUp(() {
    http = FakeHttpClient();
    final DatabaseId databaseId = DatabaseId.forProject('demo-test');
    transport = WebChannelTransport(
      http,
      DatabaseInfo(databaseId, 'key', '127.0.0.1',
          port: 8080, sslEnabled: false),
      ChannelOptionsProvider(
          databaseId: databaseId, credentialsProvider: _TokenProvider()),
    );
  });

  group('REST', () {
    test('Commit posts the request without its database to :commit', () async {
      final proto.CommitRequest request = proto.CommitRequest()
        ..database = database
        ..writes.add(proto.Write()
          ..update = (proto.Document()
            ..name = '$database/documents/rooms/a b'
            ..fields['n'] = (proto.Value()..integerValue = Int64.ONE)));

      final Future<List<proto.CommitResponse>> responses = transport
          .startCall(
              FirestoreRpc.commit, Stream<proto.CommitRequest>.value(request))
          .toList();

      final FakeRequest call = await http.next();
      expect(call.method, 'POST');
      expect(
          call.url.toString(),
          'http://127.0.0.1:8080/v1/projects/demo-test/databases/(default)'
          '/documents:commit');
      expect(call.headers['Content-Type'], 'text/plain');
      expect(call.headers['Authorization'], 'Bearer owner');
      expect(call.headers['google-cloud-resource-prefix'], database);
      expect(call.headers['x-goog-api-client'], startsWith('gl-dart/'));
      expect(jsonDecode(call.body!), <String, Object?>{
        'writes': <Object?>[
          <String, Object?>{
            'update': <String, Object?>{
              'name': '$database/documents/rooms/a b',
              'fields': <String, Object?>{
                'n': <String, Object?>{'integerValue': '1'}
              },
            }
          }
        ]
      });

      call.respond(200,
          body:
              '{"writeResults":[{"updateTime":"2026-11-12T21:14:41.553199Z"}],"commitTime":"2026-11-12T21:14:41.553199Z"}');
      final proto.CommitResponse response = (await responses).single;
      expect(response.writeResults, hasLength(1));
      expect(response.commitTime.nanos, 553199000);
    });

    test('BeginTransaction and Rollback post to their verbs of the database',
        () async {
      final Future<List<proto.BeginTransactionResponse>> begun = transport
          .startCall(
              FirestoreRpc.beginTransaction,
              Stream<proto.BeginTransactionRequest>.value(
                  proto.BeginTransactionRequest()
                    ..database = database
                    ..options = (proto.TransactionOptions()
                      ..readOnly = proto.TransactionOptions_ReadOnly())))
          .toList();
      final FakeRequest begin = await http.next();
      expect(
          begin.url.toString(),
          'http://127.0.0.1:8080/v1/projects/demo-test/databases/(default)'
          '/documents:beginTransaction');
      expect(jsonDecode(begin.body!), <String, Object?>{
        'options': <String, Object?>{'readOnly': <String, Object?>{}}
      });
      begin.respond(200, body: '{"transaction":"AQID"}');
      expect((await begun).single.transaction, <int>[1, 2, 3]);

      final Future<List<Object?>> rolledBack = transport
          .startCall(
              FirestoreRpc.rollback,
              Stream<proto.RollbackRequest>.value(proto.RollbackRequest()
                ..database = database
                ..transaction = <int>[1, 2, 3]))
          .toList();
      final FakeRequest rollback = await http.next();
      expect(
          rollback.url.toString(),
          'http://127.0.0.1:8080/v1/projects/demo-test/databases/(default)'
          '/documents:rollback');
      expect(jsonDecode(rollback.body!),
          <String, Object?>{'transaction': 'AQID'});
      // The empty answer, also when it comes without a body.
      rollback.respond(200);
      expect(await rolledBack, hasLength(1));
    });

    test('RunQuery takes the parent from the body into the URL, encoded',
        () async {
      final proto.RunQueryRequest request = proto.RunQueryRequest()
        ..parent = '$database/documents/rooms/a b'
        ..structuredQuery = (proto.StructuredQuery()
          ..from.add(proto.StructuredQuery_CollectionSelector()
            ..collectionId = 'messages'));

      final Future<List<proto.RunQueryResponse>> responses = transport
          .startCall(FirestoreRpc.runQuery,
              Stream<proto.RunQueryRequest>.value(request))
          .toList();

      final FakeRequest call = await http.next();
      expect(
          call.url.toString(),
          'http://127.0.0.1:8080/v1/projects/demo-test/databases/(default)'
          '/documents/rooms/a%20b:runQuery');
      expect(jsonDecode(call.body!), <String, Object?>{
        'structuredQuery': <String, Object?>{
          'from': <Object?>[
            <String, Object?>{'collectionId': 'messages'}
          ]
        }
      });

      // The emulator answers the stream as one JSON array (recorded shape).
      call.respond(200,
          body: '[\n{\n  "document": {\n'
              '    "name": "$database/documents/rooms/a b/messages/m1",\n'
              '    "fields": {"a": {"integerValue": "1"}, "nothing": {"nullValue": null}},\n'
              '    "createTime": "2026-11-12T21:14:21.909894Z",\n'
              '    "updateTime": "2026-11-12T21:14:21.909894Z"\n  },\n'
              '  "readTime": "2026-11-12T21:16:36.740009Z"\n},\n'
              '{\n  "readTime": "2026-11-12T21:16:36.740009Z"\n}]');
      final List<proto.RunQueryResponse> results = await responses;
      expect(results, hasLength(2));
      expect(results[0].document.fields['a']!.integerValue.toInt(), 1);
      // A JSON null would otherwise leave the value without a type.
      expect(results[0].document.fields['nothing']!.whichValueType(),
          proto.Value_ValueType.nullValue);
      expect(results[1].hasDocument(), isFalse);
    });

    test(
        'BatchGetDocuments, RunAggregationQuery and ExecutePipeline use their own verbs',
        () async {
      unawaited(transport
          .startCall(
              FirestoreRpc.batchGetDocuments,
              Stream<proto.BatchGetDocumentsRequest>.value(
                  proto.BatchGetDocumentsRequest()
                    ..database = database
                    ..documents.add('$database/documents/rooms/a')))
          .toList());
      final FakeRequest batchGet = await http.next();
      expect(batchGet.url.path,
          '/v1/projects/demo-test/databases/(default)/documents:batchGet');
      expect(jsonDecode(batchGet.body!), <String, Object?>{
        'documents': <Object?>['$database/documents/rooms/a']
      });
      batchGet.respond(200, body: '[]');

      unawaited(transport
          .startCall(
              FirestoreRpc.runAggregationQuery,
              Stream<proto.RunAggregationQueryRequest>.value(
                  proto.RunAggregationQueryRequest()
                    ..parent = '$database/documents'))
          .toList());
      final FakeRequest aggregate = await http.next();
      expect(
          aggregate.url.path,
          '/v1/projects/demo-test/databases/(default)'
          '/documents:runAggregationQuery');
      aggregate.respond(200, body: '[]');

      unawaited(transport
          .startCall(
              FirestoreRpc.executePipeline,
              Stream<proto.ExecutePipelineRequest>.value(
                  proto.ExecutePipelineRequest()..database = database))
          .toList());
      final FakeRequest pipeline = await http.next();
      expect(
          pipeline.url.path,
          '/v1/projects/demo-test/databases/(default)'
          '/documents:executePipeline');
      expect(jsonDecode(pipeline.body!), <String, Object?>{});
      pipeline.respond(200, body: '[]');
    });

    test('an error response becomes a GrpcError with the status of the body',
        () async {
      Future<GrpcError> failWith(int status, String body) async {
        final Future<List<proto.CommitResponse>> responses = transport
            .startCall(
                FirestoreRpc.commit,
                Stream<proto.CommitRequest>.value(
                    proto.CommitRequest()..database = database))
            .toList();
        (await http.next()).respond(status, body: body);
        try {
          await responses;
        } on GrpcError catch (e) {
          return e;
        }
        fail('The call did not fail');
      }

      // Recorded from the emulator: 409 is ALREADY_EXISTS here, 400 is
      // FAILED_PRECONDITION, so the HTTP status alone is not enough.
      GrpcError error = await failWith(409,
          '{"error":{"code":409,"message":"entity already exists","status":"ALREADY_EXISTS"}}');
      expect(error.code, StatusCode.alreadyExists);
      expect(error.message, 'entity already exists');

      error = await failWith(400,
          '{"error":{"code":400,"message":"the stored version does not match","status":"FAILED_PRECONDITION"}}');
      expect(error.code, StatusCode.failedPrecondition);

      // Streaming endpoints wrap the error in a list.
      error = await failWith(400,
          '[{"error":{"code":400,"message":"bad","status":"INVALID_ARGUMENT"}}]');
      expect(error.code, StatusCode.invalidArgument);

      // No usable body: the HTTP status decides.
      error = await failWith(503, '<html>Service Unavailable</html>');
      expect(error.code, StatusCode.unavailable);
      error = await failWith(404, 'Not Found');
      expect(error.code, StatusCode.notFound);
      // As the JS SDK (mapCodeFromHttpStatus): a bare 400 is FAILED_PRECONDITION, which transactions retry.
      error = await failWith(400, 'Bad Request');
      expect(error.code, StatusCode.failedPrecondition);
    });

    test('a network error is UNAVAILABLE', () async {
      final Future<List<proto.CommitResponse>> responses = transport
          .startCall(
              FirestoreRpc.commit,
              Stream<proto.CommitRequest>.value(
                  proto.CommitRequest()..database = database))
          .toList();
      (await http.next()).fail(StateError('offline'));
      await expectLater(
          responses,
          throwsA(isA<GrpcError>().having(
              (GrpcError e) => e.code, 'code', StatusCode.unavailable)));
    });

    test('cancel aborts the request', () async {
      final ResponseStream<proto.CommitResponse> call = transport.startCall(
          FirestoreRpc.commit,
          Stream<proto.CommitRequest>.value(
              proto.CommitRequest()..database = database));
      final List<Object> errors = <Object>[];
      call.listen((_) {}, onError: errors.add);
      final FakeRequest request = await http.next();
      await call.cancel();
      expect(request.aborted, isTrue);
      await pump();
      expect(errors, isEmpty);
    });

    test('shutdown fails the calls in flight with UNAVAILABLE', () async {
      // As over gRPC. A call whose stream just ended looked like a complete
      // answer: a lookup with missing documents, a commit with no response.
      final Future<List<proto.BatchGetDocumentsResponse>> lookup = transport
          .startCall(
              FirestoreRpc.batchGetDocuments,
              Stream<proto.BatchGetDocumentsRequest>.value(
                  proto.BatchGetDocumentsRequest()
                    ..database = database
                    ..documents.add('$database/documents/coll/doc')))
          .toList();
      final Future<List<proto.CommitResponse>> commit = transport
          .startCall(
              FirestoreRpc.commit,
              Stream<proto.CommitRequest>.value(
                  proto.CommitRequest()..database = database))
          .toList();
      await http.next();
      await http.next();
      final Matcher unavailable = throwsA(isA<GrpcError>()
          .having((GrpcError e) => e.code, 'code', StatusCode.unavailable));
      final Future<void> lookupFails = expectLater(lookup, unavailable);
      final Future<void> commitFails = expectLater(commit, unavailable);
      await transport.shutdown();

      await lookupFails;
      await commitFails;
    });
  });

  group('streams', () {
    test('Write: handshake, token and a write, as recorded', () async {
      final StreamController<proto.WriteRequest> requests =
          StreamController<proto.WriteRequest>();
      final ResponseStream<proto.WriteResponse> call =
          transport.startCall(FirestoreRpc.write, requests.stream);
      final List<proto.WriteResponse> responses = <proto.WriteResponse>[];
      final List<Object> errors = <Object>[];
      call.listen(responses.add, onError: errors.add);

      requests.add(proto.WriteRequest()..database = database);
      final FakeRequest handshake = await http.next();
      expect(
          handshake.url.path, '/google.firestore.v1.Firestore/Write/channel');
      expect(handshake.query['database'], database);
      expect(handshake.form['headers'], contains('Authorization:Bearer owner'));
      // As the JS WebChannelConnection: the stream is routed by its
      // `database` parameter, the routing headers are for unary calls only.
      expect(handshake.form['headers'],
          isNot(contains('google-cloud-resource-prefix')));
      expect(handshake.form['headers'],
          isNot(contains('x-goog-request-params')));
      expect(handshake.form['headers'], contains('Content-Type:text/plain'));
      expect(jsonDecode(handshake.form['req0___data__']!),
          <String, Object?>{'database': database});
      handshake.respond(200,
          body: '52\n[[0,["c","YpagAp1anIKb52xNgWf4xg==","",8,12,30000]]]');

      final FakeRequest back = await http.next();
      back.stream(200);
      back.add('49\n[[1,[{"streamId":"15395","streamToken":"MA=="}]]]');
      await pump();
      expect(responses.single.streamToken, <int>[0x30]);
      expect(await call.headers, isEmpty);

      requests.add(proto.WriteRequest()
        ..streamToken = <int>[0x30]
        ..writes.add(proto.Write()
          ..update = (proto.Document()
            ..name = '$database/documents/webprobe/doc2'
            ..fields['b'] = (proto.Value()..stringValue = 'hi'))));
      final FakeRequest write = await http.next();
      expect(write.query['SID'], 'YpagAp1anIKb52xNgWf4xg==');
      expect(write.form['ofs'], '1');
      expect(jsonDecode(write.form['req0___data__']!), <String, Object?>{
        'streamToken': 'MA==',
        'writes': <Object?>[
          <String, Object?>{
            'update': <String, Object?>{
              'name': '$database/documents/webprobe/doc2',
              'fields': <String, Object?>{
                'b': <String, Object?>{'stringValue': 'hi'}
              }
            }
          }
        ]
      });
      write.respond(200, body: '7\n[1,2,7]');

      back.add('14\n[[2,["noop"]]]135\n'
          '[[3,[{"streamToken":"MQ==","writeResults":[{"updateTime":"2026-11-12T21:14:41.553199Z"}],"commitTime":"2026-11-12T21:14:41.553199Z"}]]]');
      await pump();
      expect(responses, hasLength(2));
      expect(responses[1].streamToken, <int>[0x31]);
      expect(responses[1].writeResults, hasLength(1));
      expect(errors, isEmpty);

      await call.cancel();
      final FakeRequest terminate = await http.next();
      expect(terminate.query['TYPE'], 'terminate');
      terminate.respond(200);
      await pump();
      expect(back.aborted, isTrue);
      await requests.close();
    });

    /// Opens a Write stream and answers its handshake. Returns the requests
    /// of the client and the back channel request.
    Future<(StreamController<proto.WriteRequest>, FakeRequest)> openWrites(
        void Function() onDone, List<Object> errors) async {
      final StreamController<proto.WriteRequest> requests =
          StreamController<proto.WriteRequest>();
      transport
          .startCall(FirestoreRpc.write, requests.stream)
          .listen((_) {}, onError: errors.add, onDone: onDone);

      requests.add(proto.WriteRequest()..database = database);
      (await http.next()).respond(200,
          body: '52\n[[0,["c","YpagAp1anIKb52xNgWf4xg==","",8,12,30000]]]');
      final FakeRequest back = await http.next();
      back.stream(200);
      // The answer to the handshake: the next request is only sent after it.
      back.add('49\n[[1,[{"streamId":"15395","streamToken":"MA=="}]]]');
      await pump();
      return (requests, back);
    }

    proto.WriteRequest setDoc(String id, int value) => proto.WriteRequest()
      ..streamToken = <int>[0x30]
      ..writes.add(proto.Write()
        ..update = (proto.Document()
          ..name = '$database/documents/rooms/$id'
          ..fields['v'] = (proto.Value()..integerValue = Int64(value))));

    /// The POSTs with messages (not the terminate request, not the back
    /// channel) among the requests from [start] on.
    List<FakeRequest> forwardRequests(int start) => <FakeRequest>[
          for (final FakeRequest request in http.requests.skip(start))
            if (request.method == 'POST') request,
        ];

    test(
        'closing the requests ends the session and the call, with the '
        'request in flight left to finish', () async {
      // The client closes a stream by closing its requests (a half-close for
      // gRPC). WebChannel has no half-close: the session is terminated.
      bool done = false;
      final List<Object> errors = <Object>[];
      final (StreamController<proto.WriteRequest> requests, FakeRequest back) =
          await openWrites(() => done = true, errors);

      // The final (empty) write of a write stream, then the close.
      requests.add(proto.WriteRequest()..streamToken = <int>[0x30]);
      final FakeRequest lastWrite = await http.next();
      expect(jsonDecode(lastWrite.form['req0___data__']!),
          <String, Object?>{'streamToken': 'MA=='});
      unawaited(requests.close());
      await pump();
      // The call is over for the client at once.
      expect(done, isTrue);
      expect(lastWrite.aborted, isFalse);
      lastWrite.respond(200, body: '7\n[1,2,7]');

      final FakeRequest terminate = await http.next();
      expect(terminate.query['TYPE'], 'terminate');
      terminate.respond(200);
      await pump();
      expect(back.aborted, isTrue);
      expect(errors, isEmpty);
    });

    test(
        'writes of a stream the client closed are not delivered afterwards: '
        'a failed request is not sent again', () async {
      // Found by the chaos soak test: disableNetwork() closed the write
      // stream while the request with its writes was failing (a cut); the
      // session went on sending the request again until it got through, a
      // second later, after the client had sent the same writes and newer
      // ones on its next stream. The backend applied the old writes last.
      bool done = false;
      final List<Object> errors = <Object>[];
      final (StreamController<proto.WriteRequest> requests, FakeRequest _) =
          await openWrites(() => done = true, errors);

      requests.add(setDoc('a', 1));
      final FakeRequest write = await http.next();
      expect(write.form['req0___data__'], contains('rooms/a'));
      final int sent = http.requests.length;

      // The client closes the stream (disableNetwork), then the connection
      // of the request in flight is cut.
      unawaited(requests.close());
      await pump();
      write.fail(const SocketException('connection cut'));

      final FakeRequest terminate = await http.next();
      expect(terminate.query['TYPE'], 'terminate');
      terminate.respond(200);
      // Longer than the delays before a request is sent again (100 ms, 1 s).
      await Future<void>.delayed(const Duration(milliseconds: 1400));
      expect(forwardRequests(sent), isEmpty,
          reason: 'the write was sent again after the client closed the '
              'stream');
      expect(done, isTrue);
      expect(errors, isEmpty);
    });

    test(
        'writes of a stream the client closed are not delivered afterwards: '
        'what waited for the request in flight is dropped', () async {
      bool done = false;
      final List<Object> errors = <Object>[];
      final (StreamController<proto.WriteRequest> requests, FakeRequest _) =
          await openWrites(() => done = true, errors);

      requests.add(setDoc('a', 1));
      final FakeRequest first = await http.next();
      // Sent ahead: it waits for the request in flight.
      requests.add(setDoc('b', 2));
      await pump();
      final int sent = http.requests.length;

      unawaited(requests.close());
      await pump();
      // The request in flight is answered: before, the write that waited
      // went out now.
      first.respond(200, body: '7\n[1,2,7]');

      final FakeRequest terminate = await http.next();
      expect(terminate.query['TYPE'], 'terminate');
      terminate.respond(200);
      await pump();
      expect(forwardRequests(sent), isEmpty,
          reason: 'a write went out after the client closed the stream');
      expect(done, isTrue);
      expect(errors, isEmpty);
    });

    test('Listen: a rejected target keeps its cause, without the details',
        () async {
      final StreamController<proto.ListenRequest> requests =
          StreamController<proto.ListenRequest>();
      final List<proto.ListenResponse> responses = <proto.ListenResponse>[];
      final ResponseStream<proto.ListenResponse> call =
          transport.startCall(FirestoreRpc.listen, requests.stream);
      call.listen(responses.add);

      requests.add(proto.ListenRequest()
        ..database = database
        ..addTarget = (proto.Target()..targetId = 2));
      (await http.next()).respond(200,
          body: '52\n[[0,["c","4ApGpUebBDNnT9YbQeHo6g==","",8,12,30000]]]');
      final FakeRequest back = await http.next();
      back.stream(200);
      // Recorded from the emulator, with `details` added as the production
      // backend sends them.
      back.add(chunk(
          '[[1,[{"targetChange":{"targetChangeType":"REMOVE","targetIds":[2],"cause":{"code":3,"message":"Document parent name \\"bogus\\" lacks \\"projects\\" at index 0.","details":[{"@type":"type.googleapis.com/google.rpc.ErrorInfo","reason":"X"}]}}}]]]'));
      await pump();

      final proto.TargetChange change = responses.single.targetChange;
      expect(
          change.targetChangeType, proto.TargetChange_TargetChangeType.REMOVE);
      expect(change.cause.code, 3);
      expect(change.cause.message, startsWith('Document parent name'));
      await call.cancel();
      await requests.close();
    });

    test('a stream error reaches the call as a GrpcError and ends it',
        () async {
      final StreamController<proto.ListenRequest> requests =
          StreamController<proto.ListenRequest>();
      final List<Object> errors = <Object>[];
      bool done = false;
      transport
          .startCall(FirestoreRpc.listen, requests.stream)
          .listen((_) {}, onError: errors.add, onDone: () => done = true);

      requests.add(proto.ListenRequest()..database = database);
      (await http.next()).respond(200,
          body: '52\n[[0,["c","4ApGpUebBDNnT9YbQeHo6g==","",8,12,30000]]]');
      (await http.next()).respond(200,
          body: chunk(
              '[[1,{"__sm__":{"status":[[{"error":{"code":403,"message":"denied","status":"PERMISSION_DENIED"}}]]}}]]'));
      await pump();
      await pump();

      expect((errors.single as GrpcError).code, StatusCode.permissionDenied);
      expect(done, isTrue);
      await requests.close();
    });

    test('shutdown ends the open calls and closes the HTTP client', () async {
      final StreamController<proto.ListenRequest> requests =
          StreamController<proto.ListenRequest>();
      bool done = false;
      transport
          .startCall(FirestoreRpc.listen, requests.stream)
          .listen((_) {}, onDone: () => done = true);
      requests.add(proto.ListenRequest()..database = database);
      (await http.next()).respond(200,
          body: '52\n[[0,["c","4ApGpUebBDNnT9YbQeHo6g==","",8,12,30000]]]');
      final FakeRequest back = await http.next();
      back.stream(200);
      await pump();

      final Future<void> shutdown = transport.shutdown();
      // The session is terminated before the HTTP client is closed, which
      // would cut the request off.
      final FakeRequest terminate = await http.next();
      expect(terminate.query['TYPE'], 'terminate');
      expect(http.closed, isFalse);
      terminate.respond(200);
      await shutdown;
      await pump();
      expect(back.aborted, isTrue);
      expect(done, isTrue);
      expect(http.closed, isTrue);

      // Calls after the shutdown fail instead of hanging.
      await expectLater(
          transport
              .startCall(
                  FirestoreRpc.commit,
                  Stream<proto.CommitRequest>.value(
                      proto.CommitRequest()..database = database))
              .toList(),
          throwsA(isA<GrpcError>()));
      await requests.close();
    });
  });

  group('write requests are sent ahead when they can be repeated', () {
    late StreamController<proto.WriteRequest> requests;
    late List<proto.WriteResponse> responses;
    late List<Object> errors;
    late FakeRequest back;

    proto.WriteRequest write(String id) => proto.WriteRequest()
      ..streamToken = <int>[0x30]
      ..writes.add(proto.Write()..delete = '$database/documents/c/$id');

    proto.WriteRequest increment(String id) => proto.WriteRequest()
      ..streamToken = <int>[0x30]
      ..writes.add(proto.Write()
        ..update = (proto.Document()..name = '$database/documents/c/$id')
        ..updateMask = proto.DocumentMask()
        ..updateTransforms.add(proto.DocumentTransform_FieldTransform()
          ..fieldPath = 'n'
          ..increment = (proto.Value()..integerValue = Int64(1))));

    /// The last path segments of the documents written by [request], one per
    /// message of the request.
    List<String> written(FakeRequest request) {
      final int count = int.parse(request.form['count']!);
      return <String>[
        for (int i = 0; i < count; i++)
          () {
            final Map<String, Object?> write =
                ((jsonDecode(request.form['req${i}___data__']!)
                            as Map<String, Object?>)['writes']!
                        as List<Object?>)
                    .single!
                    as Map<String, Object?>;
            final String name = write.containsKey('delete')
                ? write['delete']! as String
                : (write['update']! as Map<String, Object?>)['name']! as String;
            return name.split('/').last;
          }(),
      ];
    }

    const String ack =
        '[{"streamToken":"MQ==","writeResults":[{}],"commitTime":"2026-11-12T21:14:41.553199Z"}]';

    setUp(() async {
      requests = StreamController<proto.WriteRequest>();
      responses = <proto.WriteResponse>[];
      errors = <Object>[];
      transport
          .startCall(FirestoreRpc.write, requests.stream)
          .listen(responses.add, onError: errors.add);
      requests.add(proto.WriteRequest()..database = database);
      (await http.next()).respond(200,
          body: '52\n[[0,["c","YpagAp1anIKb52xNgWf4xg==","",8,12,30000]]]');
      back = await http.next();
      back.stream(200);
      await pump();
    });

    tearDown(() => requests.close());

    test('repeatable writes do not wait for the earlier responses', () async {
      back.add('49\n[[1,[{"streamId":"15395","streamToken":"MA=="}]]]');
      await pump();
      requests.add(write('a'));
      final FakeRequest first = await http.next();
      expect(written(first), <String>['a']);
      // More writes while `a` is neither delivered nor answered: they go out
      // together as soon as the request in progress is done.
      requests.add(write('b'));
      requests.add(write('c'));
      await pump();
      first.respond(200, body: '7\n[1,2,7]');
      final FakeRequest second = await http.next();
      expect(written(second), <String>['b', 'c']);
      expect(second.form['ofs'], '2');
      second.respond(200, body: '7\n[1,4,7]');

      back.add(chunk('[[2,$ack],[3,$ack],[4,$ack]]'));
      await pump();
      expect(responses, hasLength(4));
      expect(errors, isEmpty);
    });

    test('an increment waits for the responses to everything before it',
        () async {
      back.add('49\n[[1,[{"streamId":"15395","streamToken":"MA=="}]]]');
      await pump();
      requests.add(write('a'));
      requests.add(increment('counter'));
      requests.add(write('b'));
      final FakeRequest first = await http.next();
      expect(written(first), <String>['a']);
      first.respond(200, body: '7\n[1,2,7]');
      await pump();
      // `a` is delivered but not answered: the increment stays back, and so
      // does `b` behind it (requests go out in order).
      expect(http.hasUnclaimed, isFalse);

      back.add(chunk('[[2,$ack]]'));
      final FakeRequest second = await http.next();
      expect(written(second), <String>['counter']);
      second.respond(200, body: '7\n[1,3,7]');
      // `b` can be repeated: it is sent ahead of the answer to the increment.
      final FakeRequest third = await http.next();
      expect(written(third), <String>['b']);
      third.respond(200, body: '7\n[1,4,7]');
      back.add(chunk('[[3,$ack],[4,$ack]]'));
      await pump();
      expect(responses, hasLength(4));
      expect(errors, isEmpty);
    });

    test('a write that fails is not followed by an increment behind it',
        () async {
      back.add('49\n[[1,[{"streamId":"15395","streamToken":"MA=="}]]]');
      await pump();
      requests.add(write('a'));
      requests.add(increment('counter'));
      final FakeRequest first = await http.next();
      first.respond(200, body: '7\n[1,2,7]');
      await pump();

      // As the emulator reports a failed write: a message, and the session
      // goes on, so the increment would be applied if it had been sent ahead
      // (and applied again when the client sends it on its next stream).
      back.add(chunk(
          '[[2,[{"error":{"message":"NOT_FOUND: no entity to update","status":"NOT_FOUND"}}]]]'));
      await pump();
      expect((errors.single as GrpcError).code, StatusCode.notFound);

      // Only the end of the session follows.
      final FakeRequest terminate = await http.next();
      expect(terminate.query['TYPE'], 'terminate');
      terminate.respond(200);
      await pump();
      expect(http.hasUnclaimed, isFalse);
      expect(
          http.requests.where((FakeRequest r) => r.method == 'POST'),
          hasLength(2),
          reason: 'the handshake and the first write');
    });
  });

  group('robustness', () {
    test(
      'a unary call that takes too long fails with DEADLINE_EXCEEDED',
      () async {
        final DatabaseId databaseId = DatabaseId.forProject('demo-test');
        final WebChannelTransport quick = WebChannelTransport(
          http,
          DatabaseInfo(
            databaseId,
            'key',
            '127.0.0.1',
            port: 8080,
            sslEnabled: false,
          ),
          ChannelOptionsProvider(
            databaseId: databaseId,
            credentialsProvider: _TokenProvider(),
          ),
          unaryTimeout: const Duration(milliseconds: 50),
        );
        final Future<List<proto.CommitResponse>> responses = quick
            .startCall(
              FirestoreRpc.commit,
              Stream<proto.CommitRequest>.value(
                proto.CommitRequest()..database = database,
              ),
            )
            .toList();
        final FakeRequest request = await http.next();
        // Headers arrive, the body never ends.
        request.stream(200);

        await expectLater(
          responses,
          throwsA(
            isA<GrpcError>()
                .having(
                  (GrpcError e) => e.code,
                  'code',
                  StatusCode.deadlineExceeded,
                )
                .having(
                  (GrpcError e) => e.message,
                  'message',
                  'Request time out',
                ),
          ),
        );
        expect(request.aborted, isTrue);
      },
    );

    test('the default unary timeout is the 15 seconds of the JS SDK', () {
      expect(RestClient.defaultTimeout, const Duration(seconds: 15));
    });

    test('closing the requests of a stream ends its session', () async {
      final StreamController<proto.ListenRequest> requests =
          StreamController<proto.ListenRequest>();
      bool done = false;
      final List<Object> errors = <Object>[];
      transport
          .startCall(FirestoreRpc.listen, requests.stream)
          .listen((_) {}, onError: errors.add, onDone: () => done = true);
      requests.add(proto.ListenRequest()..database = database);
      (await http.next()).respond(
        200,
        body: '52\n[[0,["c","4ApGpUebBDNnT9YbQeHo6g==","",8,12,30000]]]',
      );
      final FakeRequest back = await http.next();
      back.stream(200);
      await pump();

      // What BaseStream does when the client stops a stream: no cancel.
      await requests.close();
      final FakeRequest terminate = await http.next();
      expect(terminate.query['TYPE'], 'terminate');
      terminate.respond(200);
      await pump();
      expect(back.aborted, isTrue);
      expect(done, isTrue);
      expect(errors, isEmpty);
    });

    test('long polling settings of the database reach the streams', () async {
      final DatabaseId databaseId = DatabaseId.forProject('demo-test');
      final WebChannelTransport polling = WebChannelTransport(
        http,
        DatabaseInfo(
          databaseId,
          'key',
          '127.0.0.1',
          port: 8080,
          sslEnabled: false,
          forceLongPolling: true,
          autoDetectLongPolling: false,
        ),
        ChannelOptionsProvider(
          databaseId: databaseId,
          credentialsProvider: _TokenProvider(),
        ),
      );
      final StreamController<proto.ListenRequest> requests =
          StreamController<proto.ListenRequest>();
      final ResponseStream<proto.ListenResponse> call = polling.startCall(
        FirestoreRpc.listen,
        requests.stream,
      );
      call.listen((_) {});
      requests.add(proto.ListenRequest()..database = database);
      (await http.next()).respond(
        200,
        body: '52\n[[0,["c","4ApGpUebBDNnT9YbQeHo6g==","",8,12,30000]]]',
      );
      expect((await http.next()).query['CI'], '1');
      await call.cancel();
      await requests.close();
    });

    test('refuses to start without the protobuf names proto3 JSON needs', () {
      // The real messages have their names.
      WebChannelTransport.checkProto3JsonNames();

      // As with -Dprotobuf.omit_field_names=true: the keys are field numbers.
      expect(
        () => WebChannelTransport.checkProto3JsonNames(
          encodeRequest: () => <String, Object?>{'1': 'd'},
        ),
        throwsA(
          isA<UnsupportedError>().having(
            (UnsupportedError e) => e.message,
            'message',
            contains('protobuf.omit_field_names'),
          ),
        ),
      );
      // As with -Dprotobuf.omit_enum_names=true: enums are numbers.
      expect(
        () => WebChannelTransport.checkProto3JsonNames(
          encodeEnum: () => <String, Object?>{'targetChangeType': 2},
        ),
        throwsA(
          isA<UnsupportedError>().having(
            (UnsupportedError e) => e.message,
            'message',
            contains('enum names'),
          ),
        ),
      );
    });
  });

  group('status mapping', () {
    test('status names win over the numeric code', () {
      expect(
          grpcErrorFromJson(<String, Object?>{
            'code': 400,
            'status': 'OUT_OF_RANGE',
            'message': 'm'
          }).code,
          StatusCode.outOfRange);
      expect(grpcErrorFromJson(<String, Object?>{'code': 429}).code,
          StatusCode.resourceExhausted);
      expect(grpcErrorFromJson(<String, Object?>{'status': 'NOPE'}).code,
          StatusCode.internal);
    });

    test('HTTP statuses map like in the JS SDK', () {
      expect(codeFromHttpStatus(400), StatusCode.failedPrecondition);
      expect(codeFromHttpStatus(401), StatusCode.unauthenticated);
      expect(codeFromHttpStatus(403), StatusCode.permissionDenied);
      expect(codeFromHttpStatus(409), StatusCode.aborted);
      expect(codeFromHttpStatus(504), StatusCode.deadlineExceeded);
      expect(codeFromHttpStatus(418), StatusCode.failedPrecondition);
      expect(codeFromHttpStatus(599), StatusCode.internal);
    });
  });
}
