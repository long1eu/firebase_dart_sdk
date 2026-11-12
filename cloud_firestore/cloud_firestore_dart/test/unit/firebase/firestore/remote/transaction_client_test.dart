import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/empty_credentials_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/channel_options_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/datastore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;
import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart' hide ResponseStream;
import 'package:test/test.dart';
import 'unused_transport.dart';

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

/// Serves a canned BatchGetDocuments response stream that the test controls.
class _FakeClient extends FirestoreClient {
  _FakeClient(this.responses)
      : super(
          UnusedTransport(),
          ChannelOptionsProvider(
            databaseId: DatabaseId.forProject('p'),
            credentialsProvider: EmptyCredentialsProvider(),
          ),
        );

  final StreamController<proto.BatchGetDocumentsResponse> responses;

  @override
  ResponseStream<proto.BatchGetDocumentsResponse> batchGetDocuments(
    proto.BatchGetDocumentsRequest request, {
    CallOptions? options,
  }) =>
      ResponseStream<proto.BatchGetDocumentsResponse>(
          _FakeResponse(), responses.stream);
}

proto.BatchGetDocumentsResponse _missing(String path) {
  return proto.BatchGetDocumentsResponse(
    missing: 'projects/p/databases/(default)/documents/$path',
    readTime: proto.Timestamp(seconds: Int64(1)),
  );
}

void main() {
  final DocumentKey a = DocumentKey.fromPathString('rooms/a');
  final DocumentKey b = DocumentKey.fromPathString('rooms/b');

  late StreamController<proto.BatchGetDocumentsResponse> responses;
  late TransactionClient client;

  setUp(() {
    responses = StreamController<proto.BatchGetDocumentsResponse>();
    client = TransactionClient(
        _FakeClient(responses), RemoteSerializer(DatabaseId.forProject('p')));
  });

  tearDown(() => responses.close());

  test(
      'lookup completes once every document was received, without waiting '
      'for the server to close the stream', () async {
    // The stream is intentionally never closed.
    final Future<List<MaybeDocument>> result =
        client.lookup(<DocumentKey>[a, b]);
    // Responses may arrive in any order.
    responses.add(_missing('rooms/b'));
    responses.add(_missing('rooms/a'));

    final List<MaybeDocument> docs =
        await result.timeout(const Duration(seconds: 2));
    expect(docs.map((MaybeDocument d) => d.key), <DocumentKey>[a, b]);
  });

  test('lookup with a repeated key completes after one response per document',
      () async {
    final Future<List<MaybeDocument>> result =
        client.lookup(<DocumentKey>[a, a]);
    responses.add(_missing('rooms/a'));

    final List<MaybeDocument> docs =
        await result.timeout(const Duration(seconds: 2));
    expect(docs.map((MaybeDocument d) => d.key), <DocumentKey>[a, a]);
  });

  test('lookup fails with the error reported by the stream', () async {
    final Future<List<MaybeDocument>> result = client.lookup(<DocumentKey>[a]);
    responses.addError(const GrpcError.permissionDenied('no'));
    await expectLater(result, throwsA(anything));
  });
}
