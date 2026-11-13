// Ports the cases of the JS SDK test/unit/remote/serializer.helper.ts that the
// Android RemoteSerializerTest (remote_serializer_test.dart) has no
// counterpart for. Group and test names are the JS ones.
//
// JS checks two encodings of each proto, the proto3 JSON one and the
// protobuf.js one. This port has only the protobuf message, so the
// expectations are the protobuf.js ones; the JSON encoding is covered by
// web/proto3_json_test.dart.

import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/blob.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bson_object_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bson_timestamp.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/filter/filter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/order_by.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/target.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/decimal128_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/field_value.dart'
    as firestore;
import 'package:cloud_firestore_dart/src/firebase/firestore/int32_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_purpose.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/max_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/min_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/set_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/regex_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/watch_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/user_data_converter.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as proto_v1;
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;
import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';

void main() {
  final RemoteSerializer s = RemoteSerializer(DatabaseId.forDatabase('p', 'd'));

  /// The JS `wrapTargetData()`.
  QueryData wrapTargetData(Target target) {
    return QueryData(
      target,
      1,
      2,
      QueryPurpose.listen,
      SnapshotVersion.none,
      Uint8List(0),
    );
  }

  /// The JS TestUtil `setMutation()`: parses [values] like a `set()` call, so
  /// field value sentinels become field transforms.
  Mutation setMutationWithTransforms(String path, Map<String, Object?> values) {
    return UserDataConverter(
      DatabaseId.forProject('project'),
    ).parseSetData(values).toMutation(key(path), Precondition.none);
  }

  proto.MapValue mapValue(Map<String, proto_v1.Value> fields) {
    return proto.MapValue()..fields.addAll(fields);
  }

  proto.Document document(String name, Map<String, proto_v1.Value> fields) {
    return proto.Document(name: name)..fields.addAll(fields);
  }

  proto.StructuredQuery_Filter fieldFilterProto(
    String path,
    proto.StructuredQuery_FieldFilter_Operator op,
    proto_v1.Value value,
  ) {
    return proto.StructuredQuery_Filter()
      ..fieldFilter = (proto.StructuredQuery_FieldFilter()
        ..field_1 = (proto.StructuredQuery_FieldReference()..fieldPath = path)
        ..op = op
        ..value = value);
  }

  proto.StructuredQuery_Filter unaryFilterProto(
    String path,
    proto.StructuredQuery_UnaryFilter_Operator op,
  ) {
    return proto.StructuredQuery_Filter()
      ..unaryFilter = (proto.StructuredQuery_UnaryFilter()
        ..field_2 = (proto.StructuredQuery_FieldReference()..fieldPath = path)
        ..op = op);
  }

  proto.StructuredQuery_Order orderProto(
    String path,
    proto.StructuredQuery_Direction direction,
  ) {
    return proto.StructuredQuery_Order()
      ..field_1 = (proto.StructuredQuery_FieldReference()..fieldPath = path)
      ..direction = direction;
  }

  group('Serializer', () {
    group('converts value', () {
      /// Encodes [value] (a user value), checks the proto against [expected],
      /// and checks that decoding it gives the value back.
      void verifyFieldValueRoundTrip(Object? value, proto_v1.Value expected) {
        final FieldValue model = wrap(value);
        final proto_v1.Value actual = s.encodeValue(model);
        expect(actual, expected);
        expect(s.decodeValue(actual), model);
      }

      test('converts NaN', () {
        // NaN != NaN, so the proto is checked field by field.
        final FieldValue model = wrap(double.nan);
        final proto_v1.Value actual = s.encodeValue(model);
        expect(actual.hasDoubleValue(), isTrue);
        expect(actual.doubleValue, isNaN);
        expect(s.decodeValue(actual), model);
      });

      test('converts Infinity', () {
        verifyFieldValueRoundTrip(
          double.infinity,
          proto_v1.Value(doubleValue: double.infinity),
        );
        verifyFieldValueRoundTrip(
          double.negativeInfinity,
          proto_v1.Value(doubleValue: double.negativeInfinity),
        );
      });

      test('converts TimestampValue from proto', () {
        final List<Timestamp> examples = <Timestamp>[
          const Timestamp(1451730050, 850000000),
          const Timestamp(1466160615, 0),
        ];
        final List<proto.Timestamp> expectedProtoJs = <proto.Timestamp>[
          proto.Timestamp(seconds: Int64(1451730050), nanos: 850000000),
          proto.Timestamp(seconds: Int64(1466160615), nanos: 0),
        ];

        for (int i = 0; i < examples.length; i++) {
          verifyFieldValueRoundTrip(
            examples[i],
            proto_v1.Value(timestampValue: expectedProtoJs[i]),
          );
        }
      });

      test('converts empty ArrayValue', () {
        verifyFieldValueRoundTrip(
          <Object>[],
          proto_v1.Value(arrayValue: proto.ArrayValue()),
        );
      });

      test('converts empty ObjectValue', () {
        verifyFieldValueRoundTrip(
          <String, Object>{},
          proto_v1.Value(mapValue: proto.MapValue()),
        );
      });

      test('converts BSON types in mapValue', () {
        final List<Object> examples = <Object>[
          const BsonObjectId('foo'),
          BsonTimestamp(1, 2),
          MinKey.instance,
          MaxKey.instance,
          const RegexValue('a', 'b'),
          Int32Value(1),
          Decimal128Value('1.2e3'),
        ];

        for (final Object example in examples) {
          final proto_v1.Value encoded = s.encodeValue(wrap(example));
          expect(encoded.hasMapValue(), isTrue, reason: '$example');
          verifyFieldValueRoundTrip(example, encoded);
        }

        // The subtype of BSON binary data is the first byte of the bytes.
        final Blob bsonBinary = Blob.bsonBinary(
          1,
          Uint8List.fromList(<int>[1, 2, 3]),
        );
        final proto_v1.Value expectedProtoJson = proto_v1.Value(
          mapValue: mapValue(<String, proto_v1.Value>{
            '__binary__': proto_v1.Value(bytesValue: <int>[1, 1, 2, 3]),
          }),
        );
        verifyFieldValueRoundTrip(bsonBinary, expectedProtoJson);
      });
    });

    group('toKey', () {
      test('converts an empty key', () {
        final String obj = s.encodeKey(DocumentKey.empty());
        expect(obj, 'projects/p/databases/d/documents');
      });

      test('converts a regular key', () {
        final String actual = s.encodeKey(key('docs/1'));
        expect(actual, 'projects/p/databases/d/documents/docs/1');
      });

      test('converts a long key', () {
        // Number.MAX_SAFE_INTEGER
        const int maxSafeInteger = 9007199254740991;
        final String actual = s.encodeKey(
          key('users/$maxSafeInteger/profiles/primary'),
        );
        expect(
          actual,
          'projects/p/databases/d/documents/users/$maxSafeInteger/profiles/primary',
        );
      });
    });

    group('fromKey', () {
      test('converts an empty key', () {
        final DocumentKey expected = DocumentKey.empty();
        final DocumentKey actual = s.decodeKey(s.encodeKey(expected));
        expect(actual, expected);
      });

      test('converts a regular key', () {
        final DocumentKey expected = key('docs/1/part/2');
        final DocumentKey actual = s.decodeKey(s.encodeKey(expected));
        expect(actual, expected);
      });

      test('converts default-value containing key', () {
        final DocumentKey expected = key('docs/1');
        final DocumentKey actual = s.decodeKey(s.encodeKey(expected));
        expect(actual, expected);
      });
    });

    group('toMutation / fromMutation', () {
      void verifyMutation(Mutation mutation, proto.Write expected) {
        final proto.Write serialized = s.encodeMutation(mutation);
        expect(serialized, expected);
        expect(s.decodeMutation(serialized), mutation);
      }

      test('SetMutation', () {
        final SetMutation mutation = setMutation('foo/bar', <String, Object?>{
          'a': 'b',
          'num': 1,
        });
        final proto.Write expected = proto.Write(
          update: s.encodeDocument(mutation.key, mutation.value),
        );
        verifyMutation(mutation, expected);
      });

      test('PatchMutation', () {
        final Mutation mutation = patchMutation('bar/baz', <String, Object?>{
          'a': 'b',
          'num': 1,
          'some.deep.thing': 2,
        });
        final proto.Write expected = proto.Write(
          update: document(
            'projects/p/databases/d/documents/bar/baz',
            <String, proto_v1.Value>{
              'a': proto_v1.Value(stringValue: 'b'),
              'num': proto_v1.Value(integerValue: Int64(1)),
              'some': proto_v1.Value(
                mapValue: mapValue(<String, proto_v1.Value>{
                  'deep': proto_v1.Value(
                    mapValue: mapValue(<String, proto_v1.Value>{
                      'thing': proto_v1.Value(integerValue: Int64(2)),
                    }),
                  ),
                }),
              ),
            },
          ),
          updateMask: proto.DocumentMask(
            fieldPaths: <String>['a', 'num', 'some.deep.thing'],
          ),
          currentDocument: proto.Precondition(exists: true),
        );
        verifyMutation(mutation, expected);
      });

      test('PatchMutation without precondition', () {
        final Mutation mutation = patchMutation(
          'bar/baz',
          <String, Object?>{'a': 'b', 'num': 1, 'some.deep.thing': 2},
          <FieldPath>[field('a'), field('num'), field('some.deep.thing')],
        );
        expect(mutation.precondition, Precondition.none);
        final proto.Write expected = proto.Write(
          update: document(
            'projects/p/databases/d/documents/bar/baz',
            <String, proto_v1.Value>{
              'a': proto_v1.Value(stringValue: 'b'),
              'num': proto_v1.Value(integerValue: Int64(1)),
              'some': proto_v1.Value(
                mapValue: mapValue(<String, proto_v1.Value>{
                  'deep': proto_v1.Value(
                    mapValue: mapValue(<String, proto_v1.Value>{
                      'thing': proto_v1.Value(integerValue: Int64(2)),
                    }),
                  ),
                }),
              ),
            },
          ),
          updateMask: proto.DocumentMask(
            fieldPaths: <String>['a', 'num', 'some.deep.thing'],
          ),
        );
        verifyMutation(mutation, expected);
      });

      test('ServerTimestamp transform', () {
        final Mutation mutation2 = setMutationWithTransforms(
          'baz/quux',
          <String, Object?>{'a': firestore.FieldValue.serverTimestamp()},
        );
        final proto.Write proto2 = proto.Write(
          update: proto.Document(
            name: 'projects/p/databases/d/documents/baz/quux',
          ),
          updateTransforms: <proto.DocumentTransform_FieldTransform>[
            proto.DocumentTransform_FieldTransform(
              fieldPath: 'a',
              setToServerValue: proto
                  .DocumentTransform_FieldTransform_ServerValue
                  .REQUEST_TIME,
            ),
          ],
        );
        verifyMutation(mutation2, proto2);
      });

      test('Numeric Add transform', () {
        final Mutation mutation =
            setMutationWithTransforms('baz/quux', <String, Object?>{
              'integer': firestore.FieldValue.increment(42),
              'double': firestore.FieldValue.increment(13.37),
            });
        final proto.Write expected = proto.Write(
          update: proto.Document(
            name: 'projects/p/databases/d/documents/baz/quux',
          ),
          updateTransforms: <proto.DocumentTransform_FieldTransform>[
            proto.DocumentTransform_FieldTransform(
              fieldPath: 'integer',
              increment: proto_v1.Value(integerValue: Int64(42)),
            ),
            proto.DocumentTransform_FieldTransform(
              fieldPath: 'double',
              increment: proto_v1.Value(doubleValue: 13.37),
            ),
          ],
        );
        verifyMutation(mutation, expected);
      });

      test('SetMutation with precondition', () {
        final SetMutation mutation = SetMutation(
          key('foo/bar'),
          wrapMap(<String, Object?>{'a': 'b', 'num': 1}),
          Precondition(updateTime: version(4)),
        );
        final proto.Write expected = proto.Write(
          update: s.encodeDocument(mutation.key, mutation.value),
          currentDocument: proto.Precondition(
            updateTime: proto.Timestamp(seconds: Int64(0), nanos: 4000),
          ),
        );
        verifyMutation(mutation, expected);
      });
    });

    group('to/from UnaryOrFieldFilter', () {
      void verifyFieldFilter(
        FieldFilter input,
        proto.StructuredQuery_Filter expected,
      ) {
        final proto.StructuredQuery_Filter actual = s.encodeUnaryOrFieldFilter(
          input,
        );
        expect(actual, expected);
        final FieldFilter roundtripped = s.decodeFieldFilter(
          actual.fieldFilter,
        );
        expect(roundtripped, input);
        expect(roundtripped.runtimeType, input.runtimeType);
      }

      test('makes dotted-property names', () {
        final FieldPath path = FieldPath.fromSegments(<String>[
          'item',
          'part',
          'top',
        ]);
        final FieldFilter input = FieldFilter(
          path,
          FilterOperator.equal,
          wrap('food'),
        );
        verifyFieldFilter(
          input,
          fieldFilterProto(
            'item.part.top',
            proto.StructuredQuery_FieldFilter_Operator.EQUAL,
            proto_v1.Value(stringValue: 'food'),
          ),
        );
      });

      test('converts LessThan', () {
        verifyFieldFilter(
          filter('field', '<', 42),
          fieldFilterProto(
            'field',
            proto.StructuredQuery_FieldFilter_Operator.LESS_THAN,
            proto_v1.Value(integerValue: Int64(42)),
          ),
        );
      });

      test('converts LessThanOrEqual', () {
        verifyFieldFilter(
          filter('field', '<=', 'food'),
          fieldFilterProto(
            'field',
            proto.StructuredQuery_FieldFilter_Operator.LESS_THAN_OR_EQUAL,
            proto_v1.Value(stringValue: 'food'),
          ),
        );
      });

      test('converts GreaterThan', () {
        verifyFieldFilter(
          filter('field', '>', false),
          fieldFilterProto(
            'field',
            proto.StructuredQuery_FieldFilter_Operator.GREATER_THAN,
            proto_v1.Value(booleanValue: false),
          ),
        );
      });

      test('converts GreaterThanOrEqual', () {
        verifyFieldFilter(
          filter('field', '>=', 1e100),
          fieldFilterProto(
            'field',
            proto.StructuredQuery_FieldFilter_Operator.GREATER_THAN_OR_EQUAL,
            proto_v1.Value(doubleValue: 1e100),
          ),
        );
      });

      test('converts array-contains', () {
        verifyFieldFilter(
          filter('field', 'array-contains', 42),
          fieldFilterProto(
            'field',
            proto.StructuredQuery_FieldFilter_Operator.ARRAY_CONTAINS,
            proto_v1.Value(integerValue: Int64(42)),
          ),
        );
      });
    });

    group('toTarget', () {
      test(
        'converts multi-layer composite filters with OR at the first layer',
        () {
          final Target q = query('docs')
              .filter(
                orFilters(<Filter>[
                  filter('prop', '<', 42),
                  filter('name', '==', 'dimond'),
                  andFilters(<Filter>[
                    filter('nan', '==', double.nan),
                    filter('null', '==', null),
                    filter('tags', 'array-contains', 'pending'),
                  ]),
                ]),
              )
              .toTarget();
          final proto_v1.Target result = s.encodeTarget(wrapTargetData(q));
          final proto_v1.Target expected = proto_v1.Target(
            query: proto.Target_QueryTarget(
              parent: 'projects/p/databases/d/documents',
              structuredQuery: proto.StructuredQuery(
                from: <proto.StructuredQuery_CollectionSelector>[
                  proto.StructuredQuery_CollectionSelector(
                    collectionId: 'docs',
                  ),
                ],
                where: proto.StructuredQuery_Filter(
                  compositeFilter: proto.StructuredQuery_CompositeFilter(
                    op: proto.StructuredQuery_CompositeFilter_Operator.OR,
                    filters: <proto.StructuredQuery_Filter>[
                      fieldFilterProto(
                        'prop',
                        proto.StructuredQuery_FieldFilter_Operator.LESS_THAN,
                        proto_v1.Value(integerValue: Int64(42)),
                      ),
                      fieldFilterProto(
                        'name',
                        proto.StructuredQuery_FieldFilter_Operator.EQUAL,
                        proto_v1.Value(stringValue: 'dimond'),
                      ),
                      proto.StructuredQuery_Filter(
                        compositeFilter: proto.StructuredQuery_CompositeFilter(
                          op: proto
                              .StructuredQuery_CompositeFilter_Operator
                              .AND,
                          filters: <proto.StructuredQuery_Filter>[
                            unaryFilterProto(
                              'nan',
                              proto.StructuredQuery_UnaryFilter_Operator.IS_NAN,
                            ),
                            unaryFilterProto(
                              'null',
                              proto
                                  .StructuredQuery_UnaryFilter_Operator
                                  .IS_NULL,
                            ),
                            fieldFilterProto(
                              'tags',
                              proto
                                  .StructuredQuery_FieldFilter_Operator
                                  .ARRAY_CONTAINS,
                              proto_v1.Value(stringValue: 'pending'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                orderBy: <proto.StructuredQuery_Order>[
                  orderProto('prop', proto.StructuredQuery_Direction.ASCENDING),
                  orderProto(
                    '__name__',
                    proto.StructuredQuery_Direction.ASCENDING,
                  ),
                ],
              ),
            ),
            targetId: 1,
          );
          expect(result, expected);
          expect(s.decodeQueryTarget(s.encodeQueryTarget(q)), q);
        },
      );

      test(
        'converts multi-layer composite filters with AND at the first layer',
        () {
          final Target q = query('docs')
              .filter(
                andFilters(<Filter>[
                  filter('prop', '<', 42),
                  filter('name', '==', 'dimond'),
                  orFilters(<Filter>[
                    filter('nan', '==', double.nan),
                    filter('null', '==', null),
                    filter('tags', 'array-contains', 'pending'),
                  ]),
                ]),
              )
              .toTarget();
          final proto_v1.Target result = s.encodeTarget(wrapTargetData(q));
          final proto_v1.Target expected = proto_v1.Target(
            query: proto.Target_QueryTarget(
              parent: 'projects/p/databases/d/documents',
              structuredQuery: proto.StructuredQuery(
                from: <proto.StructuredQuery_CollectionSelector>[
                  proto.StructuredQuery_CollectionSelector(
                    collectionId: 'docs',
                  ),
                ],
                where: proto.StructuredQuery_Filter(
                  compositeFilter: proto.StructuredQuery_CompositeFilter(
                    op: proto.StructuredQuery_CompositeFilter_Operator.AND,
                    filters: <proto.StructuredQuery_Filter>[
                      fieldFilterProto(
                        'prop',
                        proto.StructuredQuery_FieldFilter_Operator.LESS_THAN,
                        proto_v1.Value(integerValue: Int64(42)),
                      ),
                      fieldFilterProto(
                        'name',
                        proto.StructuredQuery_FieldFilter_Operator.EQUAL,
                        proto_v1.Value(stringValue: 'dimond'),
                      ),
                      proto.StructuredQuery_Filter(
                        compositeFilter: proto.StructuredQuery_CompositeFilter(
                          op: proto.StructuredQuery_CompositeFilter_Operator.OR,
                          filters: <proto.StructuredQuery_Filter>[
                            unaryFilterProto(
                              'nan',
                              proto.StructuredQuery_UnaryFilter_Operator.IS_NAN,
                            ),
                            unaryFilterProto(
                              'null',
                              proto
                                  .StructuredQuery_UnaryFilter_Operator
                                  .IS_NULL,
                            ),
                            fieldFilterProto(
                              'tags',
                              proto
                                  .StructuredQuery_FieldFilter_Operator
                                  .ARRAY_CONTAINS,
                              proto_v1.Value(stringValue: 'pending'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                orderBy: <proto.StructuredQuery_Order>[
                  orderProto('prop', proto.StructuredQuery_Direction.ASCENDING),
                  orderProto(
                    '__name__',
                    proto.StructuredQuery_Direction.ASCENDING,
                  ),
                ],
              ),
            ),
            targetId: 1,
          );
          expect(result, expected);
          expect(s.decodeQueryTarget(s.encodeQueryTarget(q)), q);
        },
      );

      test('converts order bys', () {
        final Target q = query(
          'docs',
        ).orderBy(orderBy('prop', 'asc')).toTarget();
        final proto_v1.Target result = s.encodeTarget(wrapTargetData(q));
        final proto_v1.Target expected = proto_v1.Target(
          query: proto.Target_QueryTarget(
            parent: 'projects/p/databases/d/documents',
            structuredQuery: proto.StructuredQuery(
              from: <proto.StructuredQuery_CollectionSelector>[
                proto.StructuredQuery_CollectionSelector(collectionId: 'docs'),
              ],
              orderBy: <proto.StructuredQuery_Order>[
                orderProto('prop', proto.StructuredQuery_Direction.ASCENDING),
                orderProto(
                  '__name__',
                  proto.StructuredQuery_Direction.ASCENDING,
                ),
              ],
            ),
          ),
          targetId: 1,
        );
        expect(result, expected);
        expect(s.decodeQueryTarget(s.encodeQueryTarget(q)), q);
      });
    });

    group('to/from OperatorName', () {
      test('contains all Operators', () {
        // toOperatorName() / fromOperatorName() are private here; a field
        // filter round trip goes through both.
        final Map<FilterOperator, Object> allOperators =
            <FilterOperator, Object>{
              FilterOperator.lessThan: 1,
              FilterOperator.lessThanOrEqual: 1,
              FilterOperator.equal: 1,
              FilterOperator.notEqual: 1,
              FilterOperator.graterThan: 1,
              FilterOperator.graterThanOrEqual: 1,
              FilterOperator.arrayContains: 1,
              FilterOperator.IN: <Object>[1],
              FilterOperator.NOT_IN: <Object>[1],
              FilterOperator.arrayContainsAny: <Object>[1],
            };
        expect(allOperators, hasLength(10));

        for (final MapEntry<FilterOperator, Object> entry
            in allOperators.entries) {
          final FieldFilter input = FieldFilter(
            field('a'),
            entry.key,
            wrap(entry.value),
          );
          final FieldFilter roundtripped = s.decodeFieldFilter(
            s.encodeUnaryOrFieldFilter(input).fieldFilter,
          );
          expect(roundtripped.operator, entry.key);
        }
      });
    });

    group('to/from Direction', () {
      test('contains all Directions', () {
        for (final OrderByDirection dir in <OrderByDirection>[
          OrderByDirection.ascending,
          OrderByDirection.descending,
        ]) {
          final Target target = query(
            'docs',
          ).orderBy(OrderBy(dir, field('a'))).toTarget();
          final Target roundtripped = s.decodeQueryTarget(
            s.encodeQueryTarget(target),
          );
          expect(roundtripped.orderBy.first.direction, dir);
        }
      });
    });

    group('to/from PropertyOrder', () {
      // toPropertyOrder() / fromPropertyOrder() are private here; the order is
      // checked inside the structured query.
      void verifyPropertyOrder(
        OrderBy orderBy,
        proto.StructuredQuery_Order expected,
      ) {
        final Target target = query('docs').orderBy(orderBy).toTarget();
        final proto.Target_QueryTarget actual = s.encodeQueryTarget(target);
        expect(actual.structuredQuery.orderBy.first, expected);
        expect(s.decodeQueryTarget(actual).orderBy.first, orderBy);
      }

      test('renders ascending', () {
        verifyPropertyOrder(
          OrderBy(OrderByDirection.ascending, field('a.b')),
          orderProto('a.b', proto.StructuredQuery_Direction.ASCENDING),
        );
      });

      test('renders descending', () {
        verifyPropertyOrder(
          OrderBy(OrderByDirection.descending, field('a.b.c')),
          orderProto('a.b.c', proto.StructuredQuery_Direction.DESCENDING),
        );
      });
    });

    group('fromWatchChange', () {
      test('converts target change with no_change (omitted in JSON)', () {
        final WatchChangeWatchTargetChange expected =
            WatchChangeWatchTargetChange(WatchTargetChangeType.noChange, <int>[
              1,
              4,
            ]);
        final WatchChange actual = s.decodeWatchChange(
          proto.ListenResponse(
            targetChange: proto.TargetChange(targetIds: <int>[1, 4]),
          ),
        );
        expect(actual, expected);
      });

      test('converts target change with snapshot version', () {
        final WatchChangeWatchTargetChange expected =
            WatchChangeWatchTargetChange(
              WatchTargetChangeType.removed,
              <int>[1, 4],
              Uint8List.fromList('resume'.codeUnits),
              const GrpcError.cancelled('message'),
            );
        final WatchChange actual = s.decodeWatchChange(
          proto.ListenResponse(
            targetChange: proto.TargetChange(
              targetChangeType: proto.TargetChange_TargetChangeType.REMOVE,
              targetIds: <int>[1, 4],
              resumeToken: 'resume'.codeUnits,
              cause: proto.Status(code: 1, message: 'message'),
            ),
          ),
        );
        expect(actual, expected);
      });
    });
  });
}
