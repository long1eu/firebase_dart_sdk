import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/core/filter/filter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_purpose.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as proto_v1;
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;
import 'package:test/test.dart';

import '../../../../util/test_util.dart';

/// Cases of the iOS SDK's `Firestore/core/test/unit/remote/serializer_test.cc`
/// that neither the Android nor the JS tests have.
void main() {
  final RemoteSerializer serializer = RemoteSerializer(
    DatabaseId.forDatabase('p', 'd'),
  );

  test('testEncodesNotInFilterWithNull', () {
    final FieldFilter model = filter('item.tags', 'not-in', <Object?>[null]);

    final proto.StructuredQuery_Filter encoded = serializer.encodeFilter(model);
    // A `not-in [null]` stays a field filter: only `== null` and `!= null`
    // become unary filters.
    expect(encoded.hasFieldFilter(), isTrue);
    expect(encoded.fieldFilter.field_1.fieldPath, 'item.tags');
    expect(
      encoded.fieldFilter.op,
      proto.StructuredQuery_FieldFilter_Operator.NOT_IN,
    );
    expect(
      encoded.fieldFilter.value.arrayValue.values.single.hasNullValue(),
      isTrue,
    );
    expect(serializer.decodeFilter(encoded), model);
  });

  test('testRoundTripsSpecialFieldNames', () {
    final Mutation model = setMutation('collection/key', <String, Object?>{
      'field': 'field 1',
      'field.dot': 2,
      'field\\slash': 3,
    });

    final proto.Write encoded = serializer.encodeMutation(model);
    expect(encoded.update.fields.keys.toSet(), <String>{
      'field',
      'field.dot',
      'field\\slash',
    });
    expect(encoded.update.fields['field.dot']!.integerValue.toInt(), 2);
    expect(serializer.decodeMutation(encoded), model);
  });

  test('testEncodeExpectedCountSkippedWithoutResumeToken', () {
    final QueryData model = QueryData(
      Query(ResourcePath.fromString('docs')).toTarget(),
      1,
      0,
      QueryPurpose.listen,
      SnapshotVersion.none,
      Uint8List(0),
      1234,
    );

    final proto_v1.Target encoded = serializer.encodeTarget(model);
    expect(encoded.hasExpectedCount(), isFalse);
    expect(encoded.hasResumeToken(), isFalse);
    expect(encoded.hasReadTime(), isFalse);
  });

  test('testDecodesMutationResultWithNoUpdateTime', () {
    final MutationResult result = serializer.decodeMutationResult(
      proto.WriteResult(),
      version(10000000),
    );
    expect(result.version, version(10000000));
    expect(result.transformResults, isEmpty);
  });

  test('testDecodeMaybeDocWithoutFoundOrMissingSetShouldFail', () {
    expect(
      () => serializer.decodeMaybeDocument(proto.BatchGetDocumentsResponse()),
      throwsArgumentError,
    );
  });

  test('testDecodesVersionWithNoReadTime', () {
    expect(
      serializer.decodeVersionFromListenResponse(proto.ListenResponse()),
      SnapshotVersion.none,
    );
  });

  test('testDecodesVersionWithTargets', () {
    // The read time does not apply to the whole stream when the change names
    // targets.
    final proto.ListenResponse response = proto.ListenResponse(
      targetChange: proto.TargetChange(
        targetIds: <int>[1],
        readTime: serializer.encodeVersion(version(123456789)),
      ),
    );
    expect(
      serializer.decodeVersionFromListenResponse(response),
      SnapshotVersion.none,
    );
  });
}
