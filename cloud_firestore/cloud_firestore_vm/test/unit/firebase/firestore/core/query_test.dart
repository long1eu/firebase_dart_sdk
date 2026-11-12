// File created by
// Lung Razvan <long1eu>
// on 27/09/2018

import 'package:cloud_firestore_vm/src/firebase/firestore/core/bound.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/filter/filter.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/order_by.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/target.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/value/field_value.dart';
import 'package:test/test.dart';

import '../../../../util/comparator_test.dart';
import '../../../../util/test_util.dart';

void main() {
  test('testMatchesBasedDocumentKey', () {
    final ResourcePath queryPath =
        ResourcePath.fromString('rooms/eros/messages/1');
    final Document doc1 =
        doc('rooms/eros/messages/1', 0, map(<String>['text', 'msg1']));
    final Document doc2 =
        doc('rooms/eros/messages/2', 0, map(<String>['text', 'msg2']));
    final Document doc3 =
        doc('rooms/other/messages/1', 0, map(<String>['text', 'msg3']));

    final Query query = Query(queryPath);
    expect(query.matches(doc1), isTrue);
    expect(query.matches(doc2), isFalse);
    expect(query.matches(doc3), isFalse);
  });

  test('testMatchesShallowAncestorQuery', () {
    final ResourcePath queryPath =
        ResourcePath.fromString('rooms/eros/messages');
    final Document doc1 =
        doc('rooms/eros/messages/1', 0, map(<String>['text', 'msg1']));
    final Document doc1meta = doc('rooms/eros/messages/1/meta/1', 0,
        map(<dynamic>['meta', 'meta-value']));
    final Document doc2 =
        doc('rooms/eros/messages/2', 0, map(<String>['text', 'msg2']));
    final Document doc3 =
        doc('rooms/other/messages/1', 0, map(<String>['text', 'msg3']));

    final Query query = Query(queryPath);
    expect(query.matches(doc1), isTrue);
    expect(query.matches(doc1meta), isFalse);
    expect(query.matches(doc2), isTrue);
    expect(query.matches(doc3), isFalse);
  });

  test('testEmptyFieldsAreAllowedForQueries', () {
    final ResourcePath queryPath =
        ResourcePath.fromString('rooms/eros/messages');
    final Document doc1 =
        doc('rooms/eros/messages/1', 0, map(<String>['text', 'msg1']));
    final Document doc2 = doc('rooms/eros/messages/2', 0, map(<String>[]));

    final Query query = Query(queryPath).filter(filter('text', '==', 'msg1'));
    expect(query.matches(doc1), isTrue);
    expect(query.matches(doc2), isFalse);
  });

  test('testPrimitiveValueFilter', () {
    final Query query1 = Query(ResourcePath.fromString('collection'))
        .filter(filter('sort', '>=', 2));
    final Query query2 = Query(ResourcePath.fromString('collection'))
        .filter(filter('sort', '<=', 2));

    final Document doc1 = doc('collection/1', 0, map(<dynamic>['sort', 1]));
    final Document doc2 = doc('collection/2', 0, map(<dynamic>['sort', 2]));
    final Document doc3 = doc('collection/3', 0, map(<dynamic>['sort', 3]));
    final Document doc4 = doc('collection/4', 0, map(<dynamic>['sort', false]));
    final Document doc5 =
        doc('collection/5', 0, map(<dynamic>['sort', 'string']));

    expect(query1.matches(doc1), isFalse);
    expect(query1.matches(doc2), isTrue);
    expect(query1.matches(doc3), isTrue);
    expect(query1.matches(doc4), isFalse);
    expect(query1.matches(doc5), isFalse);

    expect(query2.matches(doc1), isTrue);
    expect(query2.matches(doc2), isTrue);
    expect(query2.matches(doc3), isFalse);
    expect(query2.matches(doc4), isFalse);
    expect(query2.matches(doc5), isFalse);
  });

  test('testArrayContainsFilters', () {
    final Query query = Query(ResourcePath.fromString('collection'))
        .filter(filter('array', 'array-contains', 42));

    // not an array
    Document document = doc('collection/1', 0, map(<dynamic>['array', 1]));
    expect(query.matches(document), isFalse);

    // empty array
    document = doc('collection/1', 0, map(<dynamic>['array', <dynamic>[]]));
    expect(query.matches(document), isFalse);

    // array without element (and make sure it doesn't match in a nested field
    // or a different field)
    document = doc(
        'collection/1',
        0,
        map(<dynamic>[
          'array',
          <dynamic>[
            41,
            '42',
            map<dynamic>(<dynamic>[
              'a',
              42,
              'b',
              <int>[42]
            ])
          ],
          'different',
          42
        ]));
    expect(query.matches(document), isFalse);

    // array with element
    document = doc(
        'collection/1',
        0,
        map(<dynamic>[
          'array',
          <dynamic>[
            1,
            '2',
            42,
            map<dynamic>(<dynamic>['a', 1])
          ]
        ]));
    expect(query.matches(document), isTrue);
  });

  test('testArrayContainsFiltersWithObjectValues', () {
    // Search for arrays containing the object { a: [42] }
    final Query query =
        Query(ResourcePath.fromString('collection')).filter(filter(
            'array',
            'array-contains',
            map<dynamic>(<dynamic>[
              'a',
              <int>[42]
            ])));

    // array without element
    Document document = doc(
        'collection/1',
        0,
        map(<dynamic>[
          'array',
          <dynamic>[
            map<dynamic>(<dynamic>['a', 42]),
            map<dynamic>(<dynamic>[
              'a',
              <int>[42, 43]
            ]),
            map<dynamic>(<dynamic>[
              'b',
              <int>[42]
            ]),
            map<dynamic>(<dynamic>[
              'a',
              <int>[42],
              'b',
              42
            ])
          ]
        ]));
    expect(query.matches(document), isFalse);

    // array with element
    document = doc(
        'collection/1',
        0,
        map(<dynamic>[
          'array',
          <dynamic>[
            1,
            '2',
            42,
            map<dynamic>(<dynamic>[
              'a',
              <int>[42]
            ])
          ]
        ]));

    expect(query.matches(document), isTrue);
  });

  test('testInFilters', () {
    final Query query = Query(ResourcePath.fromString('collection'))
        .filter(filter('zip', 'in', <dynamic>[12345]));

    Document document = doc('collection/1', 0, map(<dynamic>['zip', 12345]));
    expect(query.matches(document), isTrue);

    // Value matches in array.
    document = doc(
        'collection/1',
        0,
        map(<dynamic>[
          'zip',
          <dynamic>[12345]
        ]));
    expect(query.matches(document), isFalse);

    // Non-type match.
    document = doc('collection/1', 0, map(<dynamic>['zip', '12345']));
    expect(query.matches(document), isFalse);

    // Nested match.
    document = doc(
        'collection/1',
        0,
        map(<dynamic>[
          'zip',
          <dynamic>[
            '12345',
            map<dynamic>(<dynamic>['zip', 12345])
          ]
        ]));
    expect(query.matches(document), isFalse);
  });

  test('testInFiltersWithObjectValues', () {
    final Query query = Query(ResourcePath.fromString('collection'))
        .filter(filter('zip', 'in', <dynamic>[
      map<dynamic>(<dynamic>[
        'a',
        <dynamic>[42]
      ])
    ]));

    // Containing object in array.
    Document document = doc(
        'collection/1',
        0,
        map(<dynamic>[
          'zip',
          <dynamic>[
            map<dynamic>(<dynamic>[
              'a',
              <dynamic>[42]
            ])
          ]
        ]));
    expect(query.matches(document), isFalse);

    // Containing object.
    document = doc(
        'collection/1',
        0,
        map(<dynamic>[
          'zip',
          map<dynamic>(<dynamic>[
            'a',
            <dynamic>[42]
          ])
        ]));
    expect(query.matches(document), isTrue);
  });

  test('testArrayContainsAnyFilters', () {
    final Query query = Query(ResourcePath.fromString('collection'))
        .filter(filter('zip', 'array-contains-any', <dynamic>[12345]));

    Document document = doc(
        'collection/1',
        0,
        map(<dynamic>[
          'zip',
          <dynamic>[12345]
        ]));
    expect(query.matches(document), isTrue);

    // Value matches in non-array.
    document = doc('collection/1', 0, map(<dynamic>['zip', 12345]));
    expect(query.matches(document), isFalse);

    // Non-type match.
    document = doc(
        'collection/1',
        0,
        map(<dynamic>[
          'zip',
          <dynamic>['12345']
        ]));
    expect(query.matches(document), isFalse);

    // Nested match.
    document = doc(
        'collection/1',
        0,
        map(<dynamic>[
          'zip',
          <dynamic>[
            '12345',
            map<dynamic>(<dynamic>[
              'zip',
              <dynamic>[12345]
            ])
          ]
        ]));
    expect(query.matches(document), isFalse);
  });

  test('testArrayContainsAnyFiltersWithObjectValues', () {
    final Query query = Query(ResourcePath.fromString('collection'))
        .filter(filter('zip', 'array-contains-any', <dynamic>[
      map<dynamic>(<dynamic>[
        'a',
        <dynamic>[42]
      ])
    ]));

    // Containing object in array.
    Document document = doc(
        'collection/1',
        0,
        map(<dynamic>[
          'zip',
          <dynamic>[
            map<dynamic>(<dynamic>[
              'a',
              <dynamic>[42]
            ])
          ]
        ]));
    expect(query.matches(document), isTrue);

    // Containing object.
    document = doc(
        'collection/1',
        0,
        map(<dynamic>[
          'zip',
          map<dynamic>(<dynamic>[
            'a',
            <dynamic>[42]
          ])
        ]));
    expect(query.matches(document), isFalse);
  });

  test('testNotEqualFilters', () {
    final Query query = Query(ResourcePath.fromString('collection'))
        .filter(filter('zip', '!=', 12345));

    // No match.
    expect(query.matches(doc('collection/1', 0, map(<dynamic>['zip', 23456]))),
        isTrue);
    // Different types always match.
    expect(
        query.matches(doc('collection/1', 0, map(<dynamic>['zip', '12345']))),
        isTrue);
    expect(
        query.matches(doc(
            'collection/1',
            0,
            map(<dynamic>[
              'zip',
              <dynamic>[12345]
            ]))),
        isTrue);
    // Null is excluded.
    expect(query.matches(doc('collection/1', 0, map(<dynamic>['zip', null]))),
        isFalse);
    // Missing field is excluded.
    expect(query.matches(doc('collection/1', 0, map(<dynamic>['chip', 23456]))),
        isFalse);
    // NaN matches.
    expect(
        query
            .matches(doc('collection/1', 0, map(<dynamic>['zip', double.nan]))),
        isTrue);
    // Direct match.
    expect(query.matches(doc('collection/1', 0, map(<dynamic>['zip', 12345]))),
        isFalse);
    // An equal double does not match either.
    expect(
        query.matches(doc('collection/1', 0, map(<dynamic>['zip', 12345.0]))),
        isFalse);
  });

  test('testNotInFilters', () {
    final Query query = Query(ResourcePath.fromString('collection'))
        .filter(filter('zip', 'not-in', <dynamic>[12345]));

    // No match.
    expect(query.matches(doc('collection/1', 0, map(<dynamic>['zip', 23456]))),
        isTrue);
    // Value matches in array.
    expect(
        query.matches(doc(
            'collection/1',
            0,
            map(<dynamic>[
              'zip',
              <dynamic>[12345]
            ]))),
        isTrue);
    // Non-type match.
    expect(
        query.matches(doc('collection/1', 0, map(<dynamic>['zip', '12345']))),
        isTrue);
    // Nested match.
    expect(
        query.matches(doc(
            'collection/1',
            0,
            map(<dynamic>[
              'zip',
              <dynamic>[
                '12345',
                map<dynamic>(<dynamic>['zip', 12345])
              ]
            ]))),
        isTrue);
    // Null is excluded.
    expect(query.matches(doc('collection/1', 0, map(<dynamic>['zip', null]))),
        isFalse);
    // NaN matches.
    expect(
        query
            .matches(doc('collection/1', 0, map(<dynamic>['zip', double.nan]))),
        isTrue);
    // Direct match.
    expect(query.matches(doc('collection/1', 0, map(<dynamic>['zip', 12345]))),
        isFalse);
    // Missing field is excluded.
    expect(query.matches(doc('collection/1', 0, map(<dynamic>['chip', 23456]))),
        isFalse);
  });

  test('testNotInFiltersWithNullInArrayMatchNothing', () {
    final Query query = Query(ResourcePath.fromString('collection'))
        .filter(filter('zip', 'not-in', <dynamic>[12345, null]));
    expect(query.matches(doc('collection/1', 0, map(<dynamic>['zip', 23456]))),
        isFalse);
  });

  test('testNotInFiltersWithObjectValues', () {
    final Query query = Query(ResourcePath.fromString('collection'))
        .filter(filter('zip', 'not-in', <dynamic>[
      map<dynamic>(<dynamic>[
        'a',
        <dynamic>[42]
      ])
    ]));

    // Containing object in array.
    expect(
        query.matches(doc(
            'collection/1',
            0,
            map(<dynamic>[
              'zip',
              <dynamic>[
                map<dynamic>(<dynamic>[
                  'a',
                  <dynamic>[42]
                ])
              ]
            ]))),
        isTrue);
    // Containing object.
    expect(
        query.matches(doc(
            'collection/1',
            0,
            map(<dynamic>[
              'zip',
              map<dynamic>(<dynamic>[
                'a',
                <dynamic>[42]
              ])
            ]))),
        isFalse);
  });

  test('testNotInFiltersWithArrayValues', () {
    final Query query = Query(ResourcePath.fromString('collection'))
        .filter(filter('zip', 'not-in', <dynamic>[
      <dynamic>[12345, 12346]
    ]));
    expect(
        query.matches(doc(
            'collection/1',
            0,
            map(<dynamic>[
              'zip',
              <dynamic>[12345, 12346]
            ]))),
        isFalse);
    expect(query.matches(doc('collection/1', 0, map(<dynamic>['zip', 12345]))),
        isTrue);
  });

  test('testKeyFieldNotEqualAndNotInFilters', () {
    final Query notEqual = Query(ResourcePath.fromString('collection'))
        .filter(filter('__name__', '!=', ref('collection/a')));
    expect(notEqual.matches(doc('collection/a', 0, map(<dynamic>[]))), isFalse);
    expect(notEqual.matches(doc('collection/b', 0, map(<dynamic>[]))), isTrue);

    final Query notIn = Query(ResourcePath.fromString('collection')).filter(
        filter('__name__', 'not-in',
            <dynamic>[ref('collection/a'), ref('collection/b')]));
    expect(notIn.matches(doc('collection/a', 0, map(<dynamic>[]))), isFalse);
    expect(notIn.matches(doc('collection/b', 0, map(<dynamic>[]))), isFalse);
    expect(notIn.matches(doc('collection/c', 0, map(<dynamic>[]))), isTrue);
  });

  test('testNotEqualAndNotInAreInequalities', () {
    final Query query = Query(ResourcePath.fromString('collection'))
        .filter(filter('a', '!=', 1));
    expect(query.firstInequalityField, field('a'));
    expect(query.orderByConstraints[0].field, field('a'));

    final Query notIn = Query(ResourcePath.fromString('collection'))
        .filter(filter('a', 'not-in', <dynamic>[1]));
    expect(notIn.firstInequalityField, field('a'));
    expect(notIn.orderByConstraints[0].field, field('a'));
  });

  test('testNotEqualAndNotInCanonicalIds', () {
    final Query base = Query(ResourcePath.fromString('collection'));
    expect(base.filter(filter('a', '!=', 1)).canonicalId, contains('a != 1'));
    expect(base.filter(filter('a', 'not-in', <dynamic>[1, 2])).canonicalId,
        contains('a not_in [1, 2]'));
    expect(base.filter(filter('a', '!=', 1)).canonicalId,
        isNot(base.filter(filter('a', '==', 1)).canonicalId));
  });

  test('testNaNFilter', () {
    final Query query = Query(ResourcePath.fromString('collection'))
        .filter(filter('sort', '==', double.nan));
    final Document doc1 =
        doc('collection/1', 0, map(<dynamic>['sort', double.nan]));
    final Document doc2 = doc('collection/2', 0, map(<dynamic>['sort', 2]));
    final Document doc3 = doc('collection/3', 0, map(<dynamic>['sort', 3.1]));
    final Document doc4 = doc('collection/4', 0, map(<dynamic>['sort', false]));
    final Document doc5 =
        doc('collection/5', 0, map(<dynamic>['sort', 'string']));

    expect(query.matches(doc1), isTrue);
    expect(query.matches(doc2), isFalse);
    expect(query.matches(doc3), isFalse);
    expect(query.matches(doc4), isFalse);
    expect(query.matches(doc5), isFalse);

    final Query notEqual = Query(ResourcePath.fromString('collection'))
        .filter(filter('sort', '!=', double.nan));
    expect(notEqual.matches(doc1), isFalse);
    expect(notEqual.matches(doc2), isTrue);
    expect(notEqual.matches(doc3), isTrue);
    expect(notEqual.matches(doc4), isTrue);
    expect(notEqual.matches(doc5), isTrue);
  });

  test('testNullFilter', () {
    final Query query = Query(ResourcePath.fromString('collection'))
        .filter(filter('sort', '==', null));
    final Document doc1 = doc('collection/1', 0, map(<dynamic>['sort', null]));
    final Document doc2 = doc('collection/2', 0, map(<dynamic>['sort', 2]));
    final Document doc3 = doc('collection/3', 0, map(<dynamic>['sort', 3.1]));
    final Document doc4 = doc('collection/4', 0, map(<dynamic>['sort', false]));
    final Document doc5 =
        doc('collection/5', 0, map(<dynamic>['sort', 'string']));

    expect(query.matches(doc1), isTrue);
    expect(query.matches(doc2), isFalse);
    expect(query.matches(doc3), isFalse);
    expect(query.matches(doc4), isFalse);
    expect(query.matches(doc5), isFalse);

    final Query notEqual = Query(ResourcePath.fromString('collection'))
        .filter(filter('sort', '!=', null));
    expect(notEqual.matches(doc1), isFalse);
    expect(notEqual.matches(doc2), isTrue);
    expect(notEqual.matches(doc3), isTrue);
    expect(notEqual.matches(doc4), isTrue);
    expect(notEqual.matches(doc5), isTrue);
  });

  test('testSupportsNullAndNaNInFilters', () {
    final Query query = Query(ResourcePath.fromString('collection'));
    for (String op in <String>['<', '<=', '>', '>=', '==', '!=']) {
      expect(() => query.filter(filter('sort', op, null)), returnsNormally);
      expect(
          () => query.filter(filter('sort', op, double.nan)), returnsNormally);
    }
  });

  test('testComplexObjectFilters', () {
    final Query query1 = Query(ResourcePath.fromString('collection'))
        .filter(filter('sort', '<=', 2));
    final Query query2 = Query(ResourcePath.fromString('collection'))
        .filter(filter('sort', '>=', 2));

    final Document doc1 = doc('collection/1', 0, map(<dynamic>['sort', 2]));
    final Document doc2 =
        doc('collection/2', 0, map(<dynamic>['sort', <int>[]]));
    final Document doc3 = doc(
        'collection/3',
        0,
        map(<dynamic>[
          'sort',
          <int>[1]
        ]));
    final Document doc4 = doc(
        'collection/4',
        0,
        map(<dynamic>[
          'sort',
          map<dynamic>(<dynamic>['foo', 2])
        ]));
    final Document doc5 = doc(
        'collection/5',
        0,
        map(<dynamic>[
          'sort',
          map<String>(<String>['foo', 'bar'])
        ]));
    final Document doc6 =
        doc('collection/6', 0, map(<dynamic>['sort', map<int>(<int>[])]));
    final Document doc7 = doc(
        'collection/7',
        0,
        map(<dynamic>[
          'sort',
          <int>[3, 1]
        ]));

    expect(query1.matches(doc1), isTrue);
    expect(query1.matches(doc2), isFalse);
    expect(query1.matches(doc3), isFalse);
    expect(query1.matches(doc4), isFalse);
    expect(query1.matches(doc5), isFalse);
    expect(query1.matches(doc6), isFalse);
    expect(query1.matches(doc7), isFalse);

    expect(query2.matches(doc1), isTrue);
    expect(query2.matches(doc2), isFalse);
    expect(query2.matches(doc3), isFalse);
    expect(query2.matches(doc4), isFalse);
    expect(query2.matches(doc5), isFalse);
    expect(query2.matches(doc6), isFalse);
    expect(query2.matches(doc7), isFalse);
  });

  test('testDoesNotRemoveComplexObjectsWithOrderBy', () {
    final Query query =
        Query(ResourcePath.fromString('collection')).orderBy(orderBy('sort'));

    final Document doc1 = doc('collection/1', 0, map(<dynamic>['sort', 2]));
    final Document doc2 =
        doc('collection/2', 0, map(<dynamic>['sort', <int>[]]));
    final Document doc3 = doc(
        'collection/3',
        0,
        map(<dynamic>[
          'sort',
          <int>[1]
        ]));
    final Document doc4 = doc(
        'collection/4',
        0,
        map(<dynamic>[
          'sort',
          map<dynamic>(<dynamic>['foo', 2])
        ]));
    final Document doc5 = doc(
        'collection/5',
        0,
        map(<dynamic>[
          'sort',
          map<String>(<String>['foo', 'bar'])
        ]));

    expect(query.matches(doc1), isTrue);
    expect(query.matches(doc2), isTrue);
    expect(query.matches(doc3), isTrue);
    expect(query.matches(doc4), isTrue);
    expect(query.matches(doc5), isTrue);
  });

  test('testFiltersArrays', () {
    final Query baseQuery = Query(ResourcePath.fromString('collection'));
    final Document doc1 = doc(
        'collection/doc',
        0,
        map(<dynamic>[
          'tags',
          <dynamic>['foo', 1, true]
        ]));
    final List<Filter> matchingFilters = <Filter>[
      filter('tags', '==', <dynamic>['foo', 1, true])
    ];

    final List<Filter> nonMatchingFilters = <Filter>[
      filter('tags', '==', 'foo'),
      filter('tags', '==', <dynamic>['foo', 1]),
      filter('tags', '==', <dynamic>['foo', true, 1])
    ];

    for (Filter filter in matchingFilters) {
      expect(baseQuery.filter(filter).matches(doc1), isTrue);
    }

    for (Filter filter in nonMatchingFilters) {
      expect(baseQuery.filter(filter).matches(doc1), isFalse);
    }
  });

  test('testFiltersObjects', () {
    final Query baseQuery = Query(ResourcePath.fromString('collection'));
    final Document doc1 = doc(
        'collection/doc',
        0,
        map(<dynamic>[
          'tags',
          map<dynamic>(
              <dynamic>['foo', 'foo', 'a', 0, 'b', true, 'c', double.nan])
        ]));

    final List<Filter> matchingFilters = <Filter>[
      filter(
          'tags',
          '==',
          map<dynamic>(
              <dynamic>['foo', 'foo', 'a', 0, 'b', true, 'c', double.nan])),
      filter(
          'tags',
          '==',
          map<dynamic>(
              <dynamic>['b', true, 'a', 0, 'foo', 'foo', 'c', double.nan])),
      filter('tags.foo', '==', 'foo')
    ];

    final List<Filter> nonMatchingFilters = <Filter>[
      filter('tags', '==', 'foo'),
      filter('tags', '==',
          map<dynamic>(<dynamic>['foo', 'foo', 'a', 0, 'b', true]))
    ];

    for (Filter filter in matchingFilters) {
      expect(baseQuery.filter(filter).matches(doc1), isTrue);
    }

    for (Filter filter in nonMatchingFilters) {
      expect(baseQuery.filter(filter).matches(doc1), isFalse);
    }
  });

  test('testSortsDocuments', () {
    final Query query =
        Query(ResourcePath.fromString('collection')).orderBy(orderBy('sort'));
    ComparatorTester<Document>(query.comparator)
        .addItem(doc('collection/1', 0, map(<dynamic>['sort', null])))
        .addItem(doc('collection/1', 0, map(<dynamic>['sort', false])))
        .addItem(doc('collection/1', 0, map(<dynamic>['sort', true])))
        .addItem(doc('collection/1', 0, map(<dynamic>['sort', 1])))
        .addItem(doc('collection/2', 0, map(<dynamic>['sort', 1]))) // by key
        .addItem(doc('collection/3', 0, map(<dynamic>['sort', 1]))) // by key
        .addItem(doc('collection/1', 0, map(<dynamic>['sort', 1.9])))
        .addItem(doc('collection/1', 0, map(<dynamic>['sort', 2])))
        .addItem(doc('collection/1', 0, map(<dynamic>['sort', 2.1])))
        .addItem(doc('collection/1', 0, map(<dynamic>['sort', ''])))
        .addItem(doc('collection/1', 0, map(<dynamic>['sort', 'a'])))
        .addItem(doc('collection/1', 0, map(<dynamic>['sort', 'ab'])))
        .addItem(doc('collection/1', 0, map(<dynamic>['sort', 'b'])))
        .addItem(doc(
            'collection/1', 0, map(<dynamic>['sort', ref('collection/id1')])))
        .testCompare();
  });

  test('testSortsWithMultipleFields', () {
    final Query query = Query(ResourcePath.fromString('collection'))
        .orderBy(orderBy('sort1'))
        .orderBy(orderBy('sort2'));

    ComparatorTester<Document>(query.comparator)
        .addItem(doc('collection/1', 0, map(<dynamic>['sort1', 1, 'sort2', 1])))
        .addItem(doc('collection/1', 0, map(<dynamic>['sort1', 1, 'sort2', 2])))
        .addItem(doc('collection/2', 0,
            map(<dynamic>['sort1', 1, 'sort2', 2]))) // by key
        .addItem(doc('collection/3', 0,
            map(<dynamic>['sort1', 1, 'sort2', 2]))) // by key
        .addItem(doc('collection/1', 0, map(<dynamic>['sort1', 1, 'sort2', 3])))
        .addItem(doc('collection/1', 0, map(<dynamic>['sort1', 2, 'sort2', 1])))
        .addItem(doc('collection/1', 0, map(<dynamic>['sort1', 2, 'sort2', 2])))
        .addItem(doc('collection/2', 0,
            map(<dynamic>['sort1', 2, 'sort2', 2]))) // by key
        .addItem(doc('collection/3', 0,
            map(<dynamic>['sort1', 2, 'sort2', 2]))) // by key
        .addItem(doc('collection/1', 0, map(<dynamic>['sort1', 2, 'sort2', 3])))
        .testCompare();
  });

  test('testSortsDescending', () {
    final Query query = Query(ResourcePath.fromString('collection'))
        .orderBy(orderBy('sort1', 'desc'))
        .orderBy(orderBy('sort2', 'desc'));

    ComparatorTester<Document>(query.comparator)
        .addItem(doc('collection/1', 0, map(<dynamic>['sort1', 2, 'sort2', 3])))
        .addItem(doc('collection/3', 0, map(<dynamic>['sort1', 2, 'sort2', 2])))
        .addItem(doc('collection/2', 0,
            map(<dynamic>['sort1', 2, 'sort2', 2]))) // by key
        .addItem(doc('collection/1', 0,
            map(<dynamic>['sort1', 2, 'sort2', 2]))) // by key
        .addItem(doc('collection/1', 0, map(<dynamic>['sort1', 2, 'sort2', 1])))
        .addItem(doc('collection/1', 0, map(<dynamic>['sort1', 1, 'sort2', 3])))
        .addItem(doc('collection/3', 0, map(<dynamic>['sort1', 1, 'sort2', 2])))
        .addItem(doc('collection/2', 0,
            map(<dynamic>['sort1', 1, 'sort2', 2]))) // by key
        .addItem(doc('collection/1', 0,
            map(<dynamic>['sort1', 1, 'sort2', 2]))) // by key
        .addItem(doc('collection/1', 0, map(<dynamic>['sort1', 1, 'sort2', 1])))
        .testCompare();
  });

  test('testHashCode', () {
    final Query q1a = Query(ResourcePath.fromString('foo'))
        .filter(filter('i1', '<', 2))
        .filter(filter('i2', '==', 3));

    // TODO(long1eu): uncomment this when hashcode does not depend on filter order.
    /*
    Query q1b =
        Query(ResourcePath.fromString('foo'))
            .filter(filter('i2', '==', 3))
            .filter(filter('i1', '<', 2));
    */

    final Query q2a = Query(ResourcePath.fromString('foo'));
    final Query q2b = Query(ResourcePath.fromString('foo'));

    final Query q3a = Query(ResourcePath.fromString('foo/bar'));
    final Query q3b = Query(ResourcePath.fromString('foo/bar'));

    final Query q4a = Query(ResourcePath.fromString('foo'))
        .orderBy(orderBy('foo'))
        .orderBy(orderBy('bar'));
    final Query q4b = Query(ResourcePath.fromString('foo'))
        .orderBy(orderBy('foo'))
        .orderBy(orderBy('bar'));

    final Query q5a = Query(ResourcePath.fromString('foo'))
        .orderBy(orderBy('bar'))
        .orderBy(orderBy('foo'));

    final Query q6a = Query(ResourcePath.fromString('foo'))
        .filter(filter('bar', '>', 2))
        .orderBy(orderBy('bar'));

    final Query q7a = Query(ResourcePath.fromString('foo')).limit(10);

    // TODO(long1eu): Add test cases with{Lower,Upper}Bound once cursors are implemented.
    testEquality(<List<int>>[
      <int>[q1a.hashCode],
      <int>[q2a.hashCode, q2b.hashCode],
      <int>[q3a.hashCode, q3b.hashCode],
      <int>[q4a.hashCode, q4b.hashCode],
      <int>[q5a.hashCode],
      <int>[q6a.hashCode],
      <int>[q7a.hashCode]
    ]);
  });

  test('testImplicitOrderBy', () {
    final Query baseQuery = Query(path('foo'));
    // Default is ascending
    expect(baseQuery.orderByConstraints,
        <OrderBy>[orderBy(DocumentKey.keyFieldName, 'asc')]);

    // Explicit key ordering is respected
    expect(
        baseQuery
            .orderBy(orderBy(DocumentKey.keyFieldName, 'asc'))
            .orderByConstraints,
        <OrderBy>[orderBy(DocumentKey.keyFieldName, 'asc')]);
    expect(
        baseQuery
            .orderBy(orderBy(DocumentKey.keyFieldName, 'desc'))
            .orderByConstraints,
        <OrderBy>[orderBy(DocumentKey.keyFieldName, 'desc')]);
    expect(
        baseQuery
            .orderBy(orderBy('foo'))
            .orderBy(orderBy(DocumentKey.keyFieldName, 'asc'))
            .orderByConstraints,
        <OrderBy>[orderBy('foo'), orderBy(DocumentKey.keyFieldName, 'asc')]);
    expect(
        baseQuery
            .orderBy(orderBy('foo'))
            .orderBy(orderBy(DocumentKey.keyFieldName, 'desc'))
            .orderByConstraints,
        <OrderBy>[orderBy('foo'), orderBy(DocumentKey.keyFieldName, 'desc')]);

    // Inequality filters add order bys
    expect(baseQuery.filter(filter('foo', '<', 5)).orderByConstraints,
        <OrderBy>[orderBy('foo'), orderBy(DocumentKey.keyFieldName, 'asc')]);

    // Descending order by applies to implicit key ordering
    expect(
        baseQuery.orderBy(orderBy('foo', 'desc')).orderByConstraints, <OrderBy>[
      orderBy('foo', 'desc'),
      orderBy(DocumentKey.keyFieldName, 'desc')
    ]);
    expect(
        baseQuery
            .orderBy(orderBy('foo', 'asc'))
            .orderBy(orderBy('bar', 'desc'))
            .orderByConstraints,
        <OrderBy>[
          orderBy('foo', 'asc'),
          orderBy('bar', 'desc'),
          orderBy(DocumentKey.keyFieldName, 'desc')
        ]);
    expect(
        baseQuery
            .orderBy(orderBy('foo', 'desc'))
            .orderBy(orderBy('bar', 'asc'))
            .orderByConstraints,
        <OrderBy>[
          orderBy('foo', 'desc'),
          orderBy('bar', 'asc'),
          orderBy(DocumentKey.keyFieldName, 'asc')
        ]);
  });

  test('canonicalId contains the limit value', () {
    final Query base = Query(ResourcePath.fromString('a'));
    expect(base.limit(5).toTarget().canonicalId, 'a|f:|ob:__name__asc|l:5');
    expect(base.limit(5).canonicalId,
        'a|f:|ob:__name__asc|l:5|lt:LIMIT_TO_FIRST');
    expect(base.limit(5).canonicalId, isNot(base.limit(10).canonicalId));
    expect(base.toTarget().canonicalId, 'a|f:|ob:__name__asc');
    expect(base.canonicalId, 'a|f:|ob:__name__asc|lt:LIMIT_TO_FIRST');
  });

  group('limitToLast', () {
    Query base() => Query(ResourcePath.fromString('collection'));

    test('limit and limitToLast override each other', () {
      final Query first = base().limit(3);
      expect(first.limitType, LimitType.limitToFirst);
      expect(first.hasLimitToFirst, isTrue);
      expect(first.hasLimitToLast, isFalse);

      final Query last = first.limitToLast(5);
      expect(last.limitType, LimitType.limitToLast);
      expect(last.hasLimitToLast, isTrue);
      expect(last.hasLimitToFirst, isFalse);
      expect(last.getLimit(), 5);

      final Query backToFirst = last.limit(2);
      expect(backToFirst.limitType, LimitType.limitToFirst);
      expect(backToFirst.getLimit(), 2);
      expect(backToFirst, base().limitToFirst(2));
    });

    test('a query without limit reports neither limit type', () {
      expect(base().hasLimitToFirst, isFalse);
      expect(base().hasLimitToLast, isFalse);
    });

    test('toTarget of a limitToFirst query keeps the implicit ordering', () {
      final Query query = base().orderBy(orderBy('foo')).limit(4);
      final Target target = query.toTarget();
      expect(target.orderBy, query.orderByConstraints);
      expect(target.orderBy,
          <OrderBy>[orderBy('foo'), orderBy(DocumentKey.keyFieldName)]);
      expect(target.limit, 4);
    });

    test('toTarget of a limitToLast query flips the orderings', () {
      final Query query = base()
          .orderBy(orderBy('foo', 'desc'))
          .orderBy(orderBy('bar'))
          .limitToLast(4);
      final Target target = query.toTarget();
      expect(target.orderBy, <OrderBy>[
        orderBy('foo'),
        orderBy('bar', 'desc'),
        orderBy(DocumentKey.keyFieldName, 'desc'),
      ]);
      expect(target.limit, 4);

      // The query itself keeps its own ordering.
      expect(query.orderByConstraints, <OrderBy>[
        orderBy('foo', 'desc'),
        orderBy('bar'),
        orderBy(DocumentKey.keyFieldName),
      ]);
    });

    test('toTarget of a limitToLast query swaps and flips the bounds', () {
      final Bound start =
          Bound(position: <FieldValue>[wrap(1)], before: true);
      final Bound end = Bound(position: <FieldValue>[wrap(9)], before: false);
      final Target target = base()
          .orderBy(orderBy('foo'))
          .startAt(start)
          .endAt(end)
          .limitToLast(2)
          .toTarget();

      expect(target.startAt!.position, end.position);
      expect(target.startAt!.before, isTrue);
      expect(target.endAt!.position, start.position);
      expect(target.endAt!.before, isFalse);

      // Without bounds nothing is invented.
      final Target unbounded =
          base().orderBy(orderBy('foo')).limitToLast(2).toTarget();
      expect(unbounded.startAt, isNull);
      expect(unbounded.endAt, isNull);

      // Only one bound.
      final Target onlyStart =
          base().orderBy(orderBy('foo')).startAt(start).limitToLast(2).toTarget();
      expect(onlyStart.startAt, isNull);
      expect(onlyStart.endAt!.before, isFalse);
    });

    test('mirror queries map to the same target', () {
      final Query limit = base().orderBy(orderBy('sort')).limit(2);
      final Query limitToLast =
          base().orderBy(orderBy('sort', 'desc')).limitToLast(2);

      expect(limit.toTarget(), limitToLast.toTarget());
      expect(limit.toTarget().canonicalId, limitToLast.toTarget().canonicalId);
      expect(limit.toTarget().hashCode, limitToLast.toTarget().hashCode);

      // ... but they are different queries.
      expect(limit, isNot(limitToLast));
      expect(limit.canonicalId, isNot(limitToLast.canonicalId));
      expect(limitToLast.canonicalId, endsWith('|lt:LIMIT_TO_LAST'));
    });

    test('equality takes the limit type into account', () {
      final Query q = base().orderBy(orderBy('sort'));
      expect(q.limit(3), q.limit(3));
      expect(q.limit(3).hashCode, q.limit(3).hashCode);
      expect(q.limitToLast(3), q.limitToLast(3));
      expect(q.limitToLast(3).hashCode, q.limitToLast(3).hashCode);
      expect(q.limit(3), isNot(q.limitToLast(3)));
      expect(q.limitToLast(3), isNot(q.limitToLast(4)));
    });

    test('target canonicalId matches the Java format', () {
      final Query q = base().orderBy(orderBy('foo', 'desc')).limitToLast(7);
      expect(q.toTarget().canonicalId,
          'collection|f:|ob:fooasc__name__asc|l:7');
      expect(q.canonicalId,
          'collection|f:|ob:fooasc__name__asc|l:7|lt:LIMIT_TO_LAST');
    });

    test('the target is memoized', () {
      final Query q = base().orderBy(orderBy('foo')).limitToLast(7);
      expect(identical(q.toTarget(), q.toTarget()), isTrue);
    });

    test('matches ignores the limit type', () {
      final Query q = base().orderBy(orderBy('foo')).limitToLast(1);
      expect(q.matches(doc('collection/a', 0, map(<dynamic>['foo', 1]))),
          isTrue);
      expect(q.matches(doc('collection/a', 0, map(<dynamic>['bar', 1]))),
          isFalse);
    });

    test('asCollectionQueryAtPath keeps the limit type', () {
      final Query group = Query(ResourcePath.fromString(''),
              collectionGroup: 'messages')
          .orderBy(orderBy('foo'))
          .limitToLast(3);
      final Query atPath =
          group.asCollectionQueryAtPath(ResourcePath.fromString('rooms/1/messages'));
      expect(atPath.limitType, LimitType.limitToLast);
      expect(atPath.getLimit(), 3);
    });
  });

  group('OR queries and multiple inequalities', () {
    Query base() => Query(ResourcePath.fromString('foo'));
    const String key = DocumentKey.keyFieldName;

    // Port of upstream QueryTest.testImplicitOrderByInMultipleInequality.
    test('implicit orderBy over several inequality fields', () {
      expect(
          base()
              .filter(filter('a', '<', 5))
              .filter(filter('a', '>=', 5))
              .filter(filter('aa', '<', 5))
              .filter(filter('b', '<', 5))
              .filter(filter('A', '<', 5))
              .orderByConstraints,
          <OrderBy>[
            orderBy('A'),
            orderBy('a'),
            orderBy('aa'),
            orderBy('b'),
            orderBy(key),
          ]);

      // numbers
      expect(
          base()
              .filter(filter('a', '<', 5))
              .filter(filter('1', '<', 5))
              .filter(filter('2', '<', 5))
              .filter(filter('19', '<', 5))
              .orderByConstraints,
          <OrderBy>[
            orderBy('1'),
            orderBy('19'),
            orderBy('2'),
            orderBy('a'),
            orderBy(key),
          ]);

      // nested fields
      expect(
          base()
              .filter(filter('a', '<', 5))
              .filter(filter('aa', '<', 5))
              .filter(filter('a.a', '<', 5))
              .orderByConstraints,
          <OrderBy>[orderBy('a'), orderBy('a.a'), orderBy('aa'), orderBy(key)]);

      // special characters
      expect(
          base()
              .filter(filter('a', '<', 5))
              .filter(filter('_a', '<', 5))
              .filter(filter('a.a', '<', 5))
              .orderByConstraints,
          <OrderBy>[orderBy('_a'), orderBy('a'), orderBy('a.a'), orderBy(key)]);

      // composite filter
      expect(
          base().filter(filter('a', '<', 5)).filter(andFilters(<Filter>[
            orFilters(<Filter>[filter('b', '>=', 1), filter('c', '<=', 1)]),
            orFilters(<Filter>[filter('d', '<=', 1), filter('e', '==', 1)]),
          ])).orderByConstraints,
          <OrderBy>[
            orderBy('a'),
            orderBy('b'),
            orderBy('c'),
            orderBy('d'),
            orderBy(key),
          ]);

      // explicit orderBy comes first
      expect(
          base()
              .filter(filter('b', '<', 5))
              .filter(filter('a', '<', 5))
              .filter(filter('z', '<', 5))
              .orderBy(orderBy('z'))
              .orderByConstraints,
          <OrderBy>[orderBy('z'), orderBy('a'), orderBy('b'), orderBy(key)]);

      // the direction of the last explicit orderBy applies to the implicit ones
      expect(
          base()
              .filter(filter('b', '<', 5))
              .filter(filter('a', '<', 5))
              .orderBy(orderBy('z', 'desc'))
              .orderByConstraints,
          <OrderBy>[
            orderBy('z', 'desc'),
            orderBy('a', 'desc'),
            orderBy('b', 'desc'),
            orderBy(key, 'desc'),
          ]);

      expect(
          base()
              .filter(filter('b', '<', 5))
              .filter(filter('a', '<', 5))
              .orderBy(orderBy('z', 'desc'))
              .orderBy(orderBy('c'))
              .orderByConstraints,
          <OrderBy>[
            orderBy('z', 'desc'),
            orderBy('c'),
            orderBy('a'),
            orderBy('b'),
            orderBy(key),
          ]);
    });

    test('inequality on the key field is ordered last', () {
      expect(
          base().filter(filter(key, '>', ref('foo/a'))).orderByConstraints,
          <OrderBy>[orderBy(key)]);
      expect(
          base()
              .filter(filter(key, '>', ref('foo/a')))
              .filter(filter('a', '<', 1))
              .orderByConstraints,
          <OrderBy>[orderBy('a'), orderBy(key)]);
    });

    test('inequalityFilterFields includes nested composite filters', () {
      final Query query = base()
          .filter(filter('c', '==', 1))
          .filter(orFilters(<Filter>[
            filter('b', '>', 1),
            andFilters(<Filter>[filter('a', '!=', 1), filter('d', '==', 2)]),
          ]))
          .filter(filter('e', 'not-in', <int>[1]));
      expect(query.inequalityFilterFields,
          <FieldPath>[field('a'), field('b'), field('e')]);
      expect(query.firstInequalityField, field('a'));
      expect(base().filter(filter('a', '==', 1)).firstInequalityField, isNull);
    });

    test('canonicalId of a flat conjunction equals the chained filters', () {
      final Filter a = filter('a', '==', 1);
      final Filter b = filter('b', '==', 2);
      expect(base().filter(andFilters(<Filter>[a, b])).canonicalId,
          base().filter(a).filter(b).canonicalId);
      expect(base().filter(orFilters(<Filter>[a, b])).toTarget().canonicalId,
          'foo|f:or(a == 1,b == 2)|ob:__name__asc');
      expect(
          base()
              .filter(orFilters(<Filter>[
                a,
                andFilters(<Filter>[b, filter('c', '>', 3)])
              ]))
              .toTarget()
              .canonicalId,
          'foo|f:or(a == 1,b == 2c > 3)|ob:casc__name__asc');
    });

    void assertQueryMatches(
        Query query, List<Document> matching, List<Document> nonMatching) {
      for (Document d in matching) {
        expect(query.matches(d), isTrue, reason: '${d.key} should match');
      }
      for (Document d in nonMatching) {
        expect(query.matches(d), isFalse, reason: '${d.key} should not match');
      }
    }

    // Port of upstream QueryTest.testOrQuery.
    test('OR queries match', () {
      final Document doc1 =
          doc('collection/1', 0, map(<dynamic>['a', 1, 'b', 0]));
      final Document doc2 =
          doc('collection/2', 0, map(<dynamic>['a', 2, 'b', 1]));
      final Document doc3 =
          doc('collection/3', 0, map(<dynamic>['a', 3, 'b', 2]));
      final Document doc4 =
          doc('collection/4', 0, map(<dynamic>['a', 1, 'b', 3]));
      final Document doc5 =
          doc('collection/5', 0, map(<dynamic>['a', 1, 'b', 1]));
      Query collection() => query('collection');

      // Two equalities: a==1 || b==1.
      assertQueryMatches(
          collection().filter(orFilters(
              <Filter>[filter('a', '==', 1), filter('b', '==', 1)])),
          <Document>[doc1, doc2, doc4, doc5],
          <Document>[doc3]);

      // with one inequality: a>2 || b==1.
      assertQueryMatches(
          collection().filter(orFilters(
              <Filter>[filter('a', '>', 2), filter('b', '==', 1)])),
          <Document>[doc2, doc3, doc5],
          <Document>[doc1, doc4]);

      // (a==1 && b==0) || (a==3 && b==2)
      assertQueryMatches(
          collection().filter(orFilters(<Filter>[
            andFilters(<Filter>[filter('a', '==', 1), filter('b', '==', 0)]),
            andFilters(<Filter>[filter('a', '==', 3), filter('b', '==', 2)]),
          ])),
          <Document>[doc1, doc3],
          <Document>[doc2, doc4, doc5]);

      // a==1 && (b==0 || b==3).
      assertQueryMatches(
          collection().filter(andFilters(<Filter>[
            filter('a', '==', 1),
            orFilters(<Filter>[filter('b', '==', 0), filter('b', '==', 3)]),
          ])),
          <Document>[doc1, doc4],
          <Document>[doc2, doc3, doc5]);

      // (a==2 || b==2) && (a==3 || b==3)
      assertQueryMatches(
          collection().filter(andFilters(<Filter>[
            orFilters(<Filter>[filter('a', '==', 2), filter('b', '==', 2)]),
            orFilters(<Filter>[filter('a', '==', 3), filter('b', '==', 3)]),
          ])),
          <Document>[doc3],
          <Document>[doc1, doc2, doc4, doc5]);
    });

    test('OR query with an inequality requires the implicit orderBy field', () {
      // "a > 1 || b == 1" has an implicit "orderBy a": a document with only
      // {b: 1} satisfies the filter but not the orderBy.
      final Query query = base().filter(
          orFilters(<Filter>[filter('a', '>', 1), filter('b', '==', 1)]));
      expect(query.matches(doc('foo/1', 0, map(<dynamic>['b', 1]))), isFalse);
      expect(
          query.matches(doc('foo/2', 0, map(<dynamic>['a', 2, 'b', 0]))),
          isTrue);
      expect(
          query.matches(doc('foo/3', 0, map(<dynamic>['a', 0, 'b', 1]))),
          isTrue);
    });

    test('multiple inequality fields all have to match', () {
      final Query query = base()
          .filter(filter('a', '>', 1))
          .filter(filter('b', '<=', 5))
          .filter(filter('c', '!=', 3));
      expect(
          query.matches(doc('foo/1', 0, map(<dynamic>['a', 2, 'b', 5, 'c', 4]))),
          isTrue);
      expect(
          query.matches(doc('foo/2', 0, map(<dynamic>['a', 1, 'b', 5, 'c', 4]))),
          isFalse);
      expect(
          query.matches(doc('foo/3', 0, map(<dynamic>['a', 2, 'b', 6, 'c', 4]))),
          isFalse);
      expect(
          query.matches(doc('foo/4', 0, map(<dynamic>['a', 2, 'b', 5, 'c', 3]))),
          isFalse);
      expect(query.matches(doc('foo/5', 0, map(<dynamic>['a', 2, 'b', 5]))),
          isFalse);
    });

    test('filters nested in a composite filter do not break isDocumentQuery',
        () {
      expect(Query(ResourcePath.fromString('foo/bar')).isDocumentQuery, isTrue);
      expect(
          Query(ResourcePath.fromString('foo/bar'),
                  filters: <Filter>[orFilters(<Filter>[filter('a', '==', 1)])])
              .isDocumentQuery,
          isFalse);
    });

    test('limitToLast flips the implicit multiple inequality orderings', () {
      final Query q = base()
          .filter(filter('b', '>', 1))
          .filter(filter('a', '>', 1))
          .orderBy(orderBy('z'))
          .limitToLast(2);
      expect(q.toTarget().orderBy, <OrderBy>[
        orderBy('z', 'desc'),
        orderBy('a', 'desc'),
        orderBy('b', 'desc'),
        orderBy(key, 'desc'),
      ]);
    });
  });
}
