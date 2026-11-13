// Copyright 2021 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_metadata.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundled_document_metadata.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundled_query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/named_query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/bound.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/filter/filter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/geo_point.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';

// Port of the Android BundleSerializerTest. The Android test uses the lenient org.json syntax; the JSON objects are
// written here as Dart maps, which is what jsonDecode produces for the strict JSON of a real bundle.
void main() {
  const String testProject = 'projects/project/databases/(default)/documents';
  const String testDocument = '$testProject/coll/doc';

  final BundleSerializer serializer = BundleSerializer(
    RemoteSerializer(DatabaseId.forProject('project')),
  );

  Map<String, dynamic> field(String path) => <String, dynamic>{
    'fieldPath': path,
  };

  Map<String, dynamic> stringValue(String value) => <String, dynamic>{
    'stringValue': value,
  };

  void assertDecodesValue(Object? json, FieldValue expected) {
    final Map<String, dynamic> documentJson = <String, dynamic>{
      'name': testDocument,
      'fields': <String, dynamic>{'foo': json},
      'createTime': '2020-01-01T00:00:01.000000001Z',
      'updateTime': '2020-01-01T00:00:02.000000002Z',
    };
    final BundleDocument actualDocument = serializer.decodeDocument(
      documentJson,
    );
    final BundleDocument expectedDocument = BundleDocument(
      Document(
        key('coll/doc'),
        const SnapshotVersion(Timestamp(1577836802, 2)),
        DocumentState.synced,
        ObjectValue.empty.set(FieldPath.fromSingleSegment('foo'), expected),
      ),
    );

    expect(actualDocument, expectedDocument);
  }

  void assertDecodesNamedQuery(
    Map<String, dynamic> structuredQuery,
    Query expected, {
    BundledQueryLimitType limitType = BundledQueryLimitType.first,
  }) {
    final Map<String, dynamic> queryJson = <String, dynamic>{
      'name': 'query-1',
      'bundledQuery': <String, dynamic>{
        'parent': testProject,
        'structuredQuery': structuredQuery,
        'limitType': limitType == BundledQueryLimitType.last ? 'LAST' : 'FIRST',
      },
      'readTime': '2020-01-01T00:00:01.000000001Z',
    };
    final NamedQuery actualNamedQuery = serializer.decodeNamedQuery(queryJson);

    final NamedQuery expectedNamedQuery = NamedQuery(
      'query-1',
      BundledQuery(expected, limitType),
      const SnapshotVersion(Timestamp(1577836801, 1)),
    );

    expect(actualNamedQuery, expectedNamedQuery);
  }

  Map<String, dynamic> from(String collectionId, {bool? allDescendants}) =>
      <String, dynamic>{
        'collectionId': collectionId,
        if (allDescendants != null) 'allDescendants': allDescendants,
      };

  Map<String, dynamic> collQuery({
    Map<String, dynamic>? where,
    Map<String, dynamic>? extra,
  }) => <String, dynamic>{
    'from': <Object?>[from('coll')],
    if (where != null) 'where': where,
    ...?extra,
  };

  Map<String, dynamic> unaryFilter(String op, String fieldPath) =>
      <String, dynamic>{
        'unaryFilter': <String, dynamic>{'op': op, 'field': field(fieldPath)},
      };

  Map<String, dynamic> fieldFilter(
    String op,
    String fieldPath,
    Map<String, dynamic> value,
  ) => <String, dynamic>{
    'fieldFilter': <String, dynamic>{
      'op': op,
      'field': field(fieldPath),
      'value': value,
    },
  };

  group('value decoding', () {
    test('testDecodesNullValue', () {
      assertDecodesValue(<String, dynamic>{
        'nullValue': null,
      }, NullValue.nullValue());
    });

    test('testDecodesBooleanValue', () {
      for (final bool test in <bool>[true, false]) {
        assertDecodesValue(<String, dynamic>{
          'booleanValue': test,
        }, BoolValue.valueOf(test));
      }
    });

    const List<int> integers = <int>[
      -9223372036854775808,
      -100,
      -1,
      0,
      1,
      100,
      9223372036854775807,
    ];

    test('testDecodesIntegerValues', () {
      for (final int test in integers) {
        assertDecodesValue(<String, dynamic>{
          'integerValue': test,
        }, IntegerValue.valueOf(test));
      }
    });

    test('testDecodesStringEncodedIntegerValues', () {
      for (final int test in integers) {
        assertDecodesValue(<String, dynamic>{
          'integerValue': '$test',
        }, IntegerValue.valueOf(test));
      }
    });

    test('testDecodesDoubleValues', () {
      const List<double> tests = <double>[
        -double.maxFinite,
        -9223372036854775807.0 - 1.0,
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
        9223372036854775807.0,
        double.maxFinite,
      ];
      for (final double test in tests) {
        assertDecodesValue(<String, dynamic>{
          'doubleValue': test,
        }, DoubleValue.valueOf(test));
      }
    });

    test('testDecodesStringEncodedDoubleValues', () {
      const List<double> tests = <double>[
        double.nan,
        double.negativeInfinity,
        double.infinity,
      ];
      for (final double test in tests) {
        assertDecodesValue(<String, dynamic>{
          'doubleValue': '$test',
        }, DoubleValue.valueOf(test));
      }
    });

    test('testDecodesStringValues', () {
      const List<String> tests = <String>[
        '',
        'a',
        'abc def',
        'æ',
        '\u0000퟿￿',
        '(╯°□°）╯︵ ┻━┻',
      ];
      for (final String test in tests) {
        assertDecodesValue(stringValue(test), StringValue.valueOf(test));
      }
    });

    test('testDecodesDateValues', () {
      final List<Object?> json = <Object?>[
        '1970-01-01T00:00:00.000Z',
        <String, dynamic>{},
        '1970-01-01T00:00:00.001Z',
        <String, dynamic>{'nanos': 1000000},
        '2020-01-01T01:00:00.000Z',
        <String, dynamic>{'seconds': 1577840400},
        '2020-01-01T01:00:00.001Z',
        <String, dynamic>{'seconds': 1577840400, 'nanos': 1000000},
        '2020-01-01T01:02:00.001002Z',
        <String, dynamic>{'seconds': '1577840520', 'nanos': 1002000},
        '2020-01-01T01:02:03.001002003Z',
        <String, dynamic>{'seconds': 1577840523, 'nanos': 1002003},
      ];

      const List<Timestamp> timestamps = <Timestamp>[
        Timestamp(0, 0),
        Timestamp(0, 0),
        Timestamp(0, 1000000),
        Timestamp(0, 1000000),
        Timestamp(1577840400, 0),
        Timestamp(1577840400, 0),
        Timestamp(1577840400, 1000000),
        Timestamp(1577840400, 1000000),
        Timestamp(1577840520, 1002000),
        Timestamp(1577840520, 1002000),
        Timestamp(1577840523, 1002003),
        Timestamp(1577840523, 1002003),
      ];

      for (int i = 0; i < json.length; i++) {
        assertDecodesValue(<String, dynamic>{
          'timestampValue': json[i],
        }, TimestampValue.valueOf(timestamps[i]));
      }
    });

    test('testDecodesTimestampsWithTimezoneOffsets', () {
      // Not part of the Android tests: the offset is subtracted for '+' and added for '-'.
      assertDecodesValue(<String, dynamic>{
        'timestampValue': '2020-01-01T01:00:00+01:00',
      }, TimestampValue.valueOf(const Timestamp(1577836800, 0)));
      assertDecodesValue(<String, dynamic>{
        'timestampValue': '2019-12-31T19:00:00.5-05:00',
      }, TimestampValue.valueOf(const Timestamp(1577836800, 500000000)));
    });

    test('testDecodesTimestampsOutsideOfTheEpochCentury', () {
      // Not part of the Android tests: proleptic Gregorian calendar, first and last year.
      assertDecodesValue(<String, dynamic>{
        'timestampValue': '0001-01-01T00:00:00Z',
      }, TimestampValue.valueOf(const Timestamp(-62135596800, 0)));
      assertDecodesValue(<String, dynamic>{
        'timestampValue': '9999-12-31T23:59:59.999999999Z',
      }, TimestampValue.valueOf(const Timestamp(253402300799, 999999999)));
      assertDecodesValue(<String, dynamic>{
        'timestampValue': '1969-12-31T23:59:59Z',
      }, TimestampValue.valueOf(const Timestamp(-1, 0)));
    });

    test('testRejectsInvalidTimestamps', () {
      for (final Object? invalid in <Object?>[
        'yesterday',
        '2020-01-01T00:00:00',
        5,
      ]) {
        expect(
          () => serializer.decodeDocument(<String, dynamic>{
            'name': testDocument,
            'fields': <String, dynamic>{
              'foo': <String, dynamic>{'timestampValue': invalid},
            },
            'updateTime': '2020-01-01T00:00:02.000000002Z',
          }),
          throwsA(isA<ArgumentError>()),
          reason: '$invalid',
        );
      }
    });

    test('testDecodesGeoPointValues', () {
      assertDecodesValue(<String, dynamic>{
        'geoPointValue': <String, dynamic>{'latitude': 1.23, 'longitude': 4.56},
      }, GeoPointValue.valueOf(const GeoPoint(1.23, 4.56)));
    });

    test('testDecodesBlobValues', () {
      assertDecodesValue(<String, dynamic>{
        'bytesValue': 'AAECAw==',
      }, BlobValue.valueOf(blob(<int>[0, 1, 2, 3])));
    });

    test('testDecodesReferenceValues', () {
      assertDecodesValue(
        <String, dynamic>{'referenceValue': testDocument},
        ReferenceValue.valueOf(
          DatabaseId.forProject('project'),
          key('coll/doc'),
        ),
      );
    });

    test('testDecodesArrayValues', () {
      assertDecodesValue(
        <String, dynamic>{
          'arrayValue': <String, dynamic>{
            'values': <Object?>[
              <String, dynamic>{'booleanValue': true},
              stringValue('foo'),
            ],
          },
        },
        ArrayValue.fromList(<FieldValue>[
          BoolValue.valueOf(true),
          StringValue.valueOf('foo'),
        ]),
      );
    });

    test('testDecodesNestedObjectValues', () {
      final Map<String, dynamic> json = <String, dynamic>{
        'mapValue': <String, dynamic>{
          'fields': <String, dynamic>{
            'b': <String, dynamic>{'booleanValue': true},
            'd': <String, dynamic>{'doubleValue': double.maxFinite},
            'i': <String, dynamic>{'integerValue': 1},
            'n': <String, dynamic>{'nullValue': null},
            's': stringValue('foo'),
            'a': <String, dynamic>{
              'arrayValue': <String, dynamic>{
                'values': <Object?>[
                  <String, dynamic>{'integerValue': 2},
                  stringValue('bar'),
                  <String, dynamic>{
                    'mapValue': <String, dynamic>{
                      'fields': <String, dynamic>{
                        'b': <String, dynamic>{'booleanValue': false},
                      },
                    },
                  },
                ],
              },
            },
            'o': <String, dynamic>{
              'mapValue': <String, dynamic>{
                'fields': <String, dynamic>{
                  'd': <String, dynamic>{'integerValue': 100},
                  'nested': <String, dynamic>{
                    'mapValue': <String, dynamic>{
                      'fields': <String, dynamic>{
                        'e': <String, dynamic>{
                          'integerValue': -9223372036854775808,
                        },
                      },
                    },
                  },
                },
              },
            },
          },
        },
      };

      final ObjectValue expected = wrapMap(<String, Object?>{
        'b': true,
        'd': double.maxFinite,
        'i': 1,
        'n': null,
        's': 'foo',
        'a': <Object?>[
          2,
          'bar',
          <String, Object?>{'b': false},
        ],
        'o': <String, Object?>{
          'd': 100,
          'nested': <String, Object?>{'e': -9223372036854775808},
        },
      });
      assertDecodesValue(json, expected);
    });

    test('testDecodesDocumentsWithoutFields', () {
      final BundleDocument document = serializer.decodeDocument(
        <String, dynamic>{
          'name': testDocument,
          'updateTime': '2020-01-01T00:00:02.000000002Z',
        },
      );
      expect(document.document.data, ObjectValue.empty);
    });

    test('testRejectsDocumentsOfOtherDatabases', () {
      expect(
        () => serializer.decodeDocument(<String, dynamic>{
          'name': 'projects/other/databases/(default)/documents/coll/doc',
          'updateTime': '2020-01-01T00:00:02.000000002Z',
        }),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('testRejectsUnknownValueTypes', () {
      expect(
        () => serializer.decodeDocument(<String, dynamic>{
          'name': testDocument,
          'fields': <String, dynamic>{
            'foo': <String, dynamic>{'mystery': 1},
          },
          'updateTime': '2020-01-01T00:00:02.000000002Z',
        }),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('query decoding', () {
    test('testDecodesCollectionQuery', () {
      assertDecodesNamedQuery(collQuery(), query('coll'));
    });

    test('testDecodesCollectionGroupQuery', () {
      assertDecodesNamedQuery(<String, dynamic>{
        'from': <Object?>[from('coll', allDescendants: true)],
      }, Query(ResourcePath.empty, collectionGroup: 'coll'));
    });

    test('testDecodesNullFilter', () {
      assertDecodesNamedQuery(
        collQuery(where: unaryFilter('IS_NULL', 'f1')),
        query('coll').filter(filter('f1', '==', null)),
      );
    });

    test('testDecodesNotNullFilter', () {
      assertDecodesNamedQuery(
        collQuery(where: unaryFilter('IS_NOT_NULL', 'f1')),
        query('coll').filter(filter('f1', '!=', null)),
      );
    });

    test('testDecodesNaNFilter', () {
      assertDecodesNamedQuery(
        collQuery(where: unaryFilter('IS_NAN', 'f1')),
        query('coll').filter(filter('f1', '==', double.nan)),
      );
    });

    test('testDecodesNotNaNFilter', () {
      assertDecodesNamedQuery(
        collQuery(where: unaryFilter('IS_NOT_NAN', 'f1')),
        query('coll').filter(filter('f1', '!=', double.nan)),
      );
    });

    final Map<String, String> operators = <String, String>{
      'LESS_THAN': '<',
      'LESS_THAN_OR_EQUAL': '<=',
      'GREATER_THAN': '>',
      'GREATER_THAN_OR_EQUAL': '>=',
      'EQUAL': '==',
      'NOT_EQUAL': '!=',
      'ARRAY_CONTAINS': 'array-contains',
    };
    operators.forEach((String op, String dartOp) {
      test('testDecodes${op}Filter', () {
        assertDecodesNamedQuery(
          collQuery(where: fieldFilter(op, 'f1', stringValue('foo'))),
          query('coll').filter(filter('f1', dartOp, 'foo')),
        );
      });
    });

    final Map<String, String> arrayOperators = <String, String>{
      'IN': 'in',
      'ARRAY_CONTAINS_ANY': 'array-contains-any',
      'NOT_IN': 'not-in',
    };
    arrayOperators.forEach((String op, String dartOp) {
      test('testDecodes${op}Filter', () {
        assertDecodesNamedQuery(
          collQuery(
            where: fieldFilter(op, 'f1', <String, dynamic>{
              'arrayValue': <String, dynamic>{
                'values': <Object?>[stringValue('foo')],
              },
            }),
          ),
          query('coll').filter(filter('f1', dartOp, <Object?>['foo'])),
        );
      });
    });

    test('testDecodesCompositeFilter', () {
      assertDecodesNamedQuery(
        collQuery(
          where: <String, dynamic>{
            'compositeFilter': <String, dynamic>{
              'op': 'AND',
              'filters': <Object?>[
                fieldFilter('EQUAL', 'f1', stringValue('foo')),
                fieldFilter('EQUAL', 'f2', stringValue('bar')),
              ],
            },
          },
        ),
        query(
          'coll',
        ).filter(filter('f1', '==', 'foo')).filter(filter('f2', '==', 'bar')),
      );
    });

    // PORTING NOTE: the Android SDK rejects 'OR' composite filters. The port reads them (as the JS SDK does) so that
    // the bundle of `QuerySnapshot.toJson()` for an OR query can be read back; unknown operators are still rejected.
    test('testDecodesOrCompositeFilters', () {
      assertDecodesNamedQuery(
        collQuery(
          where: <String, dynamic>{
            'compositeFilter': <String, dynamic>{
              'op': 'OR',
              'filters': <Object?>[
                fieldFilter('EQUAL', 'f1', stringValue('foo')),
                <String, dynamic>{
                  'compositeFilter': <String, dynamic>{
                    'op': 'AND',
                    'filters': <Object?>[
                      fieldFilter('EQUAL', 'f2', stringValue('bar')),
                      fieldFilter('EQUAL', 'f3', stringValue('baz')),
                    ],
                  },
                },
              ],
            },
          },
        ),
        query('coll').filter(
          CompositeFilter.or(<Filter>[
            filter('f1', '==', 'foo'),
            CompositeFilter.and(<Filter>[
              filter('f2', '==', 'bar'),
              filter('f3', '==', 'baz'),
            ]),
          ]),
        ),
      );
    });

    test('testRejectsUnknownCompositeFilters', () {
      expect(
        () => assertDecodesNamedQuery(
          collQuery(
            where: <String, dynamic>{
              'compositeFilter': <String, dynamic>{
                'op': 'OPERATOR_UNSPECIFIED',
                'filters': <Object?>[
                  fieldFilter('EQUAL', 'f1', stringValue('foo')),
                ],
              },
            },
          ),
          query('coll'),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('testDecodeOrderByQuery', () {
      assertDecodesNamedQuery(
        collQuery(
          extra: <String, dynamic>{
            'orderBy': <Object?>[
              <String, dynamic>{'field': field('f1')},
              <String, dynamic>{'field': field('f2'), 'direction': 'ASCENDING'},
              <String, dynamic>{
                'field': field('f3'),
                'direction': 'DESCENDING',
              },
            ],
          },
        ),
        query('coll')
            .orderBy(orderBy('f1'))
            .orderBy(orderBy('f2', 'asc'))
            .orderBy(orderBy('f3', 'desc')),
      );
    });

    test('testDecodesLimitQuery', () {
      for (final Object limit in <Object>[
        <String, dynamic>{'value': 5}, // ProtobufJS
        5, // Proto3 JSON
        '5', // Proto3 JSON, string encoded
      ]) {
        assertDecodesNamedQuery(
          collQuery(extra: <String, dynamic>{'limit': limit}),
          query('coll').limit(5),
        );
      }
    });

    test('testDecodesLimitToLastQuery', () {
      // PORTING NOTE: core Query has no limitToLast yet: the query is the one the backend sees (limit to first) and
      // the limit type is kept next to it.
      assertDecodesNamedQuery(
        collQuery(
          extra: <String, dynamic>{
            'limit': <String, dynamic>{'value': 5},
          },
        ),
        query('coll').limit(5),
        limitType: BundledQueryLimitType.last,
      );
    });

    test('testDecodesStartAtQuery', () {
      assertDecodesNamedQuery(
        collQuery(
          extra: <String, dynamic>{
            'orderBy': <Object?>[
              <String, dynamic>{'field': field('foo')},
            ],
            'startAt': <String, dynamic>{
              'values': <Object?>[stringValue('bar')],
              'before': false,
            },
          },
        ),
        query('coll')
            .orderBy(orderBy('foo'))
            .startAt(
              Bound(
                position: <FieldValue>[StringValue.valueOf('bar')],
                inclusive: false,
              ),
            ),
      );
    });

    test('testDecodesEndBeforeQuery', () {
      assertDecodesNamedQuery(
        collQuery(
          extra: <String, dynamic>{
            'orderBy': <Object?>[
              <String, dynamic>{'field': field('foo')},
            ],
            'endAt': <String, dynamic>{
              'values': <Object?>[stringValue('bar')],
              'before': true,
            },
          },
        ),
        query('coll')
            .orderBy(orderBy('foo'))
            .endAt(
              Bound(
                position: <FieldValue>[StringValue.valueOf('bar')],
                inclusive: false,
              ),
            ),
      );
    });

    test('testDoesNotDecodeOffset', () {
      expect(
        () => assertDecodesNamedQuery(
          collQuery(extra: <String, dynamic>{'offset': 5}),
          query('coll'),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('testDoesNotDecodeSelect', () {
      expect(
        () => assertDecodesNamedQuery(
          collQuery(extra: <String, dynamic>{'select': <Object?>[]}),
          query('coll'),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('testDoesNotDecodeMissingCollection', () {
      expect(
        () => assertDecodesNamedQuery(<String, dynamic>{
          'from': <Object?>[],
        }, query('coll')),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('testDoesNotDecodeMultipleCollections', () {
      expect(
        () => assertDecodesNamedQuery(<String, dynamic>{
          'from': <Object?>[from('c1'), from('c2')],
        }, query('coll')),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('testDoesNotDecodeUnknownLimitTypes', () {
      expect(
        () => serializer.decodeNamedQuery(<String, dynamic>{
          'name': 'query-1',
          'bundledQuery': <String, dynamic>{
            'parent': testProject,
            'structuredQuery': collQuery(),
            'limitType': 'MIDDLE',
          },
          'readTime': '2020-01-01T00:00:01.000000001Z',
        }),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('target decoding', () {
    Map<String, dynamic> namedQueryWithLimit(String limitType) =>
        <String, dynamic>{
          'name': 'myNamedQuery',
          'bundledQuery': <String, dynamic>{
            'parent': testProject,
            'structuredQuery': <String, dynamic>{
              'from': <Object?>[from('foo')],
              'limit': <String, dynamic>{'value': 10},
            },
            'limitType': limitType,
          },
          'readTime': <String, dynamic>{
            'seconds': '1679674432',
            'nanos': 579934000,
          },
        };

    test('testDecodesTargetWithoutImplicitOrderByOnName', () {
      final NamedQuery namedQuery = serializer.decodeNamedQuery(
        namedQueryWithLimit('FIRST'),
      );
      expect(
        namedQuery.bundledQuery.query.toTarget(),
        query('foo').limitToFirst(10).toTarget(),
      );
      expect(namedQuery.bundledQuery.limitType, BundledQueryLimitType.first);
    });

    test('testDecodesLimitToLastTargetWithoutImplicitOrderByOnName', () {
      final NamedQuery namedQuery = serializer.decodeNamedQuery(
        namedQueryWithLimit('LAST'),
      );
      expect(
        namedQuery.bundledQuery.query.toTarget(),
        // Note that `limitToFirst(10)` is expected.
        query('foo').limitToFirst(10).toTarget(),
      );
      expect(namedQuery.bundledQuery.limitType, BundledQueryLimitType.last);
    });
  });

  group('metadata decoding', () {
    test('testDecodesBundleMetadata', () {
      final Map<String, dynamic> json = <String, dynamic>{
        'id': 'bundle-1',
        'version': 1,
        'createTime': <String, dynamic>{'seconds': 2, 'nanos': 3},
        'totalDocuments': 4,
        'totalBytes': 5,
      };
      const BundleMetadata expectedMetadata = BundleMetadata(
        'bundle-1',
        1,
        SnapshotVersion(Timestamp(2, 3)),
        4,
        5,
      );
      expect(serializer.decodeBundleMetadata(json), expectedMetadata);
    });

    test('testDecodesProto3JsonBundleMetadata', () {
      // 64 bit integers are strings in proto3 JSON, the create time is an RFC 3339 string.
      final Map<String, dynamic> json = <String, dynamic>{
        'id': 'bundle-1',
        'version': 1,
        'createTime': '1970-01-01T00:00:02.000000003Z',
        'totalDocuments': 4,
        'totalBytes': '5',
      };
      const BundleMetadata expectedMetadata = BundleMetadata(
        'bundle-1',
        1,
        SnapshotVersion(Timestamp(2, 3)),
        4,
        5,
      );
      expect(serializer.decodeBundleMetadata(json), expectedMetadata);
    });

    test('testDecodesBundledDocumentMetadata', () {
      final Map<String, dynamic> json = <String, dynamic>{
        'name': testDocument,
        'readTime': '2020-01-01T00:00:01.000000001Z',
        'exists': true,
        'queries': <Object?>['query-1', 'query-2'],
      };
      final BundledDocumentMetadata expectedMetadata = BundledDocumentMetadata(
        key('coll/doc'),
        const SnapshotVersion(Timestamp(1577836801, 1)),
        true,
        const <String>['query-1', 'query-2'],
      );
      expect(serializer.decodeBundledDocumentMetadata(json), expectedMetadata);
    });

    test('testDecodesBundledDocumentMetadataWithoutQueriesOrExists', () {
      final BundledDocumentMetadata metadata = serializer
          .decodeBundledDocumentMetadata(<String, dynamic>{
            'name': testDocument,
            'readTime': '2020-01-01T00:00:01.000000001Z',
          });
      expect(metadata.exists, isFalse);
      expect(metadata.queries, isEmpty);
    });
  });

  group('decodeValue', () {
    test('decodesScalarAndNestedValues', () {
      expect(serializer.decodeValue(stringValue('a')), wrap('a'));
      expect(
        serializer.decodeValue(<String, dynamic>{'integerValue': '42'}),
        wrap(42),
      );
      expect(
        serializer.decodeValue(<String, dynamic>{
          'arrayValue': <String, dynamic>{
            'values': <dynamic>[stringValue('x')],
          },
        }),
        wrap(<dynamic>['x']),
      );
    });
  });
}
