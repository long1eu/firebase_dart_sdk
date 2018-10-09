// File created by
// Lung Razvan <long1eu>
// on 03/10/2018

import 'dart:typed_data';

import 'package:firebase_firestore/src/firebase/firestore/core/bound.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/document_reference.dart';
import 'package:firebase_firestore/src/firebase/firestore/field_value.dart'
    as firestore;
import 'package:firebase_firestore/src/firebase/firestore/geo_point.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_data.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_purpose.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/database_id.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/field_path.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/resource_path.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/snapshot_version.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/double_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/field_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/integer_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/null_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/reference_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/watch_change.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/watch_stream.dart';
import 'package:firebase_firestore/src/firebase/timestamp.dart';
import 'package:firebase_firestore/src/proto/google/firestore/v1beta1/common.pb.dart'
    as proto;
import 'package:firebase_firestore/src/proto/google/firestore/v1beta1/document.pb.dart'
    as proto;
import 'package:firebase_firestore/src/proto/google/firestore/v1beta1/firestore.pb.dart'
    as proto;
import 'package:firebase_firestore/src/proto/google/firestore/v1beta1/query.pb.dart'
    as proto;
import 'package:firebase_firestore/src/proto/google/firestore/v1beta1/write.pb.dart'
    as proto;
import 'package:firebase_firestore/src/proto/google/protobuf/struct.pbenum.dart'
    as proto;
import 'package:firebase_firestore/src/proto/google/protobuf/timestamp.pb.dart'
    as proto;
import 'package:firebase_firestore/src/proto/google/protobuf/wrappers.pb.dart'
    as proto;
import 'package:firebase_firestore/src/proto/google/rpc/status.pb.dart'
    as proto;
import 'package:firebase_firestore/src/proto/google/type/latlng.pb.dart'
    as proto;
import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';

void main() {
  final Uint8List resumeToken = Uint8List.fromList(<int>[]);

  DatabaseId databaseId;
  RemoteSerializer serializer;

  setUp(() {
    databaseId = DatabaseId.forDatabase('p', 'd');
    serializer = RemoteSerializer(databaseId);
  });

  proto.Value valueBuilder() => proto.Value.create();

  void assertRoundTrip(
      FieldValue value, proto.Value data, ValueTypeCase typeCase) {
    final proto.Value actual = serializer.encodeValue(value);

    switch (typeCase) {
      case ValueTypeCase.nullValue:
        expect(actual.hasNullValue(), isTrue);
        break;
      case ValueTypeCase.booleanValue:
        expect(actual.hasBooleanValue(), isTrue);
        break;
      case ValueTypeCase.integerValue:
        expect(actual.hasIntegerValue(), isTrue);
        break;
      case ValueTypeCase.doubleValue:
        expect(actual.hasDoubleValue(), isTrue);
        break;
      case ValueTypeCase.timestampValue:
        expect(actual.hasTimestampValue(), isTrue);
        break;
      case ValueTypeCase.stringValue:
        expect(actual.hasStringValue(), isTrue);
        break;
      case ValueTypeCase.bytesValue:
        expect(actual.hasBytesValue(), isTrue);
        break;
      case ValueTypeCase.referenceValue:
        expect(actual.hasReferenceValue(), isTrue);
        break;
      case ValueTypeCase.geoPointValue:
        expect(actual.hasGeoPointValue(), isTrue);
        break;
      case ValueTypeCase.arrayValue:
        expect(actual.hasArrayValue(), isTrue);
        break;
      case ValueTypeCase.mapValue:
        expect(actual.hasMapValue(), isTrue);
        break;
    }

    expect(actual, data);
    expect(serializer.decodeValue(data), value);
  }

  void assertRoundTripForMutation(Mutation mutation, proto.Write data) {
    final proto.Write actualProto = serializer.encodeMutation(mutation);
    expect(actualProto, data);

    final Mutation actualMutation = serializer.decodeMutation(data);
    expect(actualMutation, mutation);
  }

  proto.StructuredQuery_Order defaultKeyOrder() {
    return (proto.StructuredQuery_Order.create()
      ..field_1 = (proto.StructuredQuery_FieldReference.create()
        ..fieldPath = DocumentKey.keyFieldName)
      ..direction = proto.StructuredQuery_Direction.ASCENDING)
      ..freeze();
  }

  /// Wraps the given query in [QueryData]. This is useful because the APIs
  /// we're testing accept [QueryData], but for the most part we're just testing
  /// variations on [Query].
  QueryData wrapQueryData(Query query) {
    return QueryData(query, 1, 2, QueryPurpose.listen, SnapshotVersion.none,
        WatchStream.emptyResumeToken);
  }

  void unaryFilterTest(Object equalityValue,
      proto.StructuredQuery_UnaryFilter_Operator unaryOperator) {
    final Query q = Query.atPath(ResourcePath.fromString('docs'))
        .filter(TestUtil.filter('prop', '==', equalityValue));
    final proto.Target actual = serializer.encodeTarget(wrapQueryData(q));

    final proto.StructuredQuery structuredQueryBuilder =
        proto.StructuredQuery.create()
          ..from.add(proto.StructuredQuery_CollectionSelector.create()
            ..collectionId = 'docs')
          ..where = (proto.StructuredQuery_Filter.create()
            ..unaryFilter = (proto.StructuredQuery_UnaryFilter.create()
              ..field_2 = (proto.StructuredQuery_FieldReference.create()
                ..fieldPath = 'prop')
              ..op = unaryOperator))
          ..orderBy.add(defaultKeyOrder());

    final proto.Target_QueryTarget queryBuilder =
        proto.Target_QueryTarget.create()
          ..parent = 'projects/p/databases/d'
          ..structuredQuery = structuredQueryBuilder;

    final proto.Target expected = proto.Target.create()
      ..query = queryBuilder
      ..targetId = 1
      ..freeze();

    expect(actual, expected);
    expect(q, serializer.decodeQueryTarget(serializer.encodeQueryTarget(q)));
  }

  test('testEncodesNull', () {
    final FieldValue value = NullValue.nullValue();
    final proto.Value data = valueBuilder()
      ..nullValue = proto.NullValue.NULL_VALUE
      ..freeze();
    assertRoundTrip(value, data, ValueTypeCase.nullValue);
  });

  test('testEncodesBoolean', () {
    final List<bool> tests = <bool>[true, false];
    for (bool test in tests) {
      final FieldValue value = TestUtil.wrap(test);
      final proto.Value data = valueBuilder()
        ..booleanValue = test
        ..freeze();
      assertRoundTrip(value, data, ValueTypeCase.booleanValue);
    }
  });

  test('testEncodesIntegers', () {
    final List<int> tests = <int>[
      IntegerValue.min,
      -100,
      -1,
      0,
      1,
      100,
      IntegerValue.max
    ];

    for (int test in tests) {
      final FieldValue value = TestUtil.wrap(test);
      final proto.Value data = valueBuilder()
        ..integerValue = Int64(test)
        ..freeze();
      assertRoundTrip(value, data, ValueTypeCase.integerValue);
    }
  });

  test('testEncodesDoubles', () {
    final List<double> tests = <double>[
      double.negativeInfinity,
      -double.maxFinite,
      IntegerValue.max * -1.0 - 1.0,
      -2.0,
      -1.1,
      -1.0,
      -double.minPositive,
      -DoubleValue.minNormal,
      -0.0,
      0.0,
      DoubleValue.minNormal,
      double.minPositive,
      0.1,
      1.1,
      IntegerValue.max * 1.0,
      double.maxFinite,
      double.infinity,
    ];

    for (double test in tests) {
      final FieldValue value = wrap(test);
      final proto.Value data = valueBuilder()
        ..doubleValue = test
        ..freeze();
      assertRoundTrip(value, data, ValueTypeCase.doubleValue);
    }
  });

  test('testEncodesStrings', () {
    final List<String> tests = <String>[
      '',
      'a',
      'abc def',
      'æ',
      '\0\ud7ff\ue000\uffff',
      '(╯°□°）╯︵ ┻━┻'
    ];
    for (String test in tests) {
      final FieldValue value = wrap(test);
      final proto.Value data = valueBuilder()
        ..stringValue = test
        ..freeze();
      assertRoundTrip(value, data, ValueTypeCase.stringValue);
    }
  });

  test('testEncodesDates', () {
    final DateTime date1 = DateTime.utc(2016, 1, 2, 10, 20, 50, 500);
    final DateTime date2 = DateTime.utc(2016, 6, 17, 10, 50, 15);

    final List<DateTime> tests = <DateTime>[date1, date2];

    final proto.Timestamp ts1 = proto.Timestamp.create()
      ..nanos = 500000000
      ..seconds = Int64(1451730050);

    final proto.Timestamp ts2 = proto.Timestamp.create()
      ..nanos = 0
      ..seconds = Int64(1466160615);

    final List<proto.Value> expected = <proto.Value>[
      valueBuilder()
        ..timestampValue = ts1
        ..freeze(),
      valueBuilder()
        ..timestampValue = ts2
        ..freeze()
    ];

    for (int i = 0; i < tests.length; i++) {
      final FieldValue value = wrap(tests[i]);
      assertRoundTrip(value, expected[i], ValueTypeCase.timestampValue);
    }
  });

  test('testEncodesGeoPoints', () {
    final FieldValue geoPoint = wrap(const GeoPoint(1.23, 4.56));
    final proto.Value data = valueBuilder()
      ..geoPointValue = (proto.LatLng.create()
        ..latitude = 1.23
        ..longitude = 4.56)
      ..freeze();

    assertRoundTrip(geoPoint, data, ValueTypeCase.geoPointValue);
  });

  test('testEncodesBlobs', () {
    final FieldValue blob = wrap(TestUtil.blob(<int>[0, 1, 2, 3]));
    final proto.Value data = valueBuilder()
      ..bytesValue = <int>[0, 1, 2, 3]
      ..freeze();

    assertRoundTrip(blob, data, ValueTypeCase.bytesValue);
  });

  test('testEncodesReferences', () {
    final DocumentReference value = ref('foo/bar');
    final FieldValue reference = wrap(value);
    final proto.Value data = valueBuilder()
      ..referenceValue =
          'projects/project/databases/(default)/documents/foo/bar'
      ..freeze();

    assertRoundTrip(reference, data, ValueTypeCase.referenceValue);
  });

  test('testEncodeArrays', () {
    final FieldValue model = wrap(<dynamic>[true, 'foo']);
    final proto.ArrayValue builder = proto.ArrayValue.create()
      ..values.add(valueBuilder()..booleanValue = true)
      ..values.add(valueBuilder()..stringValue = 'foo');

    final proto.Value data = valueBuilder()
      ..arrayValue = builder
      ..freeze();

    assertRoundTrip(model, data, ValueTypeCase.arrayValue);
  });

  test('testEncodesNestedObjects', () {
    final FieldValue model = TestUtil.wrapMap(map<dynamic>(<dynamic>[
      'b',
      true,
      'd',
      double.maxFinite,
      'i',
      1,
      'n',
      null,
      's',
      'foo',
      'a',
      <dynamic>[
        2,
        'bar',
        map<dynamic>(<dynamic>['b', false])
      ],
      'o',
      map<dynamic>(<dynamic>[
        'd',
        100,
        'nested',
        map<dynamic>(<dynamic>['e', IntegerValue.min])
      ])
    ]));

    proto.MapValue inner = proto.MapValue.create()
      ..fields.add(proto.MapValue_FieldsEntry.create()
        ..key = 'b'
        ..value = (valueBuilder()..booleanValue = false));

    final proto.ArrayValue array = proto.ArrayValue.create()
      ..values.add(valueBuilder()..integerValue = Int64(2))
      ..values.add(valueBuilder()..stringValue = 'bar')
      ..values.add(valueBuilder()..mapValue = inner);

    inner = proto.MapValue.create()
      ..fields.add(proto.MapValue_FieldsEntry.create()
        ..key = 'e'
        ..value = (valueBuilder()..integerValue = Int64(IntegerValue.min)));

    final proto.MapValue middle = proto.MapValue.create()
      ..fields.add(proto.MapValue_FieldsEntry.create()
        ..key = 'd'
        ..value = (valueBuilder()..integerValue = Int64(100)))
      ..fields.add(proto.MapValue_FieldsEntry.create()
        ..key = 'nested'
        ..value = (valueBuilder()..mapValue = inner));

    final proto.MapValue obj = proto.MapValue.create()
      ..fields.add(proto.MapValue_FieldsEntry.create()
        ..key = 'b'
        ..value = (valueBuilder()..booleanValue = true))
      ..fields.add(proto.MapValue_FieldsEntry.create()
        ..key = 'd'
        ..value = (valueBuilder()..doubleValue = double.maxFinite))
      ..fields.add(proto.MapValue_FieldsEntry.create()
        ..key = 'i'
        ..value = (valueBuilder()..integerValue = Int64(1)))
      ..fields.add(proto.MapValue_FieldsEntry.create()
        ..key = 'n'
        ..value = (valueBuilder()..nullValue = proto.NullValue.NULL_VALUE))
      ..fields.add(proto.MapValue_FieldsEntry.create()
        ..key = 's'
        ..value = (valueBuilder()..stringValue = 'foo'))
      ..fields.add(proto.MapValue_FieldsEntry.create()
        ..key = 'a'
        ..value = (valueBuilder()..arrayValue = array))
      ..fields.add(proto.MapValue_FieldsEntry.create()
        ..key = 'o'
        ..value = (valueBuilder()..mapValue = middle))
      ..fields.sort(
          (proto.MapValue_FieldsEntry a, proto.MapValue_FieldsEntry b) =>
              a.key.compareTo(b.key));

    final proto.Value data = valueBuilder()
      ..mapValue = obj
      ..freeze();

    assertRoundTrip(model, data, ValueTypeCase.mapValue);
  });

  test('testEncodeDeleteMutation', () {
    final Mutation mutation = deleteMutation('docs/1');

    final proto.Write expected = proto.Write.create()
      ..delete = 'projects/p/databases/d/documents/docs/1'
      ..freeze();
    assertRoundTripForMutation(mutation, expected);
  });

  test('testEncodeSetMutation', () {
    final Mutation mutation =
        setMutation('docs/1', map(<String>['key', 'value']));

    final proto.Write expected = proto.Write.create()
      ..update = (proto.Document.create()
        ..name = 'projects/p/databases/d/documents/docs/1'
        ..fields.add(proto.Document_FieldsEntry.create()
          ..key = 'key'
          ..value = (valueBuilder()..stringValue = 'value')))
      ..freeze();

    assertRoundTripForMutation(mutation, expected);
  });

  test('testEncodesPatchMutation', () {
    final Mutation mutation =
        patchMutation('docs/1', map(<dynamic>['key', 'value', 'key2', true]));

    final proto.Write expected = proto.Write.create()
      ..update = (proto.Document.create()
        ..name = 'projects/p/databases/d/documents/docs/1'
        ..fields.add(proto.Document_FieldsEntry.create()
          ..key = 'key'
          ..value = (valueBuilder()..stringValue = 'value'))
        ..fields.add(proto.Document_FieldsEntry.create()
          ..key = 'key2'
          ..value = (valueBuilder()..booleanValue = true)))
      ..updateMask = (proto.DocumentMask.create()
        ..fieldPaths.addAll(<String>['key', 'key2']))
      ..currentDocument = (proto.Precondition.create()..exists = true)
      ..freeze();

    assertRoundTripForMutation(mutation, expected);
  });

  test('testEncodesPatchMutationWithFieldMask', () {
    final Mutation mutation = patchMutation(
        'docs/1',
        map(<dynamic>['key', 'value', 'key2', true]),
        <FieldPath>[field('key')]);

    final proto.Write expected = proto.Write.create()
      ..update = (proto.Document.create()
        ..name = 'projects/p/databases/d/documents/docs/1'
        ..fields.add(proto.Document_FieldsEntry.create()
          ..key = 'key'
          ..value = (valueBuilder()..stringValue = 'value'))
        ..fields.add(proto.Document_FieldsEntry.create()
          ..key = 'key2'
          ..value = (valueBuilder()..booleanValue = true)))
      ..updateMask = (proto.DocumentMask.create()..fieldPaths.add('key'))
      ..freeze();

    assertRoundTripForMutation(mutation, expected);
  });

  test('testEncodesServerTimestampTransformMutation', () {
    final Mutation mutation = transformMutation(
        'docs/1',
        map(<dynamic>[
          'a',
          firestore.FieldValue.serverTimestamp(),
          'bar.baz',
          firestore.FieldValue.serverTimestamp()
        ]));

    final proto.Write expected = proto.Write.create()
      ..transform = (proto.DocumentTransform.create()
        ..document = 'projects/p/databases/d/documents/docs/1'
        ..fieldTransforms.add(proto.DocumentTransform_FieldTransform.create()
          ..fieldPath = 'a'
          ..setToServerValue =
              proto.DocumentTransform_FieldTransform_ServerValue.REQUEST_TIME)
        ..fieldTransforms.add(proto.DocumentTransform_FieldTransform.create()
          ..fieldPath = 'bar.baz'
          ..setToServerValue =
              proto.DocumentTransform_FieldTransform_ServerValue.REQUEST_TIME))
      ..currentDocument = (proto.Precondition.create()..exists = true)
      ..freeze();

    assertRoundTripForMutation(mutation, expected);
  });

  test('testEncodesArrayTransformMutations', () {
    final Mutation mutation = transformMutation(
        'docs/1',
        map(<dynamic>[
          'a',
          firestore.FieldValue.arrayUnion(<dynamic>['a', 2]),
          'bar.baz',
          firestore.FieldValue.arrayRemove(<dynamic>[
            map<dynamic>(<dynamic>['x', 1])
          ])
        ]));

    final proto.Write expected = proto.Write.create()
      ..transform = (proto.DocumentTransform.create()
        ..document = 'projects/p/databases/d/documents/docs/1'
        ..fieldTransforms.add(proto.DocumentTransform_FieldTransform.create()
          ..fieldPath = 'a'
          ..appendMissingElements = (proto.ArrayValue.create()
            ..values.add(serializer.encodeValue(wrap('a')))
            ..values.add(serializer.encodeValue(wrap(2)))))
        ..fieldTransforms.add(proto.DocumentTransform_FieldTransform.create()
          ..fieldPath = 'bar.baz'
          ..removeAllFromArray = (proto.ArrayValue.create()
            ..values.add(serializer
                .encodeValue(wrap(map<dynamic>(<dynamic>['x', 1])))))))
      ..currentDocument = (proto.Precondition.create()..exists = true)
      ..freeze();

    assertRoundTripForMutation(mutation, expected);
  });

  test('testEncodesListenRequestLabels', () {
    final Query query = TestUtil.query('collection/key');
    QueryData queryData = QueryData.init(query, 2, 3, QueryPurpose.listen);

    MapEntry<String, String> result =
        serializer.encodeListenRequestLabels(queryData);
    expect(result, isNull);

    queryData = QueryData.init(query, 2, 3, QueryPurpose.limboResolution);
    result = serializer.encodeListenRequestLabels(queryData);
    expect(result,
        const MapEntry<String, String>('goog-listen-tags', 'limbo-document'));

    queryData =
        QueryData.init(query, 2, 3, QueryPurpose.existenceFilterMismatch);
    result = serializer.encodeListenRequestLabels(queryData);
    expect(
        result,
        const MapEntry<String, String>(
            'goog-listen-tags', 'existence-filter-mismatch'));
  });

  test('testEncodesFirstLevelKeyQueries', () {
    final Query q = Query.atPath(ResourcePath.fromString('docs/1'));
    final proto.Target actual = serializer.encodeTarget(QueryData(
        q,
        1,
        2,
        QueryPurpose.limboResolution,
        SnapshotVersion.none,
        WatchStream.emptyResumeToken));

    final proto.Target_DocumentsTarget docs =
        proto.Target_DocumentsTarget.create()
          ..documents.add('projects/p/databases/d/documents/docs/1');

    final proto.Target expected = proto.Target.create()
      ..documents = docs
      ..targetId = 1
      ..resumeToken = resumeToken
      ..freeze();

    expect(actual, expected);
    expect(q,
        serializer.decodeDocumentsTarget(serializer.encodeDocumentsTarget(q)));
  });

  test('testEncodesFirstLevelAncestorQueries', () {
    final Query q = Query.atPath(ResourcePath.fromString('messages'));
    final proto.Target actual = serializer.encodeTarget(wrapQueryData(q));

    final proto.StructuredQuery structuredQueryBuilder =
        proto.StructuredQuery.create()
          ..from.add(proto.StructuredQuery_CollectionSelector.create()
            ..collectionId = 'messages')
          ..orderBy.add(defaultKeyOrder());

    final proto.Target_QueryTarget queryBuilder =
        proto.Target_QueryTarget.create()
          ..parent = 'projects/p/databases/d'
          ..structuredQuery = structuredQueryBuilder;

    final proto.Target expected = proto.Target.create()
      ..query = queryBuilder
      ..targetId = 1
      ..resumeToken = resumeToken
      ..freeze();

    expect(actual, expected);
    expect(q, serializer.decodeQueryTarget(serializer.encodeQueryTarget(q)));
  });

  test('testEncodesNestedAncestorQueries', () {
    final Query q = Query.atPath(
        ResourcePath.fromString('rooms/1/messages/10/attachments'));
    final proto.Target actual = serializer.encodeTarget(wrapQueryData(q));

    final proto.StructuredQuery structuredQueryBuilder =
        proto.StructuredQuery.create()
          ..from.add(proto.StructuredQuery_CollectionSelector.create()
            ..collectionId = 'attachments')
          ..orderBy.add(defaultKeyOrder());

    final proto.Target_QueryTarget queryBuilder =
        proto.Target_QueryTarget.create()
          ..parent = 'projects/p/databases/d/documents/rooms/1/messages/10'
          ..structuredQuery = structuredQueryBuilder
          ..freeze();

    final proto.Target expected = proto.Target.create()
      ..query = queryBuilder
      ..targetId = 1
      ..resumeToken = resumeToken
      ..freeze();

    expect(actual, expected);
    expect(q, serializer.decodeQueryTarget(serializer.encodeQueryTarget(q)));
  });

  test('testEncodesSingleFilterAtFirstLevelCollections', () {
    final Query q = Query.atPath(ResourcePath.fromString('docs'))
        .filter(filter('prop', '<', 42));
    final proto.Target actual = serializer.encodeTarget(wrapQueryData(q));

    final proto.StructuredQuery structuredQueryBuilder =
        proto.StructuredQuery.create()
          ..from.add(proto.StructuredQuery_CollectionSelector.create()
            ..collectionId = 'docs')
          ..where = (proto.StructuredQuery_Filter.create()
            ..fieldFilter = (proto.StructuredQuery_FieldFilter.create()
              ..field_1 = (proto.StructuredQuery_FieldReference.create()
                ..fieldPath = 'prop')
              ..op = proto.StructuredQuery_FieldFilter_Operator.LESS_THAN
              ..value = (valueBuilder()..integerValue = Int64(42))))
          ..orderBy.add(proto.StructuredQuery_Order.create()
            ..field_1 = (proto.StructuredQuery_FieldReference.create()
              ..fieldPath = 'prop')
            ..direction = proto.StructuredQuery_Direction.ASCENDING)
          ..orderBy.add(defaultKeyOrder());

    final proto.Target_QueryTarget queryBuilder =
        proto.Target_QueryTarget.create()
          ..parent = 'projects/p/databases/d'
          ..structuredQuery = structuredQueryBuilder;

    final proto.Target expected = proto.Target.create()
      ..query = queryBuilder
      ..targetId = 1
      ..resumeToken = resumeToken
      ..freeze();

    expect(actual, expected);
    expect(q, serializer.decodeQueryTarget(serializer.encodeQueryTarget(q)));
  });

  test('testEncodesMultipleFiltersOnDeeperCollections', () {
    final Query q =
        Query.atPath(ResourcePath.fromString('rooms/1/messages/10/attachments'))
            .filter(filter('prop', '<', 42))
            .filter(filter('author', '==', 'dimond'))
            .filter(filter('tags', 'array-contains', 'pending'));
    final proto.Target actual = serializer.encodeTarget(wrapQueryData(q));

    final proto
        .StructuredQuery structuredQueryBuilder = proto.StructuredQuery.create()
      ..from.add(proto.StructuredQuery_CollectionSelector.create()
        ..collectionId = 'attachments')
      ..where = (proto.StructuredQuery_Filter.create()
        ..compositeFilter = (proto.StructuredQuery_CompositeFilter.create()
          ..op = proto.StructuredQuery_CompositeFilter_Operator.AND
          ..filters.add(proto.StructuredQuery_Filter.create()
            ..fieldFilter = (proto.StructuredQuery_FieldFilter.create()
              ..field_1 = (proto.StructuredQuery_FieldReference.create()
                ..fieldPath = 'prop')
              ..op = proto.StructuredQuery_FieldFilter_Operator.LESS_THAN
              ..value = (valueBuilder()..integerValue = Int64(42))))
          ..filters.add(proto.StructuredQuery_Filter.create()
            ..fieldFilter = (proto.StructuredQuery_FieldFilter.create()
              ..field_1 = (proto.StructuredQuery_FieldReference.create()
                ..fieldPath = 'author')
              ..op = proto.StructuredQuery_FieldFilter_Operator.EQUAL
              ..value = (valueBuilder()..stringValue = 'dimond')))
          ..filters.add(proto.StructuredQuery_Filter.create()
            ..fieldFilter = (proto.StructuredQuery_FieldFilter.create()
              ..field_1 = (proto.StructuredQuery_FieldReference.create()
                ..fieldPath = 'tags')
              ..op = proto.StructuredQuery_FieldFilter_Operator.ARRAY_CONTAINS
              ..value = (valueBuilder()..stringValue = 'pending')))))
      ..orderBy.add(proto.StructuredQuery_Order.create()
        ..field_1 =
            (proto.StructuredQuery_FieldReference.create()..fieldPath = 'prop')
        ..direction = proto.StructuredQuery_Direction.ASCENDING)
      ..orderBy.add(defaultKeyOrder());

    final proto.Target_QueryTarget queryBuilder =
        proto.Target_QueryTarget.create()
          ..parent = 'projects/p/databases/d/documents/rooms/1/messages/10'
          ..structuredQuery = structuredQueryBuilder;

    final proto.Target expected = proto.Target.create()
      ..query = queryBuilder
      ..targetId = 1
      ..resumeToken = resumeToken
      ..freeze();

    expect(actual, expected);
    expect(q, serializer.decodeQueryTarget(serializer.encodeQueryTarget(q)));
  });

  // PORTING NOTE: Isolated array-contains filter test omitted since we seem to
  // have omitted isolated filter tests on Android
  // (and the encodeRelationFilter() / decodeRelationFilter() serializer methods
  // are private) in favor of relying on the larger tests. array-contains
  // encoding / decoding is covered by
  // [testEncodesMultipleFiltersOnDeeperCollections].

  test('testEncodesNullFilter', () {
    unaryFilterTest(null, proto.StructuredQuery_UnaryFilter_Operator.IS_NULL);
  });

  test('testEncodesNaNFilter', () {
    unaryFilterTest(
        double.nan, proto.StructuredQuery_UnaryFilter_Operator.IS_NAN);
  });

  test('testEncodesSortOrders', () {
    final Query q =
        Query.atPath(ResourcePath.fromString('docs')).orderBy(orderBy('prop'));
    final proto.Target actual = serializer.encodeTarget(wrapQueryData(q));

    final proto.StructuredQuery structuredQueryBuilder =
        proto.StructuredQuery.create()
          ..from.add(proto.StructuredQuery_CollectionSelector.create()
            ..collectionId = 'docs')
          ..orderBy.add(proto.StructuredQuery_Order.create()
            ..direction = proto.StructuredQuery_Direction.ASCENDING
            ..field_1 = (proto.StructuredQuery_FieldReference.create()
              ..fieldPath = 'prop'))
          ..orderBy.add(defaultKeyOrder());

    final proto.Target_QueryTarget queryBuilder =
        proto.Target_QueryTarget.create()
          ..parent = 'projects/p/databases/d'
          ..structuredQuery = structuredQueryBuilder;

    final proto.Target expected = proto.Target.create()
      ..query = queryBuilder
      ..targetId = 1
      ..resumeToken = resumeToken
      ..freeze();

    expect(actual, expected);
    expect(q, serializer.decodeQueryTarget(serializer.encodeQueryTarget(q)));
  });

  test('testEncodesSortOrdersDescending', () {
    final Query q =
        Query.atPath(ResourcePath.fromString('rooms/1/messages/10/attachments'))
            .orderBy(orderBy('prop', 'desc'));
    final proto.Target actual = serializer.encodeTarget(wrapQueryData(q));

    final proto.StructuredQuery structuredQueryBuilder =
        proto.StructuredQuery.create()
          ..from.add(proto.StructuredQuery_CollectionSelector.create()
            ..collectionId = 'attachments')
          ..orderBy.add(proto.StructuredQuery_Order.create()
            ..direction = proto.StructuredQuery_Direction.DESCENDING
            ..field_1 = (proto.StructuredQuery_FieldReference.create()
              ..fieldPath = 'prop'))
          ..orderBy.add(proto.StructuredQuery_Order.create()
            ..direction = proto.StructuredQuery_Direction.DESCENDING
            ..field_1 = (proto.StructuredQuery_FieldReference.create()
              ..fieldPath = DocumentKey.keyFieldName));

    final proto.Target_QueryTarget queryBuilder =
        proto.Target_QueryTarget.create()
          ..parent = 'projects/p/databases/d/documents/rooms/1/messages/10'
          ..structuredQuery = structuredQueryBuilder;

    final proto.Target expected = proto.Target.create()
      ..query = queryBuilder
      ..targetId = 1
      ..resumeToken = Int8List.fromList(<int>[])
      ..freeze();

    expect(actual, expected);
    expect(q, serializer.decodeQueryTarget(serializer.encodeQueryTarget(q)));
  });

  test('testEncodesLimits', () {
    final Query q = Query.atPath(ResourcePath.fromString('docs')).limit(26);
    final proto.Target actual = serializer.encodeTarget(wrapQueryData(q));

    final proto.StructuredQuery structuredQueryBuilder =
        proto.StructuredQuery.create()
          ..from.add(proto.StructuredQuery_CollectionSelector.create()
            ..collectionId = 'docs')
          ..orderBy.add(defaultKeyOrder())
          ..limit = (proto.Int32Value.create()..value = 26);

    final proto.Target_QueryTarget queryBuilder =
        proto.Target_QueryTarget.create()
          ..parent = 'projects/p/databases/d'
          ..structuredQuery = structuredQueryBuilder;

    final proto.Target expected = proto.Target.create()
      ..query = queryBuilder
      ..targetId = 1
      ..resumeToken = Int8List.fromList(<int>[])
      ..freeze();

    expect(actual, expected);
    expect(q, serializer.decodeQueryTarget(serializer.encodeQueryTarget(q)));
  });

  test('testEncodesBounds', () {
    final Query q = Query.atPath(ResourcePath.fromString('docs'))
        .startAt(Bound(<ReferenceValue>[
          ReferenceValue.valueOf(databaseId, key('foo/bar'))
        ], true))
        .endAt(Bound(<ReferenceValue>[
          ReferenceValue.valueOf(databaseId, key('foo/baz'))
        ], false));

    final proto.Target actual = serializer.encodeTarget(wrapQueryData(q));

    final proto.StructuredQuery structuredQueryBuilder =
        proto.StructuredQuery.create()
          ..from.add(proto.StructuredQuery_CollectionSelector.create()
            ..collectionId = 'docs')
          ..orderBy.add(defaultKeyOrder())
          ..startAt = (proto.Cursor.create()
            ..before = true
            ..values.add(valueBuilder()
              ..referenceValue = 'projects/p/databases/d/documents/foo/bar'))
          ..endAt = (proto.Cursor.create()
            ..before = false
            ..values.add(valueBuilder()
              ..referenceValue = 'projects/p/databases/d/documents/foo/baz'));

    final proto.Target_QueryTarget queryBuilder =
        proto.Target_QueryTarget.create()
          ..parent = 'projects/p/databases/d'
          ..structuredQuery = structuredQueryBuilder;

    final proto.Target expected = proto.Target.create()
      ..query = queryBuilder
      ..targetId = 1
      ..resumeToken = resumeToken
      ..freeze();

    expect(actual, expected);
    expect(q, serializer.decodeQueryTarget(serializer.encodeQueryTarget(q)));
  });

  test('testEncodesResumeTokens', () {
    final Query q = Query.atPath(ResourcePath.fromString('docs'));
    final proto.Target actual = serializer.encodeTarget(QueryData(q, 1, 2,
        QueryPurpose.listen, SnapshotVersion.none, TestUtil.resumeToken(1000)));

    final proto.StructuredQuery structuredQueryBuilder =
        proto.StructuredQuery.create()
          ..from.add(proto.StructuredQuery_CollectionSelector.create()
            ..collectionId = 'docs')
          ..orderBy.add(defaultKeyOrder());

    final proto.Target_QueryTarget queryBuilder =
        proto.Target_QueryTarget.create()
          ..parent = 'projects/p/databases/d'
          ..structuredQuery = structuredQueryBuilder;

    final proto.Target expected = proto.Target.create()
      ..query = queryBuilder
      ..targetId = 1
      ..resumeToken = TestUtil.resumeToken(1000)
      ..freeze();

    expect(actual, expected);
    expect(q, serializer.decodeQueryTarget(serializer.encodeQueryTarget(q)));
  });

  test('testConvertsTargetChangeWithAdded', () {
    final WatchChangeWatchTargetChange expected =
        WatchChangeWatchTargetChange(WatchTargetChangeType.Added, <int>[1, 4]);

    final WatchChangeWatchTargetChange actual =
        serializer.decodeWatchChange(proto.ListenResponse.create()
          ..targetChange = (proto.TargetChange.create()
            ..targetChangeType = proto.TargetChange_TargetChangeType.ADD
            ..targetIds.add(1)
            ..targetIds.add(4))
          ..freeze());

    expect(actual, expected);
  });

  test('testConvertsTargetChangeWithRemoved', () {
    final WatchChangeWatchTargetChange expected = WatchChangeWatchTargetChange(
        WatchTargetChangeType.Removed,
        <int>[1, 4],
        Uint8List.fromList(<int>[0, 1, 2]),
        GrpcError.permissionDenied());

    final WatchChangeWatchTargetChange actual =
        serializer.decodeWatchChange(proto.ListenResponse.create()
          ..targetChange = (proto.TargetChange.create()
            ..targetChangeType = proto.TargetChange_TargetChangeType.REMOVE
            ..targetIds.add(1)
            ..targetIds.add(4)
            ..cause = (proto.Status.create()..code = 7)
            ..resumeToken = Uint8List.fromList(<int>[0, 1, 2]))
          ..freeze());

    expect(actual, expected);
  });

  test('testConvertsTargetChangeWithNoChange', () {
    final WatchChangeWatchTargetChange expected = WatchChangeWatchTargetChange(
        WatchTargetChangeType.NoChange, <int>[1, 4]);

    final WatchChangeWatchTargetChange actual =
        serializer.decodeWatchChange(proto.ListenResponse()
          ..targetChange = (proto.TargetChange()
            ..targetChangeType = proto.TargetChange_TargetChangeType.NO_CHANGE
            ..targetIds.add(1)
            ..targetIds.add(4))
          ..freeze());

    expect(actual, expected);
  });

  test('testConvertsDocumentChangeWithTargetIds', () {
    final WatchChangeDocumentChange expected = WatchChangeDocumentChange(
        <int>[1, 2],
        <int>[],
        key('coll/1'),
        doc('coll/1', 5, map(<String>['foo', 'bar'])));

    final WatchChangeDocumentChange actual =
        serializer.decodeWatchChange(proto.ListenResponse()
          ..documentChange = (proto.DocumentChange.create()
            ..document = (proto.Document.create()
              ..name = serializer.encodeKey(key('coll/1'))
              ..updateTime = serializer.encodeTimestamp(Timestamp(0, 5000))
              ..fields.add(proto.Document_FieldsEntry()
                ..key = 'foo'
                ..value = (proto.Value()..stringValue = 'bar')))
            ..targetIds.add(1)
            ..targetIds.add(2))
          ..freeze());

    expect(actual, expected);
  });

  test('testConvertsDocumentChangeWithRemovedTargetIds', () {
    final WatchChangeDocumentChange expected = WatchChangeDocumentChange(
        <int>[2],
        <int>[1],
        key('coll/1'),
        doc('coll/1', 5, map(<String>['foo', 'bar'])));

    final WatchChangeDocumentChange actual =
        serializer.decodeWatchChange(proto.ListenResponse()
          ..documentChange = (proto.DocumentChange()
            ..document = (proto.Document()
              ..name = serializer.encodeKey(key('coll/1'))
              ..updateTime = serializer.encodeTimestamp(Timestamp(0, 5000))
              ..fields.add(proto.Document_FieldsEntry()
                ..key = 'foo'
                ..value = (proto.Value()..stringValue = 'bar')))
            ..targetIds.add(2)
            ..removedTargetIds.add(1))
          ..freeze());

    expect(actual, expected);
  });

  test('testConvertsDocumentChangeWithDeletions', () {
    final WatchChangeDocumentChange expected = WatchChangeDocumentChange(
        <int>[], <int>[1, 2], key('coll/1'), deletedDoc('coll/1', 5));

    final WatchChangeDocumentChange actual =
        serializer.decodeWatchChange(proto.ListenResponse()
          ..documentDelete = (proto.DocumentDelete()
            ..document = serializer.encodeKey(key('coll/1'))
            ..readTime = serializer.encodeTimestamp(Timestamp(0, 5000))
            ..removedTargetIds.add(1)
            ..removedTargetIds.add(2))
          ..freeze());

    expect(actual, expected);
  });

  test('testConvertsDocumentChangeWithRemoves', () {
    final WatchChangeDocumentChange expected =
        WatchChangeDocumentChange(<int>[], <int>[1, 2], key('coll/1'), null);

    final WatchChangeDocumentChange actual =
        serializer.decodeWatchChange(proto.ListenResponse()
          ..documentRemove = (proto.DocumentRemove()
            ..document = serializer.encodeKey(key('coll/1'))
            ..removedTargetIds.add(1)
            ..removedTargetIds.add(2))
          ..freeze());

    expect(actual, expected);
  });
}

enum ValueTypeCase {
  nullValue,
  booleanValue,
  integerValue,
  doubleValue,
  timestampValue,
  stringValue,
  bytesValue,
  referenceValue,
  geoPointValue,
  arrayValue,
  mapValue,
}

// ignore: always_specify_types
const wrap = TestUtil.wrap;
// ignore: always_specify_types
const ref = TestUtil.ref;
// ignore: always_specify_types
const map = TestUtil.map;
// ignore: always_specify_types
const deleteMutation = TestUtil.deleteMutation;
// ignore: always_specify_types
const setMutation = TestUtil.setMutation;
// ignore: always_specify_types
const patchMutation = TestUtil.patchMutation;
// ignore: always_specify_types
const field = TestUtil.field;
// ignore: always_specify_types
const transformMutation = TestUtil.transformMutation;
// ignore: always_specify_types
const query = TestUtil.query;
// ignore: always_specify_types
const filter = TestUtil.filter;
// ignore: always_specify_types
const key = TestUtil.key;
// ignore: always_specify_types
const orderBy = TestUtil.orderBy;
// ignore: always_specify_types
const doc = TestUtil.doc;
// ignore: always_specify_types
const deletedDoc = TestUtil.deletedDoc;
