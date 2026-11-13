import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/credentials_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/channel_options_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/datastore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/firestore_transport.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/grpc_status.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as proto_v1;
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;
import 'package:fixnum/fixnum.dart';
import 'package:protobuf/protobuf.dart';
import 'package:test/test.dart';

class _CountingCredentials implements CredentialsProvider {
  int invalidations = 0;

  @override
  Future<String?> get token async => null;

  @override
  void invalidateToken() => invalidations++;

  @override
  Stream<User> get onChange => const Stream<User>.empty();
}

class _Response implements Response {
  @override
  Future<Map<String, String>> get headers async => <String, String>{};

  @override
  Future<Map<String, String>> get trailers async => <String, String>{};

  @override
  Future<void> cancel() async {}
}

/// Answers every call with [error].
class _FailingTransport implements FirestoreTransport {
  _FailingTransport(this.error);

  final Object error;

  @override
  ResponseStream<Res> startCall<
    Req extends GeneratedMessage,
    Res extends GeneratedMessage
  >(FirestoreRpc<Req, Res> rpc, Stream<Req> requests, {CallOptions? options}) {
    return ResponseStream<Res>(_Response(), Stream<Res>.error(error));
  }

  @override
  Future<void> shutdown() async {}
}

FirestoreClient _client(Object error, _CountingCredentials credentials) {
  return FirestoreClient(
    _FailingTransport(error),
    ChannelOptionsProvider(
      databaseId: DatabaseId.forProject('p'),
      credentialsProvider: credentials,
    ),
  );
}

proto_v1.Value _vectorProto(List<proto_v1.Value> elements) {
  final proto.MapValue map = proto.MapValue.create();
  map.fields[VectorFieldValue.typeKey] = proto_v1.Value.create()
    ..stringValue = VectorFieldValue.vectorTypeValue;
  map.fields[VectorFieldValue.vectorKey] = proto_v1.Value.create()
    ..arrayValue = (proto.ArrayValue.create()..values.addAll(elements));
  return proto_v1.Value.create()..mapValue = map;
}

void main() {
  group('FirestoreClient error mapping', () {
    test('UNAUTHENTICATED invalidates the token and keeps its code', () async {
      final _CountingCredentials credentials = _CountingCredentials();
      final FirestoreClient client = _client(
        const GrpcError.custom(StatusCode.unauthenticated, 'expired'),
        credentials,
      );

      await expectLater(
        client.runQuery(proto.RunQueryRequest()).toList(),
        throwsA(
          isA<FirestoreError>()
              .having(
                (FirestoreError e) => e.code,
                'code',
                FirestoreErrorCode.unauthenticated,
              )
              .having((FirestoreError e) => e.message, 'message', 'expired'),
        ),
      );
      expect(credentials.invalidations, 1);
    });

    test(
      'other gRPC errors keep their code and leave the token alone',
      () async {
        final _CountingCredentials credentials = _CountingCredentials();
        final FirestoreClient client = _client(
          const GrpcError.custom(StatusCode.permissionDenied, 'nope'),
          credentials,
        );

        await expectLater(
          client.batchGetDocuments(proto.BatchGetDocumentsRequest()).toList(),
          throwsA(
            isA<FirestoreError>().having(
              (FirestoreError e) => e.code,
              'code',
              FirestoreErrorCode.permissionDenied,
            ),
          ),
        );
        expect(credentials.invalidations, 0);
      },
    );

    test('a non-gRPC failure becomes an unknown FirestoreError', () async {
      final _CountingCredentials credentials = _CountingCredentials();
      final FirestoreClient client = _client(
        StateError('socket went away'),
        credentials,
      );

      await expectLater(
        client.runQuery(proto.RunQueryRequest()).toList(),
        throwsA(
          isA<FirestoreError>()
              .having(
                (FirestoreError e) => e.code,
                'code',
                FirestoreErrorCode.unknown,
              )
              .having(
                (FirestoreError e) => e.message,
                'message',
                contains('socket went away'),
              ),
        ),
      );
      expect(credentials.invalidations, 0);
    });
  });

  group('Datastore error classification', () {
    test('OK is not an error', () {
      expect(
        () => Datastore.isPermanentError(FirestoreErrorCode.ok),
        throwsArgumentError,
      );
    });

    test('transient and permanent codes', () {
      for (final FirestoreErrorCode code in <FirestoreErrorCode>[
        FirestoreErrorCode.cancelled,
        FirestoreErrorCode.unknown,
        FirestoreErrorCode.deadlineExceeded,
        FirestoreErrorCode.resourceExhausted,
        FirestoreErrorCode.internal,
        FirestoreErrorCode.unavailable,
        FirestoreErrorCode.unauthenticated,
      ]) {
        expect(Datastore.isPermanentError(code), isFalse, reason: '$code');
      }
      for (final FirestoreErrorCode code in <FirestoreErrorCode>[
        FirestoreErrorCode.invalidArgument,
        FirestoreErrorCode.notFound,
        FirestoreErrorCode.alreadyExists,
        FirestoreErrorCode.permissionDenied,
        FirestoreErrorCode.failedPrecondition,
        FirestoreErrorCode.aborted,
        FirestoreErrorCode.outOfRange,
        FirestoreErrorCode.unimplemented,
        FirestoreErrorCode.dataLoss,
      ]) {
        expect(Datastore.isPermanentError(code), isTrue, reason: '$code');
      }
    });

    test('ABORTED is permanent for reads but retried for writes', () {
      const GrpcError aborted = GrpcError.custom(StatusCode.aborted);
      expect(Datastore.isPermanentGrpcError(aborted), isTrue);
      expect(Datastore.isPermanentWriteError(aborted), isFalse);
      expect(
        Datastore.isPermanentWriteError(
          const GrpcError.custom(StatusCode.notFound),
        ),
        isTrue,
      );
    });
  });

  group('vector decoding', () {
    final RemoteSerializer serializer = RemoteSerializer(
      DatabaseId.forProject('p'),
    );

    test('integer elements are read as doubles', () {
      final FieldValue value = serializer.decodeValue(
        _vectorProto(<proto_v1.Value>[
          proto_v1.Value.create()..doubleValue = 1.5,
          proto_v1.Value.create()..integerValue = Int64(2),
        ]),
      );
      expect(value, isA<VectorFieldValue>());
      expect((value as VectorFieldValue).internalValue, <double>[1.5, 2.0]);
    });

    test('a vector map with a non-number element is a plain map', () {
      final FieldValue value = serializer.decodeValue(
        _vectorProto(<proto_v1.Value>[
          proto_v1.Value.create()..stringValue = 'x',
        ]),
      );
      expect(value, isNot(isA<VectorFieldValue>()));
      expect(value, isA<ObjectValue>());
    });

    test('a vector type without an array value is a plain map', () {
      final proto.MapValue map = proto.MapValue.create();
      map.fields[VectorFieldValue.typeKey] = proto_v1.Value.create()
        ..stringValue = VectorFieldValue.vectorTypeValue;
      map.fields[VectorFieldValue.vectorKey] = proto_v1.Value.create()
        ..stringValue = 'not an array';
      final FieldValue value = serializer.decodeValue(
        proto_v1.Value.create()..mapValue = map,
      );
      expect(value, isA<ObjectValue>());
    });
  });
}
