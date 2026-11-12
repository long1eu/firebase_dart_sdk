import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/empty_credentials_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/call_release.dart';
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

  int cancelCount = 0;

  @override
  Future<void> cancel() async {
    cancelCount++;
  }
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
          callReleaser:
              CallReleaser(gracePeriod: const Duration(milliseconds: 200)),
        );

  final StreamController<proto.BatchGetDocumentsResponse> responses;
  final _FakeResponse call = _FakeResponse();

  @override
  ResponseStream<proto.BatchGetDocumentsResponse> batchGetDocuments(
    proto.BatchGetDocumentsRequest request, {
    CallOptions? options,
  }) =>
      ResponseStream<proto.BatchGetDocumentsResponse>(
          call, responses.stream);
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
  late _FakeClient fakeClient;
  late TransactionClient client;

  setUp(() {
    responses = StreamController<proto.BatchGetDocumentsResponse>();
    fakeClient = _FakeClient(responses);
    client = TransactionClient(
        fakeClient, RemoteSerializer(DatabaseId.forProject('p')));
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

  test(
      'lookup does not cancel a call that the server closes after the last '
      'document', () async {
    // Cancelling resets the HTTP/2 stream. When the trailers of the call are
    // already on their way, package:http2 answers them with a connection error
    // that fails every other call on the channel (a commit that was applied
    // then looks failed and its transaction is retried).
    final Future<List<MaybeDocument>> result = client.lookup(<DocumentKey>[a]);
    responses.add(_missing('rooms/a'));
    await result.timeout(const Duration(seconds: 2));
    expect(fakeClient.call.cancelCount, 0);

    await responses.close();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(fakeClient.call.cancelCount, 0);
  });

  test('lookup cancels a call that the server keeps open', () async {
    final Future<List<MaybeDocument>> result = client.lookup(<DocumentKey>[a]);
    responses.add(_missing('rooms/a'));
    await result.timeout(const Duration(seconds: 2));

    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(fakeClient.call.cancelCount, 1);
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
