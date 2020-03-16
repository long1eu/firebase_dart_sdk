// File created by
// Lung Razvan <long1eu>
// on 27/09/2018

import 'package:cloud_firestore_vm/src/firebase/firestore/core/filter.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/order_by.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/resource_path.dart';
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
  });

  test('testOnlySupportsEqualsForNull', () {
    final List<String> invalidOps = <String>['<', '<=', '>', '>='];
    final Query query = Query(ResourcePath.fromString('collection'));
    for (String op in invalidOps) {
      expect(() => query.filter(filter('sort', op, null)), throwsArgumentError);
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
}
