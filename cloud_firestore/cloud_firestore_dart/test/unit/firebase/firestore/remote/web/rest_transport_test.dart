// The REST-only transport of Firestore Lite against a fake HTTP layer.

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/empty_credentials_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/database_info.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/channel_options_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/firestore_transport.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/web/rest_transport.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/grpc_status.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as proto;
import 'package:fixnum/fixnum.dart';
import 'package:test/test.dart';

import 'fake_http_client.dart';

const String database = 'projects/p/databases/(default)';

void main() {
  late FakeHttpClient http;
  late RestTransport transport;

  setUp(() {
    http = FakeHttpClient();
    final DatabaseId databaseId = DatabaseId.forProject('p');
    transport = RestTransport(
      http,
      DatabaseInfo(
        databaseId,
        'key',
        'example.test',
        port: 8443,
        sslEnabled: true,
      ),
      ChannelOptionsProvider(
        databaseId: databaseId,
        credentialsProvider: EmptyCredentialsProvider(),
      ),
    );
  });

  test('a commit is one POST with the request as proto3 JSON', () async {
    final proto.CommitRequest request = proto.CommitRequest()
      ..database = database
      ..writes.add(
        proto.Write()
          ..update = (proto.Document()
            ..name = '$database/documents/coll/doc'
            ..fields['a'] = (proto.Value()..integerValue = Int64(1))),
      );
    final Future<List<proto.CommitResponse>> responses = transport
        .startCall(
          FirestoreRpc.commit,
          Stream<proto.CommitRequest>.value(request),
        )
        .toList();

    final FakeRequest sent = await http.next();
    expect(sent.method, 'POST');
    expect(
      sent.url.toString(),
      'https://example.test:8443/v1/projects/p/databases/(default)'
      '/documents:commit',
    );
    // As the JS SDK's RestConnection; gRPC sends the database name.
    expect(sent.headers['x-goog-request-params'], 'project_id=p');
    expect(sent.headers['google-cloud-resource-prefix'], database);
    expect(sent.headers['Content-Type'], 'text/plain');
    final Map<String, Object?> body =
        jsonDecode(sent.body!) as Map<String, Object?>;
    expect(
      body.containsKey('database'),
      isFalse,
      reason: 'REST takes the database from the URL',
    );
    expect(body['writes'], <Object?>[
      <String, Object?>{
        'update': <String, Object?>{
          'name': '$database/documents/coll/doc',
          'fields': <String, Object?>{
            'a': <String, Object?>{'integerValue': '1'},
          },
        },
      },
    ]);

    sent.respond(
      200,
      body: jsonEncode(<String, Object?>{
        'writeResults': <Object?>[<String, Object?>{}],
        'commitTime': '2024-01-01T00:00:00Z',
      }),
    );
    final proto.CommitResponse response = (await responses).single;
    expect(response.writeResults, hasLength(1));
    expect(response.commitTime.seconds, Int64(1704067200));
  });

  test(
    'a server-streaming call returns every element of the JSON array',
    () async {
      final Future<List<proto.BatchGetDocumentsResponse>> responses = transport
          .startCall(
            FirestoreRpc.batchGetDocuments,
            Stream<proto.BatchGetDocumentsRequest>.value(
              proto.BatchGetDocumentsRequest()
                ..database = database
                ..documents.add('$database/documents/coll/a')
                ..documents.add('$database/documents/coll/b'),
            ),
          )
          .toList();
      final FakeRequest sent = await http.next();
      expect(sent.url.path, '/v1/$database/documents:batchGet');
      sent.respond(
        200,
        body: jsonEncode(<Object?>[
          <String, Object?>{
            'found': <String, Object?>{
              'name': '$database/documents/coll/a',
              'fields': <String, Object?>{
                // The null of a Firestore value arrives as a JSON null.
                'nothing': <String, Object?>{'nullValue': null},
              },
              'updateTime': '2024-01-01T00:00:00Z',
            },
            'readTime': '2024-01-01T00:00:01Z',
          },
          <String, Object?>{
            'missing': '$database/documents/coll/b',
            'readTime': '2024-01-01T00:00:01Z',
          },
        ]),
      );
      final List<proto.BatchGetDocumentsResponse> list = await responses;
      expect(list, hasLength(2));
      expect(list[0].found.fields['nothing']!.hasNullValue(), isTrue);
      expect(list[1].missing, '$database/documents/coll/b');
    },
  );

  test(
    'an error response becomes a GrpcError with the status of the body',
    () async {
      final Future<List<proto.CommitResponse>> responses = transport
          .startCall(
            FirestoreRpc.commit,
            Stream<proto.CommitRequest>.value(
              proto.CommitRequest()..database = database,
            ),
          )
          .toList();
      (await http.next()).respond(
        403,
        body: jsonEncode(<String, Object?>{
          'error': <String, Object?>{
            'code': 403,
            'message': 'Missing or insufficient permissions.',
            'status': 'PERMISSION_DENIED',
          },
        }),
      );
      await expectLater(
        responses,
        throwsA(
          isA<GrpcError>()
              .having(
                (GrpcError e) => e.code,
                'code',
                StatusCode.permissionDenied,
              )
              .having(
                (GrpcError e) => e.message,
                'message',
                'Missing or insufficient permissions.',
              ),
        ),
      );
    },
  );

  test('a network failure is UNAVAILABLE', () async {
    final Future<List<proto.CommitResponse>> responses = transport
        .startCall(
          FirestoreRpc.commit,
          Stream<proto.CommitRequest>.value(
            proto.CommitRequest()..database = database,
          ),
        )
        .toList();
    (await http.next()).fail(StateError('offline'));
    await expectLater(
      responses,
      throwsA(
        isA<GrpcError>().having(
          (GrpcError e) => e.code,
          'code',
          StatusCode.unavailable,
        ),
      ),
    );
  });

  test(
    'a parent with dot segments is refused instead of resolved in the URL',
    () async {
      // Without the check, Uri.parse resolves the `..` segments and the query
      // goes to projects/q with the credentials of projects/p.
      for (final String parent in <String>[
        '$database/documents/a/../../../../../q/databases/(default)/documents',
        '$database/documents/a/./b',
        '$database/documents/a//b',
      ]) {
        await expectLater(
          transport
              .startCall(
                FirestoreRpc.runQuery,
                Stream<proto.RunQueryRequest>.value(
                  proto.RunQueryRequest()
                    ..parent = parent
                    ..structuredQuery = (proto.StructuredQuery()
                      ..from.add(
                        proto.StructuredQuery_CollectionSelector()
                          ..collectionId = 'c',
                      )),
                ),
              )
              .toList(),
          throwsA(
            isA<GrpcError>().having(
              (GrpcError e) => e.code,
              'code',
              StatusCode.invalidArgument,
            ),
          ),
          reason: parent,
        );
      }
      expect(http.requests, isEmpty);
    },
  );

  test('the streams of the main library are not available', () async {
    await expectLater(
      transport
          .startCall(
            FirestoreRpc.listen,
            const Stream<proto.ListenRequest>.empty(),
          )
          .toList(),
      throwsA(
        isA<GrpcError>().having(
          (GrpcError e) => e.code,
          'code',
          StatusCode.unimplemented,
        ),
      ),
    );
    await expectLater(
      transport
          .startCall(
            FirestoreRpc.write,
            const Stream<proto.WriteRequest>.empty(),
          )
          .toList(),
      throwsA(
        isA<GrpcError>().having(
          (GrpcError e) => e.code,
          'code',
          StatusCode.unimplemented,
        ),
      ),
    );
    expect(http.requests, isEmpty);
  });

  test('cancelling a call aborts its request', () async {
    final ResponseStream<proto.CommitResponse> call = transport.startCall(
      FirestoreRpc.commit,
      Stream<proto.CommitRequest>.value(
        proto.CommitRequest()..database = database,
      ),
    );
    final List<Object> events = <Object>[];
    call.listen(events.add, onError: events.add);
    final FakeRequest sent = await http.next();
    await call.cancel();
    expect(sent.aborted, isTrue);
    await pumpEventQueue();
    expect(events, isEmpty);
  });

  test('shutdown() aborts the calls in flight and refuses new ones', () async {
    transport
        .startCall(
          FirestoreRpc.commit,
          Stream<proto.CommitRequest>.value(
            proto.CommitRequest()..database = database,
          ),
        )
        .listen((_) {}, onError: (Object _) {});
    final FakeRequest sent = await http.next();
    await transport.shutdown();
    expect(sent.aborted, isTrue);
    expect(http.closed, isTrue);

    await expectLater(
      transport
          .startCall(
            FirestoreRpc.commit,
            Stream<proto.CommitRequest>.value(
              proto.CommitRequest()..database = database,
            ),
          )
          .toList(),
      throwsA(
        isA<GrpcError>().having(
          (GrpcError e) => e.code,
          'code',
          StatusCode.unavailable,
        ),
      ),
    );
    expect(http.requests, hasLength(1));
  });

  test('shutdown() fails the calls in flight with UNAVAILABLE', () async {
    // As over gRPC. A call whose stream just ended looked like a complete
    // answer: a lookup with missing documents, a commit with no response.
    final Future<List<proto.BatchGetDocumentsResponse>> lookup = transport
        .startCall(
          FirestoreRpc.batchGetDocuments,
          Stream<proto.BatchGetDocumentsRequest>.value(
            proto.BatchGetDocumentsRequest()
              ..database = database
              ..documents.add('$database/documents/coll/doc'),
          ),
        )
        .toList();
    final Future<List<proto.CommitResponse>> commit = transport
        .startCall(
          FirestoreRpc.commit,
          Stream<proto.CommitRequest>.value(
            proto.CommitRequest()..database = database,
          ),
        )
        .toList();
    await http.next();
    await http.next();
    final Matcher unavailable = throwsA(
      isA<GrpcError>().having(
        (GrpcError e) => e.code,
        'code',
        StatusCode.unavailable,
      ),
    );
    final Future<void> lookupFails = expectLater(lookup, unavailable);
    final Future<void> commitFails = expectLater(commit, unavailable);
    await transport.shutdown();

    await lookupFails;
    await commitFails;
  });

  test('refuses to run without the protobuf names', () {
    expect(
      () => RestTransport.checkProto3JsonNames(
        encodeRequest: () => <String, Object?>{'1': 'd'},
      ),
      throwsA(
        isA<UnsupportedError>().having(
          (UnsupportedError e) => e.message,
          'message',
          contains('omit_field_names'),
        ),
      ),
    );
    expect(
      () => RestTransport.checkProto3JsonNames(
        encodeEnum: () => <String, Object?>{'direction': 2},
      ),
      throwsUnsupportedError,
    );
    RestTransport.checkProto3JsonNames();
  });
}
