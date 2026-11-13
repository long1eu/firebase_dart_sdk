// Security review N5 (and L4): the web transport reads REST responses and WebChannel forward-channel answers whole.
// They are bounded (WebHttpResponse.maxBodyLength); a larger body fails the call with RESOURCE_EXHAUSTED, the request
// is aborted and the rest is not read.

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/empty_credentials_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/database_info.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/channel_options_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/firestore_transport.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/web/rest_transport.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/web/web_http_client.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/grpc_status.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as proto;
import 'package:test/test.dart';

import 'fake_http_client.dart';

const String database = 'projects/p/databases/(default)';

Matcher get _resourceExhausted => isA<GrpcError>().having(
  (GrpcError e) => e.code,
  'code',
  StatusCode.resourceExhausted,
);

void main() {
  test('the limit allows 16 documents of 16 MiB, as the WebChannel chunks', () {
    expect(WebHttpResponse.maxBodyLength, 256 * 1024 * 1024);
  });

  test('readAll stops at the limit without reading the rest', () async {
    int pieces = 0;
    final StreamController<String> body = StreamController<String>(
      onListen: () {},
    );
    final WebHttpResponse response = WebHttpResponse(
      200,
      const <String, String>{},
      body.stream.map((String piece) {
        pieces++;
        return piece;
      }),
    );
    final Future<String> text = response.readAll(maxLength: 10);
    body
      ..add('12345')
      ..add('67890')
      ..add('x')
      ..add('never read');
    await expectLater(text, throwsA(_resourceExhausted));
    expect(pieces, 3);
    expect(body.hasListener, isFalse);

    expect(
      await WebHttpResponse(
        200,
        const <String, String>{},
        Stream<String>.fromIterable(<String>['12345', '67890']),
      ).readAll(maxLength: 10),
      '1234567890',
    );
  });

  test(
    'a REST response above the limit fails the call and aborts the request',
    () async {
      final FakeHttpClient http = FakeHttpClient();
      final DatabaseId databaseId = DatabaseId.forProject('p');
      final RestTransport transport = RestTransport(
        http,
        DatabaseInfo(databaseId, 'key', 'example.test', sslEnabled: true),
        ChannelOptionsProvider(
          databaseId: databaseId,
          credentialsProvider: EmptyCredentialsProvider(),
        ),
      );
      final Future<List<proto.RunQueryResponse>> responses = transport
          .startCall(
            FirestoreRpc.runQuery,
            Stream<proto.RunQueryRequest>.value(
              proto.RunQueryRequest()..parent = '$database/documents',
            ),
          )
          .toList();
      final FakeRequest request = await http.next();
      request.stream(200);
      // 1 MiB pieces, the same string each time: only the references are buffered.
      final String mebibyte = 'a' * (1024 * 1024);
      for (int i = 0; i < 256; i++) {
        request.add(mebibyte);
      }
      request.add('one more character');
      await expectLater(responses, throwsA(_resourceExhausted));
      expect(request.aborted, isTrue);
    },
  );
}
