// The web transport end to end over a fake HTTP layer: proto messages in,
// REST / WebChannel requests out, and the recorded emulator responses back.

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/empty_credentials_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/database_info.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/channel_options_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/firestore_transport.dart';
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
      expect(handshake.form['headers'],
          contains('google-cloud-resource-prefix:$database'));
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
      expect(back.aborted, isTrue);
      expect((await http.next()).query['TYPE'], 'terminate');
      await requests.close();
    });

    test(
        'closing the requests sends what is queued, then ends the session '
        'and the call', () async {
      // The client closes a stream by closing its requests (a half-close for
      // gRPC). WebChannel has no half-close: the session is terminated once
      // the last request was delivered.
      final StreamController<proto.WriteRequest> requests =
          StreamController<proto.WriteRequest>();
      bool done = false;
      final List<Object> errors = <Object>[];
      transport
          .startCall(FirestoreRpc.write, requests.stream)
          .listen((_) {}, onError: errors.add, onDone: () => done = true);

      requests.add(proto.WriteRequest()..database = database);
      (await http.next()).respond(200,
          body: '52\n[[0,["c","YpagAp1anIKb52xNgWf4xg==","",8,12,30000]]]');
      final FakeRequest back = await http.next();
      back.stream(200);
      await pump();

      // The final (empty) write of a write stream, then the close.
      requests.add(proto.WriteRequest()..streamToken = <int>[0x30]);
      unawaited(requests.close());
      final FakeRequest lastWrite = await http.next();
      expect(jsonDecode(lastWrite.form['req0___data__']!),
          <String, Object?>{'streamToken': 'MA=='});
      expect(done, isFalse);
      lastWrite.respond(200, body: '7\n[1,2,7]');

      expect((await http.next()).query['TYPE'], 'terminate');
      await pump();
      expect(back.aborted, isTrue);
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

      await transport.shutdown();
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
      expect(codeFromHttpStatus(401), StatusCode.unauthenticated);
      expect(codeFromHttpStatus(403), StatusCode.permissionDenied);
      expect(codeFromHttpStatus(409), StatusCode.aborted);
      expect(codeFromHttpStatus(504), StatusCode.deadlineExceeded);
      expect(codeFromHttpStatus(418), StatusCode.failedPrecondition);
      expect(codeFromHttpStatus(599), StatusCode.internal);
    });
  });
}
