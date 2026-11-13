// Regression tests for the crashes found by the fuzz tests of this directory,
// one per fix.

import 'dart:convert';

import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_builder.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/order_by.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/document_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/geo_point.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/index/firestore_index_value_writer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/index/index_byte_encoder.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as pb;
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;
import 'package:fixnum/fixnum.dart';
import 'package:test/test.dart';

import '../../util/fuzz.dart';
import '../../util/property_model.dart';
import '../../util/test_util.dart' as util;

final RemoteSerializer remote = RemoteSerializer(modelDatabaseId);
final BundleSerializer bundle = BundleSerializer(remote);

const String root = 'projects/project/databases/(default)/documents';

Map<String, Object?> snapshotJson(String bundle, {String name = 'q1'}) =>
    <String, Object?>{
      'type': QuerySnapshot.jsonType,
      'bundleSource': 'QuerySnapshot',
      'bundleName': name,
      'bundle': bundle,
    };

String element(String json) => '${utf8.encode(json).length}$json';

const String metadata =
    '{"metadata":{"id":"b","createTime":{"seconds":1,"nanos":0},"version":1,'
    '"totalDocuments":1,"totalBytes":1}}';

void main() {
  group('RemoteSerializer', () {
    test(
      'a timestamp out of range is an ArgumentError, also without asserts',
      () {
        for (final (int seconds, int nanos) in <(int, int)>[
          (0, -1),
          (0, 1000000000),
          (-62135596801, 0),
          (253402300800, 0),
          (9223372036854775807, 0),
        ]) {
          expect(
            () => remote.decodeValue(
              pb.Value()
                ..timestampValue = (proto.Timestamp()
                  ..seconds = Int64(seconds)
                  ..nanos = nanos),
            ),
            throwsArgumentError,
            reason: '$seconds s, $nanos ns',
          );
        }
        expect(
          remote.decodeTimestamp(
            proto.Timestamp()
              ..seconds = Int64(253402300799)
              ..nanos = 999999999,
          ),
          const Timestamp(253402300799, 999999999),
        );
      },
    );

    test(
      'a geo point out of range is an ArgumentError, also without asserts',
      () {
        for (final (double latitude, double longitude) in <(double, double)>[
          (90.5, 0),
          (0, -180.5),
          (double.nan, 0),
          (0, double.infinity),
        ]) {
          expect(
            () => remote.decodeValue(
              pb.Value()
                ..geoPointValue = (proto.LatLng()
                  ..latitude = latitude
                  ..longitude = longitude),
            ),
            throwsArgumentError,
            reason: '($latitude, $longitude)',
          );
        }
      },
    );

    test('a numeric transform of a value that is not a number fails an '
        'internal assertion, not a cast', () {
      for (final void Function(pb.DocumentTransform_FieldTransform) set
          in <void Function(pb.DocumentTransform_FieldTransform)>[
            (pb.DocumentTransform_FieldTransform t) =>
                t.increment = pb.Value()..booleanValue = true,
            (pb.DocumentTransform_FieldTransform t) =>
                t.minimum = pb.Value()..stringValue = '1',
            (pb.DocumentTransform_FieldTransform t) =>
                t.maximum = pb.Value()..nullValue = proto.NullValue.NULL_VALUE,
          ]) {
        final pb.DocumentTransform_FieldTransform transform =
            pb.DocumentTransform_FieldTransform()..fieldPath = 'a';
        set(transform);
        final pb.Write write = pb.Write()
          ..update = (pb.Document()..name = '$root/c/d')
          ..updateTransforms.add(transform);
        expect(
          () => remote.decodeMutation(write),
          throwsA(
            isA<AssertionError>().having(
              (AssertionError e) => '${e.message}',
              'message',
              'NumericTransformOperation expects a numeric operand',
            ),
          ),
        );
      }
    });
  });

  test(
    'LocalSerializer: a batch without writes fails an internal assertion',
    () {
      // MutationBatch checked it with an assert only, which production code
      // skips: the error must come from hardAssert.
      Object? error;
      StackTrace? stackTrace;
      try {
        LocalSerializer(remote).decodeMutationBatch(
          proto.WriteBatch()
            ..batchId = 1
            ..localWriteTime = (proto.Timestamp()..seconds = Int64(1)),
        );
      } catch (e, s) {
        error = e;
        stackTrace = s;
      }
      expect(
        error,
        isA<AssertionError>().having(
          (AssertionError e) => '${e.message}',
          'message',
          'Cannot create an empty mutation batch',
        ),
      );
      expect(
        isCleanRejection(error!, stackTrace!),
        isTrue,
        reason: '$stackTrace',
      );
    },
  );

  group('BundleSerializer', () {
    test(
      'the error about a deeply nested value does not overflow the stack',
      () {
        // An unknown value type whose content is nested 100000 levels deep: the
        // error message printed all of it.
        final Object? deep = jsonDecode(
          '{"unknownValue":${'[' * 100000}${']' * 100000}}',
        );
        expect(
          () => bundle.decodeValue(deep! as Map<String, dynamic>),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError e) => '${e.message}'.length,
              'message length',
              lessThan(300),
            ),
          ),
        );
      },
    );

    test('a timestamp out of range is an ArgumentError', () {
      for (final Object timestamp in <Object>[
        '0000-01-01T00:00:00Z',
        <String, Object?>{'seconds': 253402300800},
        <String, Object?>{'seconds': 1, 'nanos': -1},
        <String, Object?>{'seconds': 1, 'nanos': 1000000000},
      ]) {
        expect(
          () => bundle.decodeValue(<String, dynamic>{
            'timestampValue': timestamp,
          }),
          throwsArgumentError,
          reason: '$timestamp',
        );
      }
    });

    test('an integer that is not finite is an ArgumentError', () {
      for (final Object integer in <Object>['1e400', '-1e400', 'NaN']) {
        expect(
          () => bundle.decodeValue(<String, dynamic>{'integerValue': integer}),
          throwsArgumentError,
          reason: '$integer',
        );
      }
      expect(
        () => bundle.decodeBundleMetadata(<String, dynamic>{
          'id': 'b',
          'createTime': <String, Object?>{'seconds': 1},
          'version': 1,
          'totalDocuments': '1e400',
          'totalBytes': 1,
        }),
        throwsArgumentError,
      );
    });
  });

  group('snapshot fromJson', () {
    void expectInvalid(Map<String, Object?> json, {bool document = false}) {
      // The cause, if any, is a validation error: not a TypeError of a cast
      // or a stack overflow.
      expect(
        () => document
            ? DocumentSnapshot<Map<String, Object?>>.fromJson(
                modelFirestore,
                json,
              )
            : QuerySnapshot<Map<String, Object?>>.fromJson(
                modelFirestore,
                json,
              ),
        throwsA(
          isA<FirestoreError>()
              .having(
                (FirestoreError e) => e.code,
                'code',
                FirestoreErrorCode.invalidArgument,
              )
              .having(
                (FirestoreError e) => e.cause,
                'cause',
                anyOf(
                  isNull,
                  isFormatException,
                  isArgumentError,
                  // A hardAssert of the serializer, as upstream.
                  isA<AssertionError>(),
                ),
              ),
        ),
      );
    }

    test('a document that lacks a field the query orders by', () {
      final Query query = Query(util.path('c')).orderBy(
        OrderBy.getInstance(OrderByDirection.ascending, util.field('a')),
      );
      final String withoutField =
          (BundleBuilder(remote, 'b')..addNamedQuery('q1', query, <Document>[
                util.doc('c/1', 1, <String, Object?>{'a': 1}),
                util.doc('c/2', 1, <String, Object?>{'b': 1}),
              ], SnapshotVersion.none))
              .build();
      expectInvalid(snapshotJson(withoutField));
    });

    test('a bundle name that is not a valid path', () {
      for (final String name in <String>['c//d', 'a//b/c/d']) {
        expectInvalid(<String, Object?>{
          'type': DocumentSnapshot.jsonType,
          'bundleSource': 'DocumentSnapshot',
          'bundleName': name,
          'bundle': '',
        }, document: true);
      }
    });

    test('elements of the wrong JSON type', () {
      for (final String hostile in <String>[
        element('{"metadata":5}'),
        '${element(metadata)}${element('{"document":[]}')}',
        '${element(metadata)}${element('{"namedQuery":"q"}')}',
        '${element(metadata)}${element('{"documentMetadata":1}')}',
      ]) {
        expectInvalid(snapshotJson(hostile));
      }
    });

    test('a document field that cannot be decoded', () {
      const String document =
          '{"document":{"name":"$root/c/d","updateTime":{"seconds":1},'
          '"fields":{"a":{"referenceValue":"x"}}}}';
      expectInvalid(<String, Object?>{
        'type': DocumentSnapshot.jsonType,
        'bundleSource': 'DocumentSnapshot',
        'bundleName': 'c/d',
        'bundle': '${element(metadata)}${element(document)}',
      }, document: true);
    });

    test('an unknown element deeply nested is reported briefly', () {
      final String deep = '{"x":${'[' * 100000}${']' * 100000}}';
      expect(
        () => QuerySnapshot<Map<String, Object?>>.fromJson(
          modelFirestore,
          snapshotJson('${element(metadata)}${element(deep)}'),
        ),
        throwsA(
          isA<FirestoreError>()
              .having(
                (FirestoreError e) => e.message.length,
                'message length',
                lessThan(300),
              )
              .having(
                (FirestoreError e) => e.cause,
                'cause',
                isFormatException,
              ),
        ),
      );
    });
  });

  group('GeoPoint', () {
    test('compareTo agrees with == on -0.0', () {
      expect(const GeoPoint(0, -0.0), const GeoPoint(0, 0));
      expect(const GeoPoint(0, -0.0).compareTo(const GeoPoint(0, 0)), 0);
      expect(const GeoPoint(-0.0, 1).compareTo(const GeoPoint(0, 1)), 0);
      expect(const GeoPoint(-0.0, 1).compareTo(const GeoPoint(0, 2)), -1);
    });

    test('the index encodes -0.0 like 0.0', () {
      List<int> encode(GeoPoint point) {
        final IndexByteEncoder encoder = IndexByteEncoder();
        FirestoreIndexValueWriter.instance.writeIndexValue(
          util.wrap(point),
          encoder.forKind(SegmentKind.ascending),
        );
        return encoder.encodedBytes;
      }

      expect(encode(const GeoPoint(-0.0, -0.0)), encode(const GeoPoint(0, 0)));
    });
  });
}
