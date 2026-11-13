// Production Firestore writes the double -0.0 as the JSON number `-0` (verify_production check 8). jsonDecode reads
// it as the int 0, so -0.0 came back as 0.0 over the web transport. The bodies below are what production sent on
// 2026-11-13 for a document with -0.0, 0.0 and empty bytes, at the top level and in an array (get, RunQuery and
// BatchGet sent the same values).

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/empty_credentials_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/database_info.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/channel_options_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/firestore_transport.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/web/json_decode.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/web/web_channel_transport.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as proto;
import 'package:test/test.dart';

import 'fake_http_client.dart';

const String database = 'projects/demo-test/databases/(default)';
const String name = '$database/documents/vp_values/by_web';

/// The fields as production sends them (whitespace as in its REST answers).
const String fields = '''
{
    "nested": {
      "arrayValue": {
        "values": [
          {
            "doubleValue": -0
          },
          {
            "bytesValue": ""
          }
        ]
      }
    },
    "negativeZero": {
      "doubleValue": -0
    },
    "zero": {
      "doubleValue": 0
    },
    "emptyBytes": {
      "bytesValue": ""
    }
  }''';

const String batchGetBody =
    '''
[{
  "found": {
    "name": "$name",
    "fields": $fields,
    "createTime": "2026-11-13T22:31:38.593804Z",
    "updateTime": "2026-11-13T22:31:38.593804Z"
  },
  "readTime": "2026-11-13T22:31:40.000000Z"
}
]''';

bool isNegativeZero(Object? v) => v is double && v == 0 && v.isNegative;

void main() {
  group('decodeBackendJson', () {
    test('keeps the sign of -0', () {
      expect(isNegativeZero(decodeBackendJson('-0')), isTrue);
      expect(
        isNegativeZero((decodeBackendJson('[-0]')! as List<Object?>)[0]),
        isTrue,
      );
      expect(
        isNegativeZero(
          (decodeBackendJson('{"doubleValue": -0}')!
              as Map<String, Object?>)['doubleValue'],
        ),
        isTrue,
      );
      expect(
        isNegativeZero((decodeBackendJson('[-0,1]')! as List<Object?>)[0]),
        isTrue,
      );
    });

    test('leaves other numbers and strings alone', () {
      expect(decodeBackendJson('[0, -0.5, -0e3, -0.25e1, -10, -5]'), <Object?>[
        0,
        -0.5,
        -0.0,
        -2.5,
        -10,
        -5,
      ]);
      expect(decodeBackendJson('[0]'), <Object?>[0]);
      expect((decodeBackendJson('[0]')! as List<Object?>)[0], isA<int>());
      // "-0" inside strings, also after an escaped quote, is text.
      expect(
        decodeBackendJson(r'{"a": "2026-01-02T-0", "b": "x\"-0", "c": -0}'),
        <String, Object?>{'a': '2026-01-02T-0', 'b': 'x"-0', 'c': -0.0},
      );
      expect(
        isNegativeZero(
          (decodeBackendJson(r'{"b": "x\\", "c": -0}')!
              as Map<String, Object?>)['c'],
        ),
        isTrue,
        reason: 'an escaped backslash ends the string',
      );
    });
  });

  group('the web transport', () {
    late FakeHttpClient http;
    late WebChannelTransport transport;
    final RemoteSerializer serializer = RemoteSerializer(
      DatabaseId.forProject('demo-test'),
    );

    setUp(() {
      http = FakeHttpClient();
      final DatabaseId databaseId = DatabaseId.forProject('demo-test');
      transport = WebChannelTransport(
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
          credentialsProvider: EmptyCredentialsProvider(),
        ),
      );
    });

    void expectValues(Document doc) {
      expect(
        isNegativeZero(
          doc.getFieldValue(FieldPath.fromSingleSegment('negativeZero')),
        ),
        isTrue,
      );
      final Object? zero = doc.getFieldValue(
        FieldPath.fromSingleSegment('zero'),
      );
      expect(
        zero is double && zero == 0 && !zero.isNegative,
        isTrue,
        reason: '$zero',
      );
      final Object? emptyBytes = doc.getFieldValue(
        FieldPath.fromSingleSegment('emptyBytes'),
      );
      expect(
        emptyBytes,
        isNotNull,
        reason: 'empty bytes survive (as an empty Blob)',
      );
      expect(emptyBytes.toString(), contains('Blob'));
      final List<Object?> nested =
          doc.getFieldValue(FieldPath.fromSingleSegment('nested'))!
              as List<Object?>;
      expect(isNegativeZero(nested[0]), isTrue);
      expect(nested[1].toString(), emptyBytes.toString());
    }

    test('REST: BatchGet keeps -0.0 and empty bytes', () async {
      final Future<List<proto.BatchGetDocumentsResponse>> responses = transport
          .startCall(
            FirestoreRpc.batchGetDocuments,
            Stream<proto.BatchGetDocumentsRequest>.value(
              proto.BatchGetDocumentsRequest()
                ..database = database
                ..documents.add(name),
            ),
          )
          .toList();
      (await http.next()).respond(200, body: batchGetBody);
      final proto.BatchGetDocumentsResponse response = (await responses).single;

      final proto.Value value = response.found.fields['negativeZero']!;
      expect(value.whichValueType(), proto.Value_ValueType.doubleValue);
      expect(value.doubleValue.isNegative, isTrue);
      expect(
        response.found.fields['emptyBytes']!.whichValueType(),
        proto.Value_ValueType.bytesValue,
      );
      expect(response.found.fields['emptyBytes']!.bytesValue, isEmpty);

      final MaybeDocument doc = serializer.decodeMaybeDocument(response);
      expectValues(doc as Document);
    });

    test(
      'WebChannel: a Listen document change keeps -0.0 and empty bytes',
      () async {
        final StreamController<proto.ListenRequest> requests =
            StreamController<proto.ListenRequest>();
        final List<proto.ListenResponse> responses = <proto.ListenResponse>[];
        final ResponseStream<proto.ListenResponse> call = transport.startCall(
          FirestoreRpc.listen,
          requests.stream,
        );
        call.listen(responses.add);
        requests.add(
          proto.ListenRequest()
            ..database = database
            ..addTarget = (proto.Target()..targetId = 2),
        );
        (await http.next()).respond(
          200,
          body: '52\n[[0,["c","4ApGpUebBDNnT9YbQeHo6g==","",8,12,30000]]]',
        );
        final FakeRequest back = await http.next();
        back.stream(200);
        back.add(
          chunk(
            '[[1,[{"documentChange":{"document":{"name":"$name","fields":$fields,'
            '"createTime":"2026-11-13T22:31:38.593804Z","updateTime":"2026-11-13T22:31:38.593804Z"},'
            '"targetIds":[2]}}]]]',
          ),
        );
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        final proto.Document document =
            responses.single.documentChange.document;
        expect(document.fields['negativeZero']!.doubleValue.isNegative, isTrue);
        expect(
          document
              .fields['nested']!
              .arrayValue
              .values[0]
              .doubleValue
              .isNegative,
          isTrue,
        );
        expect(
          document.fields['nested']!.arrayValue.values[1].whichValueType(),
          proto.Value_ValueType.bytesValue,
        );
        await call.cancel();
        await requests.close();
      },
    );
  });
}
