// File created by
// Lung Razvan <long1eu>
// on 03/10/2018

import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/core/bound.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/filter/filter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/target.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/document_reference.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/field_value.dart'
    as firestore;
import 'package:cloud_firestore_dart/src/firebase/firestore/geo_point.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_purpose.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/field_mask.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/field_transform.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/numeric_extremum_transform_operation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/numeric_increment_transform_operation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/patch_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/server_timestamp_operation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/set_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/verify_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/watch_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/user_data_converter.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as proto_;
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;
import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';

void main() {
  final Uint8List _resumeToken = Uint8List.fromList(<int>[]);

  late DatabaseId databaseId;
  late RemoteSerializer serializer;

  setUp(() {
    databaseId = DatabaseId.forDatabase('p', 'd');
    serializer = RemoteSerializer(databaseId);
  });

  proto_.Value valueBuilder() => proto_.Value.create();

  void assertRoundTrip(
      FieldValue value, proto_.Value data, ValueTypeCase typeCase) {
    final proto_.Value actual = serializer.encodeValue(value);

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
    return QueryData(query.toTarget(), 1, 2, QueryPurpose.listen,
        SnapshotVersion.none, Uint8List(0));
  }

  void unaryFilterTest(Object? equalityValue,
      proto.StructuredQuery_UnaryFilter_Operator unaryOperator,
      [String operator = '==']) {
    final Query q = Query(ResourcePath.fromString('docs'))
        .filter(filter('prop', operator, equalityValue));
    final proto_.Target actual = serializer.encodeTarget(wrapQueryData(q));

    final proto.StructuredQuery structuredQueryBuilder =
        proto.StructuredQuery.create()
          ..from.add(proto.StructuredQuery_CollectionSelector.create()
            ..collectionId = 'docs')
          ..where = (proto.StructuredQuery_Filter.create()
            ..unaryFilter = (proto.StructuredQuery_UnaryFilter.create()
              ..field_2 = (proto.StructuredQuery_FieldReference.create()
                ..fieldPath = 'prop')
              ..op = unaryOperator));
    // Inequality filters add an implicit order by on the filtered field.
    if (operator == '!=') {
      structuredQueryBuilder.orderBy.add(proto.StructuredQuery_Order.create()
        ..direction = proto.StructuredQuery_Direction.ASCENDING
        ..field_1 = (proto.StructuredQuery_FieldReference.create()
          ..fieldPath = 'prop'));
    }
    structuredQueryBuilder.orderBy.add(defaultKeyOrder());

    final proto_.Target_QueryTarget queryBuilder =
        proto.Target_QueryTarget.create()
          ..parent = 'projects/p/databases/d/documents'
          ..structuredQuery = structuredQueryBuilder;

    final proto_.Target expected = proto_.Target.create()
      ..query = queryBuilder
      ..targetId = 1
      ..freeze();

    expect(actual, expected);
    expect(
        q.toTarget(),
        serializer
            .decodeQueryTarget(serializer.encodeQueryTarget(q.toTarget())));
  }

  test('testEncodesNull', () {
    final FieldValue value = NullValue.nullValue();
    final proto_.Value data = valueBuilder()
      ..nullValue = proto.NullValue.NULL_VALUE
      ..freeze();
    assertRoundTrip(value, data, ValueTypeCase.nullValue);
  });

  test('testEncodesBoolean', () {
    final List<bool> tests = <bool>[true, false];
    for (bool test in tests) {
      final FieldValue value = wrap(test);
      final proto_.Value data = valueBuilder()
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
      final FieldValue value = wrap(test);
      final proto_.Value data = valueBuilder()
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
      final proto_.Value data = valueBuilder()
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
      final proto_.Value data = valueBuilder()
        ..stringValue = test
        ..freeze();
      assertRoundTrip(value, data, ValueTypeCase.stringValue);
    }
  });

  test('testEncodesDates', () {
    final DateTime date1 = DateTime.utc(2016, 1, 2, 10, 20, 50, 500);
    final DateTime date2 = DateTime.utc(2016, 6, 17, 10, 50, 15);

    final List<DateTime> tests = <DateTime>[date1, date2];

    final proto.Timestamp ts1 = proto.Timestamp()
      ..nanos = 500000000
      ..seconds = Int64(1451730050);

    final proto.Timestamp ts2 = proto.Timestamp()
      ..nanos = 0
      ..seconds = Int64(1466160615);

    final List<proto_.Value> expected = <proto_.Value>[
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
    final proto_.Value data = valueBuilder()
      ..geoPointValue = (proto.LatLng.create()
        ..latitude = 1.23
        ..longitude = 4.56)
      ..freeze();

    assertRoundTrip(geoPoint, data, ValueTypeCase.geoPointValue);
  });

  test('testEncodesBlobs', () {
    final FieldValue _blob = wrap(blob(<int>[0, 1, 2, 3]));
    final proto_.Value data = valueBuilder()
      ..bytesValue = <int>[0, 1, 2, 3]
      ..freeze();

    assertRoundTrip(_blob, data, ValueTypeCase.bytesValue);
  });

  test('testEncodesReferences', () {
    final DocumentReference value = ref('foo/bar');
    final FieldValue reference = wrap(value);
    final proto_.Value data = valueBuilder()
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

    final proto_.Value data = valueBuilder()
      ..arrayValue = builder
      ..freeze();

    assertRoundTrip(model, data, ValueTypeCase.arrayValue);
  });

  test('testEncodesNestedObjects', () {
    final FieldValue model = wrapMap(map<dynamic>(<dynamic>[
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
      ..fields['b'] = (valueBuilder()..booleanValue = false);

    final proto.ArrayValue array = proto.ArrayValue.create()
      ..values.add(valueBuilder()..integerValue = Int64(2))
      ..values.add(valueBuilder()..stringValue = 'bar')
      ..values.add(valueBuilder()..mapValue = inner);

    inner = proto.MapValue.create()
      ..fields['e'] = (valueBuilder()..integerValue = Int64(IntegerValue.min));

    final proto.MapValue middle = proto.MapValue.create()
      ..fields['d'] = (valueBuilder()..integerValue = Int64(100))
      ..fields['nested'] = (valueBuilder()..mapValue = inner);

    final proto.MapValue obj = proto.MapValue.create()
      ..fields['b'] = (valueBuilder()..booleanValue = true)
      ..fields['d'] = (valueBuilder()..doubleValue = double.maxFinite)
      ..fields['i'] = (valueBuilder()..integerValue = Int64(1))
      ..fields['n'] = (valueBuilder()..nullValue = proto.NullValue.NULL_VALUE)
      ..fields['s'] = (valueBuilder()..stringValue = 'foo')
      ..fields['a'] = (valueBuilder()..arrayValue = array)
      ..fields['o'] = (valueBuilder()..mapValue = middle);

    final Map<String, proto_.Value> sortedKey =
        (obj.fields.keys.toList()..sort()).asMap().map((_, String key) =>
            MapEntry<String, proto_.Value>(key, obj.fields[key]!));

    obj.fields
      ..clear()
      ..addAll(sortedKey);

    final proto_.Value data = valueBuilder()
      ..mapValue = obj
      ..freeze();

    assertRoundTrip(model, data, ValueTypeCase.mapValue);
  });

  test('testEncodesVectorValue', () {
    final FieldValue model =
        wrap(firestore.FieldValue.vector(<double>[1, 2, 3]));

    final proto.ArrayValue array = proto.ArrayValue.create()
      ..values.add(valueBuilder()..doubleValue = 1)
      ..values.add(valueBuilder()..doubleValue = 2)
      ..values.add(valueBuilder()..doubleValue = 3);

    final proto.MapValue obj = proto.MapValue.create()
      ..fields['__type__'] = (valueBuilder()..stringValue = '__vector__')
      ..fields['value'] = (valueBuilder()..arrayValue = array);

    final proto_.Value data = valueBuilder()
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

  test('testEncodeVerifyMutation', () {
    final Mutation mutation =
        VerifyMutation(key('docs/1'), Precondition(updateTime: version(4)));

    final proto.Write expected = proto.Write.create()
      ..verify = 'projects/p/databases/d/documents/docs/1'
      ..currentDocument = (proto.Precondition.create()
        ..updateTime = serializer.encodeVersion(version(4)))
      ..freeze();
    assertRoundTripForMutation(mutation, expected);

    final proto.Write missing = serializer.encodeMutation(
        VerifyMutation(key('docs/1'), Precondition(exists: false)));
    expect(missing.verify, 'projects/p/databases/d/documents/docs/1');
    expect(missing.currentDocument.hasExists(), isTrue);
    expect(missing.currentDocument.exists, isFalse);
  });

  test('testEncodeSetMutation', () {
    final Mutation mutation =
        setMutation('docs/1', map(<String>['key', 'value']));

    final proto.Write expected = proto.Write.create()
      ..update = (proto.Document.create()
        ..name = 'projects/p/databases/d/documents/docs/1'
        ..fields['key'] = (valueBuilder()..stringValue = 'value'))
      ..freeze();

    assertRoundTripForMutation(mutation, expected);
  });

  test('testEncodesPatchMutation', () {
    final Mutation mutation =
        patchMutation('docs/1', map(<dynamic>['key', 'value', 'key2', true]));

    final proto.Write expected = proto.Write.create()
      ..update = (proto.Document.create()
        ..name = 'projects/p/databases/d/documents/docs/1'
        ..fields['key'] = (valueBuilder()..stringValue = 'value')
        ..fields['key2'] = (valueBuilder()..booleanValue = true))
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
        ..fields['key'] = (valueBuilder()..stringValue = 'value')
        ..fields['key2'] = (valueBuilder()..booleanValue = true))
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
      ..update = (proto.Document.create()
        ..name = 'projects/p/databases/d/documents/docs/1')
      ..updateMask = proto.DocumentMask.create()
      ..updateTransforms.add(proto.DocumentTransform_FieldTransform.create()
        ..fieldPath = 'a'
        ..setToServerValue =
            proto.DocumentTransform_FieldTransform_ServerValue.REQUEST_TIME)
      ..updateTransforms.add(proto.DocumentTransform_FieldTransform.create()
        ..fieldPath = 'bar.baz'
        ..setToServerValue =
            proto.DocumentTransform_FieldTransform_ServerValue.REQUEST_TIME)
      ..currentDocument = (proto.Precondition.create()..exists = true)
      ..freeze();

    assertRoundTripForMutation(mutation, expected);
  });

  test('testEncodesArrayTransformMutations', () {
    final Mutation mutation = transformMutation(
        'docs/1',
        map(<dynamic>[
          'a',
          firestore.FieldValue.arrayUnion(<Object>['a', 2]),
          'bar.baz',
          firestore.FieldValue.arrayRemove(<Object>[
            map<Object>(<Object>['x', 1])
          ])
        ]));

    final proto.Write expected = proto.Write.create()
      ..update = (proto.Document.create()
        ..name = 'projects/p/databases/d/documents/docs/1')
      ..updateMask = proto.DocumentMask.create()
      ..updateTransforms.add(proto.DocumentTransform_FieldTransform.create()
        ..fieldPath = 'a'
        ..appendMissingElements = (proto.ArrayValue.create()
          ..values.add(serializer.encodeValue(wrap('a')))
          ..values.add(serializer.encodeValue(wrap(2)))))
      ..updateTransforms.add(proto.DocumentTransform_FieldTransform.create()
        ..fieldPath = 'bar.baz'
        ..removeAllFromArray = (proto.ArrayValue.create()
          ..values.add(
              serializer.encodeValue(wrap(map<Object>(<Object>['x', 1]))))))
      ..currentDocument = (proto.Precondition.create()..exists = true)
      ..freeze();

    assertRoundTripForMutation(mutation, expected);
  });

  /// The Android TestUtil `setMutation`: parses [values] like a `set()` call,
  /// so field value sentinels become field transforms.
  Mutation setMutationWithTransforms(String path, Map<String, Object?> values) {
    return UserDataConverter(DatabaseId.forProject('project'))
        .parseSetData(values)
        .toMutation(key(path), Precondition.none);
  }

  test('testEncodesServerTimestampMutation', () {
    Mutation mutation = setMutationWithTransforms('docs/1', <String, Object?>{
      'a': firestore.FieldValue.serverTimestamp(),
      'bar': firestore.FieldValue.serverTimestamp(),
    });
    proto.Write expected = proto.Write.create()
      ..update = (proto.Document.create()
        ..name = 'projects/p/databases/d/documents/docs/1')
      ..updateTransforms.add(proto.DocumentTransform_FieldTransform.create()
        ..fieldPath = 'a'
        ..setToServerValue =
            proto.DocumentTransform_FieldTransform_ServerValue.REQUEST_TIME)
      ..updateTransforms.add(proto.DocumentTransform_FieldTransform.create()
        ..fieldPath = 'bar'
        ..setToServerValue =
            proto.DocumentTransform_FieldTransform_ServerValue.REQUEST_TIME)
      ..freeze();
    assertRoundTripForMutation(mutation, expected);

    mutation = transformMutation('docs/1', <String, Object>{
      'a': firestore.FieldValue.serverTimestamp(),
      'bar.baz': firestore.FieldValue.serverTimestamp(),
    });
    expected = proto.Write.create()
      ..update = (proto.Document.create()
        ..name = 'projects/p/databases/d/documents/docs/1')
      ..updateMask = proto.DocumentMask.create()
      ..updateTransforms.add(proto.DocumentTransform_FieldTransform.create()
        ..fieldPath = 'a'
        ..setToServerValue =
            proto.DocumentTransform_FieldTransform_ServerValue.REQUEST_TIME)
      ..updateTransforms.add(proto.DocumentTransform_FieldTransform.create()
        ..fieldPath = 'bar.baz'
        ..setToServerValue =
            proto.DocumentTransform_FieldTransform_ServerValue.REQUEST_TIME)
      ..currentDocument = (proto.Precondition.create()..exists = true)
      ..freeze();
    assertRoundTripForMutation(mutation, expected);
  });

  test('testEncodesArrayMutations', () {
    Mutation mutation = setMutationWithTransforms('docs/1', <String, Object?>{
      'a': firestore.FieldValue.arrayUnion(<Object>['a', 2]),
      'bar': firestore.FieldValue.arrayRemove(<Object>[
        <String, Object>{'x': 1}
      ]),
    });
    proto.Write expected = proto.Write.create()
      ..update = (proto.Document.create()
        ..name = 'projects/p/databases/d/documents/docs/1')
      ..updateTransforms.add(proto.DocumentTransform_FieldTransform.create()
        ..fieldPath = 'a'
        ..appendMissingElements = (proto.ArrayValue.create()
          ..values.add(serializer.encodeValue(wrap('a')))
          ..values.add(serializer.encodeValue(wrap(2)))))
      ..updateTransforms.add(proto.DocumentTransform_FieldTransform.create()
        ..fieldPath = 'bar'
        ..removeAllFromArray = (proto.ArrayValue.create()
          ..values
              .add(serializer.encodeValue(wrap(<String, Object>{'x': 1})))))
      ..freeze();
    assertRoundTripForMutation(mutation, expected);

    mutation = transformMutation('docs/1', <String, Object>{
      'a': firestore.FieldValue.arrayUnion(<Object>['a', 2]),
      'bar.baz': firestore.FieldValue.arrayRemove(<Object>[
        <String, Object>{'x': 1}
      ]),
    });
    expected = proto.Write.create()
      ..update = (proto.Document.create()
        ..name = 'projects/p/databases/d/documents/docs/1')
      ..updateMask = proto.DocumentMask.create()
      ..updateTransforms.add(proto.DocumentTransform_FieldTransform.create()
        ..fieldPath = 'a'
        ..appendMissingElements = (proto.ArrayValue.create()
          ..values.add(serializer.encodeValue(wrap('a')))
          ..values.add(serializer.encodeValue(wrap(2)))))
      ..updateTransforms.add(proto.DocumentTransform_FieldTransform.create()
        ..fieldPath = 'bar.baz'
        ..removeAllFromArray = (proto.ArrayValue.create()
          ..values
              .add(serializer.encodeValue(wrap(<String, Object>{'x': 1})))))
      ..currentDocument = (proto.Precondition.create()..exists = true)
      ..freeze();
    assertRoundTripForMutation(mutation, expected);
  });

  test('testEncodesSetMutationWithTransforms', () {
    final List<FieldTransform> transforms = <FieldTransform>[
      FieldTransform(field('a'), ServerTimestampOperation()),
      FieldTransform(field('b'),
          NumericIncrementTransformOperation(wrap(2) as NumberValue)),
    ];
    final Mutation mutation = SetMutation(key('docs/1'),
        wrapMap(<String, Object?>{'k': 'v'}), Precondition.none, transforms);

    final proto.Write expected = proto.Write.create()
      ..update = (proto.Document.create()
        ..name = 'projects/p/databases/d/documents/docs/1'
        ..fields['k'] = (valueBuilder()..stringValue = 'v'))
      ..updateTransforms.add(proto.DocumentTransform_FieldTransform.create()
        ..fieldPath = 'a'
        ..setToServerValue =
            proto.DocumentTransform_FieldTransform_ServerValue.REQUEST_TIME)
      ..updateTransforms.add(proto.DocumentTransform_FieldTransform.create()
        ..fieldPath = 'b'
        ..increment = (valueBuilder()..integerValue = Int64(2)))
      ..freeze();

    assertRoundTripForMutation(mutation, expected);
    expect(serializer.decodeMutation(expected).fieldTransforms, transforms);
  });

  test('testEncodesSetMutationWithMinimumAndMaximumTransforms', () {
    final List<FieldTransform> transforms = <FieldTransform>[
      FieldTransform(
          field('a'), NumericMinimumTransformOperation(wrap(2) as NumberValue)),
      FieldTransform(field('b'),
          NumericMaximumTransformOperation(wrap(2.5) as NumberValue)),
    ];
    final Mutation mutation = SetMutation(key('docs/1'),
        wrapMap(<String, Object?>{'k': 'v'}), Precondition.none, transforms);

    final proto.Write expected = proto.Write.create()
      ..update = (proto.Document.create()
        ..name = 'projects/p/databases/d/documents/docs/1'
        ..fields['k'] = (valueBuilder()..stringValue = 'v'))
      ..updateTransforms.add(proto.DocumentTransform_FieldTransform.create()
        ..fieldPath = 'a'
        ..minimum = (valueBuilder()..integerValue = Int64(2)))
      ..updateTransforms.add(proto.DocumentTransform_FieldTransform.create()
        ..fieldPath = 'b'
        ..maximum = (valueBuilder()..doubleValue = 2.5))
      ..freeze();

    assertRoundTripForMutation(mutation, expected);
    expect(serializer.decodeMutation(expected).fieldTransforms, transforms);
  });

  test('testEncodesPatchMutationWithTransforms', () {
    final List<FieldTransform> transforms = <FieldTransform>[
      FieldTransform(field('a.b'), ServerTimestampOperation()),
    ];
    final Mutation mutation = PatchMutation(
        key('docs/1'),
        wrapMap(<String, Object?>{'k': 'v'}),
        FieldMask(<FieldPath>{field('k')}),
        Precondition(exists: true),
        transforms);

    final proto.Write expected = proto.Write.create()
      ..update = (proto.Document.create()
        ..name = 'projects/p/databases/d/documents/docs/1'
        ..fields['k'] = (valueBuilder()..stringValue = 'v'))
      ..updateMask = (proto.DocumentMask.create()..fieldPaths.add('k'))
      ..updateTransforms.add(proto.DocumentTransform_FieldTransform.create()
        ..fieldPath = 'a.b'
        ..setToServerValue =
            proto.DocumentTransform_FieldTransform_ServerValue.REQUEST_TIME)
      ..currentDocument = (proto.Precondition.create()..exists = true)
      ..freeze();

    assertRoundTripForMutation(mutation, expected);
  });

  test('testDecodesMutationResultWithTransformResults', () {
    final proto.WriteResult result = proto.WriteResult.create()
      ..updateTime = serializer.encodeVersion(version(7))
      ..transformResults.add(serializer.encodeValue(wrap(3)));
    final MutationResult decoded =
        serializer.decodeMutationResult(result, version(9));
    expect(decoded.version, version(7));
    expect(decoded.transformResults, <FieldValue>[wrap(3)]);

    final MutationResult plain = serializer.decodeMutationResult(
        proto.WriteResult.create()
          ..updateTime = serializer.encodeVersion(version(7)),
        version(9));
    expect(plain.transformResults, isEmpty);
  });

  test('testEncodesListenRequestLabels', () {
    final Query _query = query('collection/key');
    QueryData queryData =
        QueryData(_query.toTarget(), 2, 3, QueryPurpose.listen);

    final Map<String, String> encoded =
        serializer.encodeListenRequestLabels(queryData);
    expect(encoded, isEmpty);

    queryData =
        QueryData(_query.toTarget(), 2, 3, QueryPurpose.limboResolution);
    MapEntry<String, String> result =
        serializer.encodeListenRequestLabels(queryData).entries.first;
    expect(result.key, 'goog-listen-tags');
    expect(result.value, 'limbo-document');

    queryData = QueryData(
        _query.toTarget(), 2, 3, QueryPurpose.existenceFilterMismatch);
    result = serializer.encodeListenRequestLabels(queryData).entries.first;
    expect(result.key, 'goog-listen-tags');
    expect(result.value, 'existence-filter-mismatch');

    queryData = QueryData(
        _query.toTarget(), 2, 3, QueryPurpose.existenceFilterMismatchBloom);
    result = serializer.encodeListenRequestLabels(queryData).entries.first;
    expect(result.key, 'goog-listen-tags');
    expect(result.value, 'existence-filter-mismatch-bloom');
  });

  test('testDecodesExistenceFilterWithAndWithoutUnchangedNames', () {
    final proto.BloomFilter bloomFilter = proto.BloomFilter(
        bits: proto.BitSequence(bitmap: <int>[1, 2], padding: 3), hashCount: 5);

    proto.ListenResponse response = proto.ListenResponse(
        filter: proto.ExistenceFilter(
            targetId: 7, count: 4, unchangedNames: bloomFilter));
    WatchChangeExistenceFilterWatchChange change = serializer
        .decodeWatchChange(response) as WatchChangeExistenceFilterWatchChange;
    expect(change.targetId, 7);
    expect(change.existenceFilter.count, 4);
    expect(change.existenceFilter.unchangedNames, bloomFilter);

    response = proto.ListenResponse(
        filter: proto.ExistenceFilter(targetId: 7, count: 4));
    change = serializer.decodeWatchChange(response)
        as WatchChangeExistenceFilterWatchChange;
    expect(change.existenceFilter.unchangedNames, isNull);
  });

  test('testEncodesFirstLevelKeyQueries', () {
    final Query q = Query(ResourcePath.fromString('docs/1'));
    final proto_.Target actual = serializer.encodeTarget(QueryData(
        q.toTarget(),
        1,
        2,
        QueryPurpose.limboResolution,
        SnapshotVersion.none,
        Uint8List(0)));

    final proto_.Target_DocumentsTarget docs =
        proto.Target_DocumentsTarget.create()
          ..documents.add('projects/p/databases/d/documents/docs/1');

    final proto_.Target expected = proto_.Target.create()
      ..documents = docs
      ..targetId = 1
      ..resumeToken = _resumeToken
      ..freeze();

    expect(actual, expected);
    expect(
        q.toTarget(),
        serializer.decodeDocumentsTarget(
            serializer.encodeDocumentsTarget(q.toTarget())));
  });

  test('testEncodesFirstLevelAncestorQueries', () {
    final Query q = Query(ResourcePath.fromString('messages'));
    final proto_.Target actual = serializer.encodeTarget(wrapQueryData(q));

    final proto.StructuredQuery structuredQueryBuilder =
        proto.StructuredQuery.create()
          ..from.add(proto.StructuredQuery_CollectionSelector.create()
            ..collectionId = 'messages')
          ..orderBy.add(defaultKeyOrder());

    final proto_.Target_QueryTarget queryBuilder =
        proto.Target_QueryTarget.create()
          ..parent = 'projects/p/databases/d/documents'
          ..structuredQuery = structuredQueryBuilder;

    final proto_.Target expected = proto_.Target.create()
      ..query = queryBuilder
      ..targetId = 1
      ..resumeToken = _resumeToken
      ..freeze();

    expect(actual, expected);
    expect(
        q.toTarget(),
        serializer
            .decodeQueryTarget(serializer.encodeQueryTarget(q.toTarget())));
  });

  test('testEncodesNestedAncestorQueries', () {
    final Query q =
        Query(ResourcePath.fromString('rooms/1/messages/10/attachments'));
    final proto_.Target actual = serializer.encodeTarget(wrapQueryData(q));

    final proto.StructuredQuery structuredQueryBuilder =
        proto.StructuredQuery.create()
          ..from.add(proto.StructuredQuery_CollectionSelector.create()
            ..collectionId = 'attachments')
          ..orderBy.add(defaultKeyOrder());

    final proto_.Target_QueryTarget queryBuilder =
        proto.Target_QueryTarget.create()
          ..parent = 'projects/p/databases/d/documents/rooms/1/messages/10'
          ..structuredQuery = structuredQueryBuilder
          ..freeze();

    final proto_.Target expected = proto_.Target.create()
      ..query = queryBuilder
      ..targetId = 1
      ..resumeToken = _resumeToken
      ..freeze();

    expect(actual, expected);
    expect(
        q.toTarget(),
        serializer
            .decodeQueryTarget(serializer.encodeQueryTarget(q.toTarget())));
  });

  test('testEncodesSingleFilterAtFirstLevelCollections', () {
    final Query q =
        Query(ResourcePath.fromString('docs')).filter(filter('prop', '<', 42));
    final proto_.Target actual = serializer.encodeTarget(wrapQueryData(q));

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

    final proto_.Target_QueryTarget queryBuilder =
        proto.Target_QueryTarget.create()
          ..parent = 'projects/p/databases/d/documents'
          ..structuredQuery = structuredQueryBuilder;

    final proto_.Target expected = proto_.Target.create()
      ..query = queryBuilder
      ..targetId = 1
      ..resumeToken = _resumeToken
      ..freeze();

    expect(actual, expected);
    expect(
        q.toTarget(),
        serializer
            .decodeQueryTarget(serializer.encodeQueryTarget(q.toTarget())));
  });

  test('testEncodesMultipleFiltersOnDeeperCollections', () {
    final Query q =
        Query(ResourcePath.fromString('rooms/1/messages/10/attachments'))
            .filter(filter('prop', '<', 42))
            .filter(filter('author', '==', 'dimond'))
            .filter(filter('tags', 'array-contains', 'pending'));
    final proto_.Target actual = serializer.encodeTarget(wrapQueryData(q));

    final proto.StructuredQuery structuredQueryBuilder =
        proto.StructuredQuery.create()
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
                  ..op =
                      proto.StructuredQuery_FieldFilter_Operator.ARRAY_CONTAINS
                  ..value = (valueBuilder()..stringValue = 'pending')))))
          ..orderBy.add(proto.StructuredQuery_Order.create()
            ..field_1 = (proto.StructuredQuery_FieldReference.create()
              ..fieldPath = 'prop')
            ..direction = proto.StructuredQuery_Direction.ASCENDING)
          ..orderBy.add(defaultKeyOrder());

    final proto_.Target_QueryTarget queryBuilder =
        proto.Target_QueryTarget.create()
          ..parent = 'projects/p/databases/d/documents/rooms/1/messages/10'
          ..structuredQuery = structuredQueryBuilder;

    final proto_.Target expected = proto_.Target.create()
      ..query = queryBuilder
      ..targetId = 1
      ..resumeToken = _resumeToken
      ..freeze();

    expect(actual, expected);
    expect(
        q.toTarget(),
        serializer
            .decodeQueryTarget(serializer.encodeQueryTarget(q.toTarget())));
  });

  test('testEncodesCompositeFiltersOnDeeperCollections', () {
    // (prop < 42) || (author == "ehsann" && tags array-contains "pending")
    final Query q =
        Query(ResourcePath.fromString('rooms/1/messages/10/attachments'))
            .filter(orFilters(<Filter>[
      filter('prop', '<', 42),
      andFilters(<Filter>[
        filter('author', '==', 'ehsann'),
        filter('tags', 'array-contains', 'pending'),
      ]),
    ]));
    final proto_.Target actual = serializer.encodeTarget(wrapQueryData(q));

    proto.StructuredQuery_Filter fieldFilter(String path,
            proto.StructuredQuery_FieldFilter_Operator op, proto_.Value value) =>
        proto.StructuredQuery_Filter.create()
          ..fieldFilter = (proto.StructuredQuery_FieldFilter.create()
            ..field_1 =
                (proto.StructuredQuery_FieldReference.create()..fieldPath = path)
            ..op = op
            ..value = value);

    final proto.StructuredQuery structuredQueryBuilder =
        proto.StructuredQuery.create()
          ..from.add(proto.StructuredQuery_CollectionSelector.create()
            ..collectionId = 'attachments')
          ..where = (proto.StructuredQuery_Filter.create()
            ..compositeFilter = (proto.StructuredQuery_CompositeFilter.create()
              ..op = proto.StructuredQuery_CompositeFilter_Operator.OR
              ..filters.add(fieldFilter(
                  'prop',
                  proto.StructuredQuery_FieldFilter_Operator.LESS_THAN,
                  valueBuilder()..integerValue = Int64(42)))
              ..filters.add(proto.StructuredQuery_Filter.create()
                ..compositeFilter = (proto.StructuredQuery_CompositeFilter
                    .create()
                  ..op = proto.StructuredQuery_CompositeFilter_Operator.AND
                  ..filters.add(fieldFilter(
                      'author',
                      proto.StructuredQuery_FieldFilter_Operator.EQUAL,
                      valueBuilder()..stringValue = 'ehsann'))
                  ..filters.add(fieldFilter(
                      'tags',
                      proto.StructuredQuery_FieldFilter_Operator.ARRAY_CONTAINS,
                      valueBuilder()..stringValue = 'pending'))))))
          ..orderBy.add(proto.StructuredQuery_Order.create()
            ..field_1 =
                (proto.StructuredQuery_FieldReference.create()..fieldPath = 'prop')
            ..direction = proto.StructuredQuery_Direction.ASCENDING)
          ..orderBy.add(defaultKeyOrder());

    final proto_.Target_QueryTarget queryBuilder =
        proto.Target_QueryTarget.create()
          ..parent = 'projects/p/databases/d/documents/rooms/1/messages/10'
          ..structuredQuery = structuredQueryBuilder;

    final proto_.Target expected = proto_.Target.create()
      ..query = queryBuilder
      ..targetId = 1
      ..freeze();

    expect(actual, expected);
    final Target roundTripped =
        serializer.decodeQueryTarget(serializer.encodeQueryTarget(q.toTarget()));
    expect(roundTripped, q.toTarget());
  });

  test('testNotEqualSerialization', () {
    final FieldFilter inputFilter = filter('field', '!=', 42);
    final proto.StructuredQuery_Filter apiFilter =
        serializer.encodeUnaryOrFieldFilter(inputFilter);

    final proto.StructuredQuery_Filter expectedFilter =
        proto.StructuredQuery_Filter()
          ..fieldFilter = (proto.StructuredQuery_FieldFilter()
            ..field_1 =
                (proto.StructuredQuery_FieldReference()..fieldPath = 'field')
            ..op = proto.StructuredQuery_FieldFilter_Operator.NOT_EQUAL
            ..value = (valueBuilder()..integerValue = Int64(42)));

    expect(expectedFilter, apiFilter);
    final FieldFilter roundTripped =
        serializer.decodeFieldFilter(apiFilter.fieldFilter);
    expect(inputFilter, roundTripped);
  });

  test('testNotInSerialization', () {
    final FieldFilter inputFilter =
        filter('field', 'not-in', <int>[42]);
    final proto.StructuredQuery_Filter apiFilter =
        serializer.encodeUnaryOrFieldFilter(inputFilter);

    final proto.ArrayValue notInFilterValue = proto.ArrayValue()
      ..values.add(valueBuilder()..integerValue = Int64(42));

    final proto.StructuredQuery_Filter expectedFilter =
        proto.StructuredQuery_Filter()
          ..fieldFilter = (proto.StructuredQuery_FieldFilter()
            ..field_1 =
                (proto.StructuredQuery_FieldReference()..fieldPath = 'field')
            ..op = proto.StructuredQuery_FieldFilter_Operator.NOT_IN
            ..value = (valueBuilder()..arrayValue = notInFilterValue));

    expect(expectedFilter, apiFilter);
    final FieldFilter roundTripped =
        serializer.decodeFieldFilter(apiFilter.fieldFilter);
    expect(inputFilter, roundTripped);
    expect(roundTripped, isA<NotInFilter>());
  });

  test('testKeyFieldNotInSerialization', () {
    final FieldFilter inputFilter =
        filter('__name__', 'not-in', <Object>[ref('project/database')]);
    final proto.StructuredQuery_Filter apiFilter =
        serializer.encodeUnaryOrFieldFilter(inputFilter);
    final FieldFilter roundTripped =
        serializer.decodeFieldFilter(apiFilter.fieldFilter);
    expect(apiFilter.fieldFilter.op,
        proto.StructuredQuery_FieldFilter_Operator.NOT_IN);
    expect(inputFilter, roundTripped);
    expect(roundTripped, isA<KeyFieldNotInFilter>());
  });

  group('composite filters', () {
    proto.StructuredQuery_FieldFilter fieldFilterProto(
        String path, proto.StructuredQuery_FieldFilter_Operator op, Int64 v) {
      return proto.StructuredQuery_FieldFilter.create()
        ..field_1 =
            (proto.StructuredQuery_FieldReference.create()..fieldPath = path)
        ..op = op
        ..value = (valueBuilder()..integerValue = v);
    }

    proto.StructuredQuery_Filter fieldProto(String path, Int64 v,
            [proto.StructuredQuery_FieldFilter_Operator op =
                proto.StructuredQuery_FieldFilter_Operator.EQUAL]) =>
        proto.StructuredQuery_Filter.create()
          ..fieldFilter = fieldFilterProto(path, op, v);

    proto.StructuredQuery_Filter compositeProto(
            proto.StructuredQuery_CompositeFilter_Operator op,
            List<proto.StructuredQuery_Filter> filters) =>
        proto.StructuredQuery_Filter.create()
          ..compositeFilter = (proto.StructuredQuery_CompositeFilter.create()
            ..op = op
            ..filters.addAll(filters));

    Target roundTrip(Target target) =>
        serializer.decodeQueryTarget(serializer.encodeQueryTarget(target));

    test('testEncodesOrFilter', () {
      final Filter input = orFilters(
          <Filter>[filter('a', '==', 1), filter('b', '==', 2)]);
      final proto.StructuredQuery_Filter encoded =
          serializer.encodeFilter(input);
      expect(
          encoded,
          compositeProto(proto.StructuredQuery_CompositeFilter_Operator.OR, <
              proto.StructuredQuery_Filter>[
            fieldProto('a', Int64(1)),
            fieldProto('b', Int64(2)),
          ]));
      expect(serializer.decodeFilter(encoded), input);
    });

    test('testEncodesNestedCompositeFilters', () {
      final Filter input = andFilters(<Filter>[
        filter('a', '==', 1),
        orFilters(<Filter>[
          filter('b', '>', 2),
          andFilters(<Filter>[filter('c', '==', 3), filter('d', '<', 4)]),
        ]),
      ]);
      final proto.StructuredQuery_Filter encoded =
          serializer.encodeFilter(input);
      expect(
          encoded,
          compositeProto(proto.StructuredQuery_CompositeFilter_Operator.AND, <
              proto.StructuredQuery_Filter>[
            fieldProto('a', Int64(1)),
            compositeProto(proto.StructuredQuery_CompositeFilter_Operator.OR, <
                proto.StructuredQuery_Filter>[
              fieldProto('b', Int64(2),
                  proto.StructuredQuery_FieldFilter_Operator.GREATER_THAN),
              compositeProto(
                  proto.StructuredQuery_CompositeFilter_Operator.AND,
                  <proto.StructuredQuery_Filter>[
                    fieldProto('c', Int64(3)),
                    fieldProto('d', Int64(4),
                        proto.StructuredQuery_FieldFilter_Operator.LESS_THAN),
                  ]),
            ]),
          ]));
      expect(serializer.decodeFilter(encoded), input);
    });

    test('testCompositeFilterWithASingleFilterIsEncodedAsThatFilter', () {
      expect(
          serializer.encodeFilter(
              orFilters(<Filter>[filter('a', '==', 1)])),
          fieldProto('a', Int64(1)));
      expect(
          serializer.encodeFilter(
              andFilters(<Filter>[filter('a', '==', 1)])),
          fieldProto('a', Int64(1)));
    });

    test('testEncodesUnaryFiltersInsideCompositeFilters', () {
      final Filter input = orFilters(<Filter>[
        filter('a', '==', double.nan),
        filter('b', '!=', null),
        filter('c', '==', null),
        filter('d', '!=', double.nan),
      ]);
      final proto.StructuredQuery_Filter encoded =
          serializer.encodeFilter(input);
      expect(encoded.compositeFilter.filters.map((f) => f.hasUnaryFilter()),
          everyElement(isTrue));
      expect(
          encoded.compositeFilter.filters.map((f) => f.unaryFilter.op).toList(),
          <proto.StructuredQuery_UnaryFilter_Operator>[
            proto.StructuredQuery_UnaryFilter_Operator.IS_NAN,
            proto.StructuredQuery_UnaryFilter_Operator.IS_NOT_NULL,
            proto.StructuredQuery_UnaryFilter_Operator.IS_NULL,
            proto.StructuredQuery_UnaryFilter_Operator.IS_NOT_NAN,
          ]);
      expect(serializer.decodeFilter(encoded), input);
    });

    test('testDecodesCompositeFilters', () {
      final proto.StructuredQuery_Filter orProto = compositeProto(
          proto.StructuredQuery_CompositeFilter_Operator.OR,
          <proto.StructuredQuery_Filter>[
            fieldProto('a', Int64(1)),
            fieldProto('b', Int64(2)),
          ]);
      final CompositeFilter decoded =
          serializer.decodeCompositeFilter(orProto.compositeFilter);
      expect(decoded.isDisjunction, isTrue);
      expect(decoded.filters, <Filter>[
        filter('a', '==', 1),
        filter('b', '==', 2),
      ]);
      expect(
          () => serializer.decodeCompositeFilter(
              proto.StructuredQuery_CompositeFilter.create()
                ..op = proto.StructuredQuery_CompositeFilter_Operator
                    .OPERATOR_UNSPECIFIED),
          throwsA(anything));
    });

    test('testEncodesOrFilterInATarget', () {
      final Query q = Query(ResourcePath.fromString('docs'))
          .filter(orFilters(<Filter>[
        filter('a', '==', 1),
        filter('b', '>', 2),
      ])).limit(5);
      final proto_.Target actual = serializer.encodeTarget(wrapQueryData(q));

      final proto.StructuredQuery structuredQuery = actual.query.structuredQuery;
      expect(
          structuredQuery.where,
          compositeProto(proto.StructuredQuery_CompositeFilter_Operator.OR, <
              proto.StructuredQuery_Filter>[
            fieldProto('a', Int64(1)),
            fieldProto('b', Int64(2),
                proto.StructuredQuery_FieldFilter_Operator.GREATER_THAN),
          ]));
      // The inequality on b adds an implicit orderBy b.
      expect(structuredQuery.orderBy.map((o) => o.field_1.fieldPath).toList(),
          <String>['b', DocumentKey.keyFieldName]);
      expect(structuredQuery.limit.value, 5);
      expect(roundTrip(q.toTarget()), q.toTarget());
    });

    test('testTargetFiltersAreAnImplicitAnd', () {
      final Query q = Query(ResourcePath.fromString('docs'))
          .filter(filter('a', '==', 1))
          .filter(orFilters(<Filter>[
        filter('b', '==', 2),
        filter('c', '==', 3),
      ]));
      final proto.StructuredQuery_Filter where = serializer
          .encodeQueryTarget(q.toTarget())
          .structuredQuery
          .where;
      expect(
          where,
          compositeProto(proto.StructuredQuery_CompositeFilter_Operator.AND, <
              proto.StructuredQuery_Filter>[
            fieldProto('a', Int64(1)),
            compositeProto(proto.StructuredQuery_CompositeFilter_Operator.OR, <
                proto.StructuredQuery_Filter>[
              fieldProto('b', Int64(2)),
              fieldProto('c', Int64(3)),
            ]),
          ]));
      expect(roundTrip(q.toTarget()), q.toTarget());
      expect(roundTrip(q.toTarget()).filters.length, 2);
    });

    test('testFlatAndFilterIsDecodedAsAListOfFilters', () {
      // A user AND filter and the older implicit AND of filters share the same
      // wire format and canonical id.
      final Query chained = Query(ResourcePath.fromString('docs'))
          .filter(filter('a', '==', 1))
          .filter(filter('b', '==', 2));
      final Query explicit = Query(ResourcePath.fromString('docs')).filter(
          andFilters(<Filter>[filter('a', '==', 1), filter('b', '==', 2)]));
      expect(serializer.encodeQueryTarget(explicit.toTarget()),
          serializer.encodeQueryTarget(chained.toTarget()));
      expect(roundTrip(explicit.toTarget()).filters,
          <Filter>[filter('a', '==', 1), filter('b', '==', 2)]);
      expect(roundTrip(explicit.toTarget()).canonicalId,
          explicit.toTarget().canonicalId);
    });

    test('testMultipleInequalitiesRoundTrip', () {
      final Query q = Query(ResourcePath.fromString('docs'))
          .filter(filter('a', '>', 1))
          .filter(filter('b', '<', 2))
          .filter(filter('c', '!=', 3));
      final proto.StructuredQuery structuredQuery =
          serializer.encodeQueryTarget(q.toTarget()).structuredQuery;
      expect(structuredQuery.orderBy.map((o) => o.field_1.fieldPath).toList(),
          <String>['a', 'b', 'c', DocumentKey.keyFieldName]);
      expect(roundTrip(q.toTarget()), q.toTarget());
    });

    test('testLimitToLastWithOrFilterRoundTrips', () {
      final Query q = Query(ResourcePath.fromString('docs'))
          .filter(orFilters(<Filter>[
            filter('a', '==', 1),
            filter('b', '==', 2),
          ]))
          .orderBy(orderBy('z'))
          .limitToLast(3);
      // The target (which is what is sent) has flipped orderings.
      final proto.StructuredQuery structuredQuery =
          serializer.encodeQueryTarget(q.toTarget()).structuredQuery;
      expect(
          structuredQuery.orderBy.map((o) => o.direction).toSet(),
          <proto.StructuredQuery_Direction>{
            proto.StructuredQuery_Direction.DESCENDING
          });
      expect(roundTrip(q.toTarget()), q.toTarget());
    });
  });

  test('testDecodesUnaryNotFilters', () {
    for (final MapEntry<proto.StructuredQuery_UnaryFilter_Operator,
            FieldValue> entry
        in <proto.StructuredQuery_UnaryFilter_Operator, FieldValue>{
      proto.StructuredQuery_UnaryFilter_Operator.IS_NOT_NAN: DoubleValue.nan,
      proto.StructuredQuery_UnaryFilter_Operator.IS_NOT_NULL:
          NullValue.nullValue(),
    }.entries) {
      final proto.StructuredQuery_Filter filter = proto.StructuredQuery_Filter()
        ..unaryFilter = (proto.StructuredQuery_UnaryFilter()
          ..field_2 =
              (proto.StructuredQuery_FieldReference()..fieldPath = 'prop')
          ..op = entry.key);
      final proto.StructuredQuery structuredQuery = proto.StructuredQuery()
        ..from.add(
            proto.StructuredQuery_CollectionSelector()..collectionId = 'docs')
        ..where = filter;
      final proto_.Target_QueryTarget target = proto_.Target_QueryTarget()
        ..parent = 'projects/p/databases/d/documents'
        ..structuredQuery = structuredQuery;
      final Target decoded = serializer.decodeQueryTarget(target);
      expect(decoded.filters, hasLength(1));
      expect(decoded.filters.first,
          FieldFilter(field('prop'), FilterOperator.notEqual, entry.value));
    }
  });

  test('testInSerialization', () {
    final FieldFilter inputFilter =
        filter('field', 'in', <int>[42]);
    final proto.StructuredQuery_Filter apiFilter =
        serializer.encodeUnaryOrFieldFilter(inputFilter);

    final proto.ArrayValue inFilterValue = proto.ArrayValue()
      ..values.add(valueBuilder()..integerValue = Int64(42));

    final proto.StructuredQuery_Filter expectedFilter =
        proto.StructuredQuery_Filter()
          ..fieldFilter = (proto.StructuredQuery_FieldFilter()
            ..field_1 =
                (proto.StructuredQuery_FieldReference()..fieldPath = 'field')
            ..op = proto.StructuredQuery_FieldFilter_Operator.IN
            ..value = (valueBuilder()..arrayValue = inFilterValue));

    expect(expectedFilter, apiFilter);
    final FieldFilter roundTripped =
        serializer.decodeFieldFilter(apiFilter.fieldFilter);
    expect(inputFilter, roundTripped);
    expect(roundTripped, isA<InFilter>());
  });

  test('testArrayContainsAnySerialization', () {
    final FieldFilter inputFilter =
        filter('field', 'array-contains-any', <int>[42]);
    final proto.StructuredQuery_Filter apiFilter =
        serializer.encodeUnaryOrFieldFilter(inputFilter);

    final proto.ArrayValue arrayContainsAnyFilterValue = proto.ArrayValue()
      ..values.add(valueBuilder()..integerValue = Int64(42));

    final proto.StructuredQuery_Filter expectedFilter =
        proto.StructuredQuery_Filter()
          ..fieldFilter = (proto.StructuredQuery_FieldFilter()
            ..field_1 =
                (proto.StructuredQuery_FieldReference()..fieldPath = 'field')
            ..op = proto.StructuredQuery_FieldFilter_Operator.ARRAY_CONTAINS_ANY
            ..value =
                (valueBuilder()..arrayValue = arrayContainsAnyFilterValue));

    expect(expectedFilter, apiFilter);
    final FieldFilter roundTripped =
        serializer.decodeFieldFilter(apiFilter.fieldFilter);
    expect(inputFilter, roundTripped);
    expect(roundTripped, isA<ArrayContainsAnyFilter>());
  });

  test('testKeyFieldSerializationEncoding', () {
    final FieldFilter inputFilter =
        filter('__name__', '==', ref('project/database'));
    final proto.StructuredQuery_Filter apiFilter =
        serializer.encodeUnaryOrFieldFilter(inputFilter);

    final proto.StructuredQuery_Filter expectedFilter =
        proto.StructuredQuery_Filter()
          ..fieldFilter = (proto.StructuredQuery_FieldFilter()
            ..field_1 =
                (proto.StructuredQuery_FieldReference()..fieldPath = '__name__')
            ..op = proto.StructuredQuery_FieldFilter_Operator.EQUAL
            ..value = (valueBuilder()
              ..referenceValue =
                  'projects/project/databases/(default)/documents/project/database'))
          ..freeze();

    expect(expectedFilter, apiFilter);
    final FieldFilter roundTripped =
        serializer.decodeFieldFilter(apiFilter.fieldFilter);
    expect(inputFilter, roundTripped);
    expect(roundTripped, isA<KeyFieldFilter>());
  });

  // TODO(PORTING-NOTE): Android currently tests most filter serialization (for
  //  equals, greater than, array-contains, etc.) only in
  //  testEncodesMultipleFiltersOnDeeperCollections and lacks isolated filter
  //  tests like the other platforms have. We should fix this.

  test('testEncodesNullFilter', () {
    unaryFilterTest(null, proto.StructuredQuery_UnaryFilter_Operator.IS_NULL);
  });

  test('testEncodesNaNFilter', () {
    unaryFilterTest(
        double.nan, proto.StructuredQuery_UnaryFilter_Operator.IS_NAN);
  });

  test('testEncodesNotNullFilter', () {
    unaryFilterTest(
        null, proto.StructuredQuery_UnaryFilter_Operator.IS_NOT_NULL, '!=');
  });

  test('testEncodesNotNaNFilter', () {
    unaryFilterTest(double.nan,
        proto.StructuredQuery_UnaryFilter_Operator.IS_NOT_NAN, '!=');
  });

  test('testEncodesSortOrders', () {
    final Query q =
        Query(ResourcePath.fromString('docs')).orderBy(orderBy('prop'));
    final proto_.Target actual = serializer.encodeTarget(wrapQueryData(q));

    final proto.StructuredQuery structuredQueryBuilder =
        proto.StructuredQuery.create()
          ..from.add(proto.StructuredQuery_CollectionSelector.create()
            ..collectionId = 'docs')
          ..orderBy.add(proto.StructuredQuery_Order.create()
            ..direction = proto.StructuredQuery_Direction.ASCENDING
            ..field_1 = (proto.StructuredQuery_FieldReference.create()
              ..fieldPath = 'prop'))
          ..orderBy.add(defaultKeyOrder());

    final proto_.Target_QueryTarget queryBuilder =
        proto.Target_QueryTarget.create()
          ..parent = 'projects/p/databases/d/documents'
          ..structuredQuery = structuredQueryBuilder;

    final proto_.Target expected = proto_.Target.create()
      ..query = queryBuilder
      ..targetId = 1
      ..resumeToken = _resumeToken
      ..freeze();

    expect(actual, expected);
    expect(
        q.toTarget(),
        serializer
            .decodeQueryTarget(serializer.encodeQueryTarget(q.toTarget())));
  });

  test('testEncodesSortOrdersDescending', () {
    final Query q =
        Query(ResourcePath.fromString('rooms/1/messages/10/attachments'))
            .orderBy(orderBy('prop', 'desc'));
    final proto_.Target actual = serializer.encodeTarget(wrapQueryData(q));

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

    final proto_.Target_QueryTarget queryBuilder =
        proto.Target_QueryTarget.create()
          ..parent = 'projects/p/databases/d/documents/rooms/1/messages/10'
          ..structuredQuery = structuredQueryBuilder;

    final proto_.Target expected = proto_.Target.create()
      ..query = queryBuilder
      ..targetId = 1
      ..resumeToken = Int8List.fromList(<int>[])
      ..freeze();

    expect(actual, expected);
    expect(
        q.toTarget(),
        serializer
            .decodeQueryTarget(serializer.encodeQueryTarget(q.toTarget())));
  });

  test('testEncodesLimits', () {
    final Query q = Query(ResourcePath.fromString('docs')).limit(26);
    final proto_.Target actual = serializer.encodeTarget(wrapQueryData(q));

    final proto.StructuredQuery structuredQueryBuilder =
        proto.StructuredQuery.create()
          ..from.add(proto.StructuredQuery_CollectionSelector.create()
            ..collectionId = 'docs')
          ..orderBy.add(defaultKeyOrder())
          ..limit = (proto.Int32Value()..value = 26);

    final proto_.Target_QueryTarget queryBuilder =
        proto.Target_QueryTarget.create()
          ..parent = 'projects/p/databases/d/documents'
          ..structuredQuery = structuredQueryBuilder;

    final proto_.Target expected = proto_.Target.create()
      ..query = queryBuilder
      ..targetId = 1
      ..resumeToken = Int8List.fromList(<int>[])
      ..freeze();

    expect(actual, expected);
    expect(
        q.toTarget(),
        serializer
            .decodeQueryTarget(serializer.encodeQueryTarget(q.toTarget())));
  });

  test('testEncodesLimitToLastWithFlippedOrderAndBounds', () {
    final Query q = Query(ResourcePath.fromString('docs'))
        .orderBy(orderBy('prop'))
        .startAt(Bound(position: <ReferenceValue>[
          ReferenceValue.valueOf(databaseId, key('foo/bar'))
        ], inclusive: true))
        .endAt(Bound(position: <ReferenceValue>[
          ReferenceValue.valueOf(databaseId, key('foo/baz'))
        ], inclusive: true))
        .limitToLast(5);

    final proto_.Target actual = serializer.encodeTarget(wrapQueryData(q));

    final proto.StructuredQuery structuredQueryBuilder =
        proto.StructuredQuery.create()
          ..from.add(proto.StructuredQuery_CollectionSelector.create()
            ..collectionId = 'docs')
          ..orderBy.add(proto.StructuredQuery_Order.create()
            ..direction = proto.StructuredQuery_Direction.DESCENDING
            ..field_1 = (proto.StructuredQuery_FieldReference.create()
              ..fieldPath = 'prop'))
          ..orderBy.add(proto.StructuredQuery_Order.create()
            ..direction = proto.StructuredQuery_Direction.DESCENDING
            ..field_1 = (proto.StructuredQuery_FieldReference.create()
              ..fieldPath = DocumentKey.keyFieldName))
          ..limit = (proto.Int32Value()..value = 5)
          // The cursors are swapped and flipped to match the flipped ordering.
          ..startAt = (proto.Cursor.create()
            ..before = true
            ..values.add(valueBuilder()
              ..referenceValue = 'projects/p/databases/d/documents/foo/baz'))
          ..endAt = (proto.Cursor.create()
            ..before = false
            ..values.add(valueBuilder()
              ..referenceValue = 'projects/p/databases/d/documents/foo/bar'));

    final proto_.Target_QueryTarget queryBuilder =
        proto.Target_QueryTarget.create()
          ..parent = 'projects/p/databases/d/documents'
          ..structuredQuery = structuredQueryBuilder;

    final proto_.Target expected = proto_.Target.create()
      ..query = queryBuilder
      ..targetId = 1
      ..resumeToken = Int8List.fromList(<int>[])
      ..freeze();

    expect(actual, expected);
    expect(
        q.toTarget(),
        serializer
            .decodeQueryTarget(serializer.encodeQueryTarget(q.toTarget())));
  });

  test('testLimitToLastAndMirroringLimitQueryEncodeTheSameTarget', () {
    final Query limit = Query(ResourcePath.fromString('docs'))
        .orderBy(orderBy('prop'))
        .limit(3);
    final Query limitToLast = Query(ResourcePath.fromString('docs'))
        .orderBy(orderBy('prop', 'desc'))
        .limitToLast(3);

    expect(serializer.encodeTarget(wrapQueryData(limitToLast)),
        serializer.encodeTarget(wrapQueryData(limit)));
  });

  test('testEncodesBounds', () {
    final Query q = Query(ResourcePath.fromString('docs'))
        .startAt(Bound(position: <ReferenceValue>[
          ReferenceValue.valueOf(databaseId, key('foo/bar'))
        ], inclusive: true))
        .endAt(Bound(position: <ReferenceValue>[
          ReferenceValue.valueOf(databaseId, key('foo/baz'))
        ], inclusive: true));

    final proto_.Target actual = serializer.encodeTarget(wrapQueryData(q));

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

    final proto_.Target_QueryTarget queryBuilder =
        proto.Target_QueryTarget.create()
          ..parent = 'projects/p/databases/d/documents'
          ..structuredQuery = structuredQueryBuilder;

    final proto_.Target expected = proto_.Target.create()
      ..query = queryBuilder
      ..targetId = 1
      ..resumeToken = _resumeToken
      ..freeze();

    expect(actual, expected);
    expect(
        q.toTarget(),
        serializer
            .decodeQueryTarget(serializer.encodeQueryTarget(q.toTarget())));
  });

  test('testEncodesResumeTokens', () {
    final Query q = Query(ResourcePath.fromString('docs'));
    final proto_.Target actual = serializer.encodeTarget(QueryData(q.toTarget(),
        1, 2, QueryPurpose.listen, SnapshotVersion.none, resumeToken(1000)));

    final proto.StructuredQuery structuredQueryBuilder =
        proto.StructuredQuery.create()
          ..from.add(proto.StructuredQuery_CollectionSelector.create()
            ..collectionId = 'docs')
          ..orderBy.add(defaultKeyOrder());

    final proto_.Target_QueryTarget queryBuilder =
        proto.Target_QueryTarget.create()
          ..parent = 'projects/p/databases/d/documents'
          ..structuredQuery = structuredQueryBuilder;

    final proto_.Target expected = proto_.Target.create()
      ..query = queryBuilder
      ..targetId = 1
      ..resumeToken = resumeToken(1000)!
      ..freeze();

    expect(actual, expected);
    expect(
        q.toTarget(),
        serializer
            .decodeQueryTarget(serializer.encodeQueryTarget(q.toTarget())));
  });

  test('testEncodesReadTime', () {
    final Query q = Query(ResourcePath.fromString('docs'));
    final proto_.Target actual = serializer.encodeTarget(QueryData(q.toTarget(), 1, 2,
        QueryPurpose.listen, version(4000000), Uint8List(0)));

    final proto.StructuredQuery structuredQueryBuilder =
        proto.StructuredQuery.create()
          ..from.add(proto.StructuredQuery_CollectionSelector.create()
            ..collectionId = 'docs')
          ..orderBy.add(defaultKeyOrder());

    final proto_.Target_QueryTarget queryBuilder =
        proto.Target_QueryTarget.create()
          ..parent = 'projects/p/databases/d/documents'
          ..structuredQuery = structuredQueryBuilder;

    final proto_.Target expected = proto_.Target.create()
      ..query = queryBuilder
      ..targetId = 1
      // encodeTimestamp() sets nanos explicitly; Dart protobuf equality tells
      // an explicit zero apart from an unset field, the wire bytes are equal.
      ..readTime = proto.Timestamp(seconds: Int64(4), nanos: 0)
      ..freeze();

    expect(actual, expected);
    expect(
        q.toTarget(),
        serializer
            .decodeQueryTarget(serializer.encodeQueryTarget(q.toTarget())));
  });

  test('encodesExpectedCountWhenResumeTokenIsPresent', () {
    final Query q = Query(ResourcePath.fromString('docs'));
    final proto_.Target actual = serializer.encodeTarget(QueryData(q.toTarget(), 1, 2,
        QueryPurpose.listen, SnapshotVersion.none, resumeToken(1000), 42));

    final proto.StructuredQuery structuredQueryBuilder =
        proto.StructuredQuery.create()
          ..from.add(proto.StructuredQuery_CollectionSelector.create()
            ..collectionId = 'docs')
          ..orderBy.add(defaultKeyOrder());

    final proto_.Target_QueryTarget queryBuilder =
        proto.Target_QueryTarget.create()
          ..parent = 'projects/p/databases/d/documents'
          ..structuredQuery = structuredQueryBuilder;

    final proto_.Target expected = proto_.Target.create()
      ..query = queryBuilder
      ..targetId = 1
      ..resumeToken = resumeToken(1000)!
      ..expectedCount = proto.Int32Value(value: 42)
      ..freeze();

    expect(actual, expected);
    expect(
        q.toTarget(),
        serializer
            .decodeQueryTarget(serializer.encodeQueryTarget(q.toTarget())));
  });

  test('encodesExpectedCountWhenReadTimeIsPresent', () {
    final Query q = Query(ResourcePath.fromString('docs'));
    final proto_.Target actual = serializer.encodeTarget(QueryData(q.toTarget(), 1, 2,
        QueryPurpose.listen, version(4000000), Uint8List(0), 42));

    final proto.StructuredQuery structuredQueryBuilder =
        proto.StructuredQuery.create()
          ..from.add(proto.StructuredQuery_CollectionSelector.create()
            ..collectionId = 'docs')
          ..orderBy.add(defaultKeyOrder());

    final proto_.Target_QueryTarget queryBuilder =
        proto.Target_QueryTarget.create()
          ..parent = 'projects/p/databases/d/documents'
          ..structuredQuery = structuredQueryBuilder;

    final proto_.Target expected = proto_.Target.create()
      ..query = queryBuilder
      ..targetId = 1
      // encodeTimestamp() sets nanos explicitly; Dart protobuf equality tells
      // an explicit zero apart from an unset field, the wire bytes are equal.
      ..readTime = proto.Timestamp(seconds: Int64(4), nanos: 0)
      ..expectedCount = proto.Int32Value(value: 42)
      ..freeze();

    expect(actual, expected);
    expect(
        q.toTarget(),
        serializer
            .decodeQueryTarget(serializer.encodeQueryTarget(q.toTarget())));
  });

  test('shouldIgnoreExpectedCountWithoutResumeTokenOrReadTime', () {
    final Query q = Query(ResourcePath.fromString('docs'));
    final proto_.Target actual = serializer.encodeTarget(QueryData(q.toTarget(), 1, 2,
        QueryPurpose.listen, SnapshotVersion.none, Uint8List(0), 42));

    final proto.StructuredQuery structuredQueryBuilder =
        proto.StructuredQuery.create()
          ..from.add(proto.StructuredQuery_CollectionSelector.create()
            ..collectionId = 'docs')
          ..orderBy.add(defaultKeyOrder());

    final proto_.Target_QueryTarget queryBuilder =
        proto.Target_QueryTarget.create()
          ..parent = 'projects/p/databases/d/documents'
          ..structuredQuery = structuredQueryBuilder;

    final proto_.Target expected = proto_.Target.create()
      ..query = queryBuilder
      ..targetId = 1
      ..freeze();

    expect(actual, expected);
    expect(
        q.toTarget(),
        serializer
            .decodeQueryTarget(serializer.encodeQueryTarget(q.toTarget())));
  });

  test('testConvertsTargetChangeWithAdded', () {
    final WatchChangeWatchTargetChange expected =
        WatchChangeWatchTargetChange(WatchTargetChangeType.added, <int>[1, 4]);

    final WatchChangeWatchTargetChange actual =
        serializer.decodeWatchChange(proto.ListenResponse.create()
          ..targetChange = (proto.TargetChange.create()
            ..targetChangeType = proto_.TargetChange_TargetChangeType.ADD
            ..targetIds.add(1)
            ..targetIds.add(4))
          ..freeze()) as WatchChangeWatchTargetChange;

    expect(actual, expected);
  });

  test('testConvertsTargetChangeWithRemoved', () {
    final WatchChangeWatchTargetChange expected = WatchChangeWatchTargetChange(
        WatchTargetChangeType.removed,
        <int>[1, 4],
        Uint8List.fromList(<int>[0, 1, 2]),
        const GrpcError.permissionDenied());

    final WatchChangeWatchTargetChange actual =
        serializer.decodeWatchChange(proto.ListenResponse.create()
          ..targetChange = (proto.TargetChange.create()
            ..targetChangeType = proto_.TargetChange_TargetChangeType.REMOVE
            ..targetIds.add(1)
            ..targetIds.add(4)
            ..cause = (proto.Status.create()..code = 7)
            ..resumeToken = Uint8List.fromList(<int>[0, 1, 2]))
          ..freeze()) as WatchChangeWatchTargetChange;

    expect(actual, expected);
  });

  test('testConvertsTargetChangeWithNoChange', () {
    final WatchChangeWatchTargetChange expected = WatchChangeWatchTargetChange(
        WatchTargetChangeType.noChange, <int>[1, 4]);

    final WatchChangeWatchTargetChange actual =
        serializer.decodeWatchChange(proto.ListenResponse()
          ..targetChange = (proto.TargetChange()
            ..targetChangeType = proto_.TargetChange_TargetChangeType.NO_CHANGE
            ..targetIds.add(1)
            ..targetIds.add(4))
          ..freeze()) as WatchChangeWatchTargetChange;

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
              ..updateTime =
                  serializer.encodeTimestamp(const Timestamp(0, 5000))
              ..fields['foo'] = (proto_.Value()..stringValue = 'bar'))
            ..targetIds.add(1)
            ..targetIds.add(2))
          ..freeze()) as WatchChangeDocumentChange;

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
              ..updateTime =
                  serializer.encodeTimestamp(const Timestamp(0, 5000))
              ..fields['foo'] = (proto_.Value()..stringValue = 'bar'))
            ..targetIds.add(2)
            ..removedTargetIds.add(1))
          ..freeze()) as WatchChangeDocumentChange;

    expect(actual, expected);
  });

  test('testConvertsDocumentChangeWithDeletions', () {
    final WatchChangeDocumentChange expected = WatchChangeDocumentChange(
        <int>[], <int>[1, 2], key('coll/1'), deletedDoc('coll/1', 5));

    final WatchChangeDocumentChange actual =
        serializer.decodeWatchChange(proto.ListenResponse()
          ..documentDelete = (proto.DocumentDelete()
            ..document = serializer.encodeKey(key('coll/1'))
            ..readTime = serializer.encodeTimestamp(const Timestamp(0, 5000))
            ..removedTargetIds.add(1)
            ..removedTargetIds.add(2))
          ..freeze()) as WatchChangeDocumentChange;

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
          ..freeze()) as WatchChangeDocumentChange;

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
