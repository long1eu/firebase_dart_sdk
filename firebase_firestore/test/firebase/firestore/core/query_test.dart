// File created by
// Lung Razvan <long1eu>
// on 27/09/2018

import 'package:firebase_firestore/src/firebase/firestore/core/filter.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/order_by.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/resource_path.dart';
import 'package:test/test.dart';

import '../../../util/comparator_test.dart';
import '../../../util/test_util.dart';

void main() {
  test('testMatchesBasedDocumentKey', () {
    final ResourcePath queryPath =
        ResourcePath.fromString('rooms/eros/messages/1');
    final Document doc1 = TestUtil.docForMap('rooms/eros/messages/1', 0,
        TestUtil.map(<String>['text', 'msg1']), false);
    final Document doc2 = TestUtil.docForMap('rooms/eros/messages/2', 0,
        TestUtil.map(<String>['text', 'msg2']), false);
    final Document doc3 = TestUtil.docForMap('rooms/other/messages/1', 0,
        TestUtil.map(<String>['text', 'msg3']), false);

    final Query query = Query.atPath(queryPath);
    expect(query.matches(doc1), isTrue);
    expect(query.matches(doc2), isFalse);
    expect(query.matches(doc3), isFalse);
  });

  test('testMatchesShallowAncestorQuery', () {
    final ResourcePath queryPath =
        ResourcePath.fromString('rooms/eros/messages');
    final Document doc1 = TestUtil.docForMap('rooms/eros/messages/1', 0,
        TestUtil.map(<String>['text', 'msg1']), false);
    final Document doc1meta = TestUtil.docForMap('rooms/eros/messages/1/meta/1',
        0, TestUtil.map(<dynamic>['meta', 'meta-value']), false);
    final Document doc2 = TestUtil.docForMap('rooms/eros/messages/2', 0,
        TestUtil.map(<String>['text', 'msg2']), false);
    final Document doc3 = TestUtil.docForMap('rooms/other/messages/1', 0,
        TestUtil.map(<String>['text', 'msg3']), false);

    final Query query = Query.atPath(queryPath);
    expect(query.matches(doc1), isTrue);
    expect(query.matches(doc1meta), isFalse);
    expect(query.matches(doc2), isTrue);
    expect(query.matches(doc3), isFalse);
  });

  test('testEmptyFieldsAreAllowedForQueries', () {
    final ResourcePath queryPath =
        ResourcePath.fromString('rooms/eros/messages');
    final Document doc1 = TestUtil.docForMap('rooms/eros/messages/1', 0,
        TestUtil.map(<String>['text', 'msg1']), false);
    final Document doc2 = TestUtil.docForMap(
        'rooms/eros/messages/2', 0, TestUtil.map(<String>[]), false);

    final Query query =
        Query.atPath(queryPath).filter(TestUtil.filter('text', '==', 'msg1'));
    expect(query.matches(doc1), isTrue);
    expect(query.matches(doc2), isFalse);
  });

  test('testPrimitiveValueFilter', () {
    final Query query1 = Query.atPath(ResourcePath.fromString('collection'))
        .filter(TestUtil.filter('sort', '>=', 2));
    final Query query2 = Query.atPath(ResourcePath.fromString('collection'))
        .filter(TestUtil.filter('sort', '<=', 2));

    final Document doc1 = TestUtil.docForMap(
        'collection/1', 0, TestUtil.map(<dynamic>['sort', 1]), false);
    final Document doc2 = TestUtil.docForMap(
        'collection/2', 0, TestUtil.map(<dynamic>['sort', 2]), false);
    final Document doc3 = TestUtil.docForMap(
        'collection/3', 0, TestUtil.map(<dynamic>['sort', 3]), false);
    final Document doc4 = TestUtil.docForMap(
        'collection/4', 0, TestUtil.map(<dynamic>['sort', false]), false);
    final Document doc5 = TestUtil.docForMap(
        'collection/5', 0, TestUtil.map(<dynamic>['sort', 'string']), false);

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
    final Query query = Query.atPath(ResourcePath.fromString('collection'))
        .filter(TestUtil.filter('array', 'array-contains', 42));

    // not an array
    Document document = TestUtil.docForMap(
        'collection/1', 0, TestUtil.map(<dynamic>['array', 1]));
    expect(query.matches(document), isFalse);

    // empty array
    document = TestUtil.docForMap(
        'collection/1', 0, TestUtil.map(<dynamic>['array', <dynamic>[]]));
    expect(query.matches(document), isFalse);

    // array without element (and make sure it doesn't match in a nested field or a different field)
    document = TestUtil.docForMap(
        'collection/1',
        0,
        TestUtil.map(<dynamic>[
          'array',
          <dynamic>[
            41,
            '42',
            TestUtil.map<dynamic>(<dynamic>[
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
    document = TestUtil.docForMap(
        'collection/1',
        0,
        TestUtil.map(<dynamic>[
          'array',
          <dynamic>[
            1,
            '2',
            42,
            TestUtil.map<dynamic>(<dynamic>['a', 1])
          ]
        ]));
    expect(query.matches(document), isTrue);
  });

  test('testArrayContainsFiltersWithObjectValues', () {
    // Search for arrays containing the object { a: [42] }
    final Query query = Query.atPath(ResourcePath.fromString('collection'))
        .filter(TestUtil.filter(
            'array',
            'array-contains',
            TestUtil.map<dynamic>(<dynamic>[
              'a',
              <int>[42]
            ])));

    // array without element
    Document document = TestUtil.docForMap(
        'collection/1',
        0,
        TestUtil.map(<dynamic>[
          'array',
          <dynamic>[
            TestUtil.map<dynamic>(<dynamic>['a', 42]),
            TestUtil.map<dynamic>(<dynamic>[
              'a',
              <int>[42, 43]
            ]),
            TestUtil.map<dynamic>(<dynamic>[
              'b',
              <int>[42]
            ]),
            TestUtil.map<dynamic>(<dynamic>[
              'a',
              <int>[42],
              'b',
              42
            ])
          ]
        ]));
    expect(query.matches(document), isFalse);

    // array with element
    document = TestUtil.docForMap(
        'collection/1',
        0,
        TestUtil.map(<dynamic>[
          'array',
          <dynamic>[
            1,
            '2',
            42,
            TestUtil.map<dynamic>(<dynamic>[
              'a',
              <int>[42]
            ])
          ]
        ]));

    print(document);

    expect(query.matches(document), isTrue);
  });

  test('testNaNFilter', () {
    final Query query = Query.atPath(ResourcePath.fromString('collection'))
        .filter(TestUtil.filter('sort', '==', double.nan));
    final Document doc1 = TestUtil.docForMap(
        'collection/1', 0, TestUtil.map(<dynamic>['sort', double.nan]), false);
    final Document doc2 = TestUtil.docForMap(
        'collection/2', 0, TestUtil.map(<dynamic>['sort', 2]), false);
    final Document doc3 = TestUtil.docForMap(
        'collection/3', 0, TestUtil.map(<dynamic>['sort', 3.1]), false);
    final Document doc4 = TestUtil.docForMap(
        'collection/4', 0, TestUtil.map(<dynamic>['sort', false]), false);
    final Document doc5 = TestUtil.docForMap(
        'collection/5', 0, TestUtil.map(<dynamic>['sort', 'string']), false);

    expect(query.matches(doc1), isTrue);
    expect(query.matches(doc2), isFalse);
    expect(query.matches(doc3), isFalse);
    expect(query.matches(doc4), isFalse);
    expect(query.matches(doc5), isFalse);
  });

  test('testNullFilter', () {
    final Query query = Query.atPath(ResourcePath.fromString('collection'))
        .filter(TestUtil.filter('sort', '==', null));
    final Document doc1 = TestUtil.docForMap(
        'collection/1', 0, TestUtil.map(<dynamic>['sort', null]), false);
    final Document doc2 = TestUtil.docForMap(
        'collection/2', 0, TestUtil.map(<dynamic>['sort', 2]), false);
    final Document doc3 = TestUtil.docForMap(
        'collection/3', 0, TestUtil.map(<dynamic>['sort', 3.1]), false);
    final Document doc4 = TestUtil.docForMap(
        'collection/4', 0, TestUtil.map(<dynamic>['sort', false]), false);
    final Document doc5 = TestUtil.docForMap(
        'collection/5', 0, TestUtil.map(<dynamic>['sort', 'string']), false);

    expect(query.matches(doc1), isTrue);
    expect(query.matches(doc2), isFalse);
    expect(query.matches(doc3), isFalse);
    expect(query.matches(doc4), isFalse);
    expect(query.matches(doc5), isFalse);
  });

  test('testOnlySupportsEqualsForNull', () {
    final List<String> invalidOps = <String>['<', '<=', '>', '>='];
    final Query query = Query.atPath(ResourcePath.fromString('collection'));
    for (String op in invalidOps) {
      expect(() => query.filter(TestUtil.filter('sort', op, null)),
          throwsArgumentError);
    }
  });

  test('testComplexObjectFilters', () {
    final Query query1 = Query.atPath(ResourcePath.fromString('collection'))
        .filter(TestUtil.filter('sort', '<=', 2));
    final Query query2 = Query.atPath(ResourcePath.fromString('collection'))
        .filter(TestUtil.filter('sort', '>=', 2));

    final Document doc1 = TestUtil.docForMap(
        'collection/1', 0, TestUtil.map(<dynamic>['sort', 2]), false);
    final Document doc2 = TestUtil.docForMap(
        'collection/2', 0, TestUtil.map(<dynamic>['sort', <int>[]]), false);
    final Document doc3 = TestUtil.docForMap(
        'collection/3',
        0,
        TestUtil.map(<dynamic>[
          'sort',
          <int>[1]
        ]),
        false);
    final Document doc4 = TestUtil.docForMap(
        'collection/4',
        0,
        TestUtil.map(<dynamic>[
          'sort',
          TestUtil.map<dynamic>(<dynamic>['foo', 2])
        ]),
        false);
    final Document doc5 = TestUtil.docForMap(
        'collection/5',
        0,
        TestUtil.map(<dynamic>[
          'sort',
          TestUtil.map<String>(<String>['foo', 'bar'])
        ]),
        false);
    final Document doc6 = TestUtil.docForMap('collection/6', 0,
        TestUtil.map(<dynamic>['sort', TestUtil.map<int>(<int>[])]), false);
    final Document doc7 = TestUtil.docForMap(
        'collection/7',
        0,
        TestUtil.map(<dynamic>[
          'sort',
          <int>[3, 1]
        ]),
        false);

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
    final Query query = Query.atPath(ResourcePath.fromString('collection'))
        .orderBy(TestUtil.orderBy('sort'));

    final Document doc1 = TestUtil.docForMap(
        'collection/1', 0, TestUtil.map(<dynamic>['sort', 2]), false);
    final Document doc2 = TestUtil.docForMap(
        'collection/2', 0, TestUtil.map(<dynamic>['sort', <int>[]]), false);
    final Document doc3 = TestUtil.docForMap(
        'collection/3',
        0,
        TestUtil.map(<dynamic>[
          'sort',
          <int>[1]
        ]),
        false);
    final Document doc4 = TestUtil.docForMap(
        'collection/4',
        0,
        TestUtil.map(<dynamic>[
          'sort',
          TestUtil.map<dynamic>(<dynamic>['foo', 2])
        ]),
        false);
    final Document doc5 = TestUtil.docForMap(
        'collection/5',
        0,
        TestUtil.map(<dynamic>[
          'sort',
          TestUtil.map<String>(<String>['foo', 'bar'])
        ]),
        false);

    expect(query.matches(doc1), isTrue);
    expect(query.matches(doc2), isTrue);
    expect(query.matches(doc3), isTrue);
    expect(query.matches(doc4), isTrue);
    expect(query.matches(doc5), isTrue);
  });

  test('testFiltersArrays', () {
    final Query baseQuery = Query.atPath(ResourcePath.fromString('collection'));
    final Document doc1 = TestUtil.docForMap(
        'collection/doc',
        0,
        TestUtil.map(<dynamic>[
          'tags',
          <dynamic>['foo', 1, true]
        ]),
        false);
    final List<Filter> matchingFilters = <Filter>[
      TestUtil.filter('tags', '==', <dynamic>['foo', 1, true])
    ];

    final List<Filter> nonMatchingFilters = <Filter>[
      TestUtil.filter('tags', '==', 'foo'),
      TestUtil.filter('tags', '==', <dynamic>['foo', 1]),
      TestUtil.filter('tags', '==', <dynamic>['foo', true, 1])
    ];

    for (Filter filter in matchingFilters) {
      expect(baseQuery.filter(filter).matches(doc1), isTrue);
    }

    for (Filter filter in nonMatchingFilters) {
      expect(baseQuery.filter(filter).matches(doc1), isFalse);
    }
  });

  test('testFiltersObjects', () {
    final Query baseQuery = Query.atPath(ResourcePath.fromString('collection'));
    final Document doc1 = TestUtil.docForMap(
        'collection/doc',
        0,
        TestUtil.map(<dynamic>[
          'tags',
          TestUtil.map<dynamic>(
              <dynamic>['foo', 'foo', 'a', 0, 'b', true, 'c', double.nan])
        ]),
        false);

    final List<Filter> matchingFilters = <Filter>[
      TestUtil.filter(
          'tags',
          '==',
          TestUtil.map<dynamic>(
              <dynamic>['foo', 'foo', 'a', 0, 'b', true, 'c', double.nan])),
      TestUtil.filter(
          'tags',
          '==',
          TestUtil.map<dynamic>(
              <dynamic>['b', true, 'a', 0, 'foo', 'foo', 'c', double.nan])),
      TestUtil.filter('tags.foo', '==', 'foo')
    ];

    final List<Filter> nonMatchingFilters = <Filter>[
      TestUtil.filter('tags', '==', 'foo'),
      TestUtil.filter('tags', '==',
          TestUtil.map<dynamic>(<dynamic>['foo', 'foo', 'a', 0, 'b', true]))
    ];

    for (Filter filter in matchingFilters) {
      expect(baseQuery.filter(filter).matches(doc1), isTrue);
    }

    for (Filter filter in nonMatchingFilters) {
      expect(baseQuery.filter(filter).matches(doc1), isFalse);
    }
  });

  test('testSortsDocuments', () {
    final Query query = Query.atPath(ResourcePath.fromString('collection'))
        .orderBy(TestUtil.orderBy('sort'));
    ComparatorTester<Document>(query.comparator)
        .addItem(TestUtil.docForMap(
            'collection/1', 0, TestUtil.map(<dynamic>['sort', null])))
        .addItem(TestUtil.docForMap(
            'collection/1', 0, TestUtil.map(<dynamic>['sort', false])))
        .addItem(TestUtil.docForMap(
            'collection/1', 0, TestUtil.map(<dynamic>['sort', true])))
        .addItem(TestUtil.docForMap(
            'collection/1', 0, TestUtil.map(<dynamic>['sort', 1])))
        .addItem(TestUtil.docForMap(
            'collection/2', 0, TestUtil.map(<dynamic>['sort', 1]))) // by key
        .addItem(TestUtil.docForMap(
            'collection/3', 0, TestUtil.map(<dynamic>['sort', 1]))) // by key
        .addItem(TestUtil.docForMap(
            'collection/1', 0, TestUtil.map(<dynamic>['sort', 1.9])))
        .addItem(TestUtil.docForMap(
            'collection/1', 0, TestUtil.map(<dynamic>['sort', 2])))
        .addItem(TestUtil.docForMap(
            'collection/1', 0, TestUtil.map(<dynamic>['sort', 2.1])))
        .addItem(TestUtil.docForMap(
            'collection/1', 0, TestUtil.map(<dynamic>['sort', ''])))
        .addItem(TestUtil.docForMap(
            'collection/1', 0, TestUtil.map(<dynamic>['sort', 'a'])))
        .addItem(TestUtil.docForMap(
            'collection/1', 0, TestUtil.map(<dynamic>['sort', 'ab'])))
        .addItem(TestUtil.docForMap(
            'collection/1', 0, TestUtil.map(<dynamic>['sort', 'b'])))
        .addItem(TestUtil.docForMap('collection/1', 0,
            TestUtil.map(<dynamic>['sort', TestUtil.ref('collection/id1')])))
        .testCompare();
  });

  test('testSortsWithMultipleFields', () {
    final Query query = Query.atPath(ResourcePath.fromString('collection'))
        .orderBy(TestUtil.orderBy('sort1'))
        .orderBy(TestUtil.orderBy('sort2'));

    ComparatorTester<Document>(query.comparator)
        .addItem(TestUtil.docForMap(
            'collection/1', 0, TestUtil.map(<dynamic>['sort1', 1, 'sort2', 1])))
        .addItem(TestUtil.docForMap(
            'collection/1', 0, TestUtil.map(<dynamic>['sort1', 1, 'sort2', 2])))
        .addItem(TestUtil.docForMap('collection/2', 0,
            TestUtil.map(<dynamic>['sort1', 1, 'sort2', 2]))) // by key
        .addItem(TestUtil.docForMap('collection/3', 0,
            TestUtil.map(<dynamic>['sort1', 1, 'sort2', 2]))) // by key
        .addItem(TestUtil.docForMap(
            'collection/1', 0, TestUtil.map(<dynamic>['sort1', 1, 'sort2', 3])))
        .addItem(TestUtil.docForMap(
            'collection/1', 0, TestUtil.map(<dynamic>['sort1', 2, 'sort2', 1])))
        .addItem(TestUtil.docForMap(
            'collection/1', 0, TestUtil.map(<dynamic>['sort1', 2, 'sort2', 2])))
        .addItem(TestUtil.docForMap('collection/2', 0,
            TestUtil.map(<dynamic>['sort1', 2, 'sort2', 2]))) // by key
        .addItem(TestUtil.docForMap('collection/3', 0,
            TestUtil.map(<dynamic>['sort1', 2, 'sort2', 2]))) // by key
        .addItem(TestUtil.docForMap(
            'collection/1', 0, TestUtil.map(<dynamic>['sort1', 2, 'sort2', 3])))
        .testCompare();
  });

  test('testSortsDescending', () {
    final Query query = Query.atPath(ResourcePath.fromString('collection'))
        .orderBy(TestUtil.orderBy('sort1', 'desc'))
        .orderBy(TestUtil.orderBy('sort2', 'desc'));

    ComparatorTester<Document>(query.comparator)
        .addItem(TestUtil.docForMap(
            'collection/1', 0, TestUtil.map(<dynamic>['sort1', 2, 'sort2', 3])))
        .addItem(TestUtil.docForMap(
            'collection/3', 0, TestUtil.map(<dynamic>['sort1', 2, 'sort2', 2])))
        .addItem(TestUtil.docForMap('collection/2', 0,
            TestUtil.map(<dynamic>['sort1', 2, 'sort2', 2]))) // by key
        .addItem(TestUtil.docForMap('collection/1', 0,
            TestUtil.map(<dynamic>['sort1', 2, 'sort2', 2]))) // by key
        .addItem(TestUtil.docForMap(
            'collection/1', 0, TestUtil.map(<dynamic>['sort1', 2, 'sort2', 1])))
        .addItem(TestUtil.docForMap(
            'collection/1', 0, TestUtil.map(<dynamic>['sort1', 1, 'sort2', 3])))
        .addItem(TestUtil.docForMap(
            'collection/3', 0, TestUtil.map(<dynamic>['sort1', 1, 'sort2', 2])))
        .addItem(TestUtil.docForMap('collection/2', 0,
            TestUtil.map(<dynamic>['sort1', 1, 'sort2', 2]))) // by key
        .addItem(TestUtil.docForMap('collection/1', 0,
            TestUtil.map(<dynamic>['sort1', 1, 'sort2', 2]))) // by key
        .addItem(TestUtil.docForMap(
            'collection/1', 0, TestUtil.map(<dynamic>['sort1', 1, 'sort2', 1])))
        .testCompare();
  });

  test('testHashCode', () {
    final Query q1a = Query.atPath(ResourcePath.fromString('foo'))
        .filter(TestUtil.filter('i1', '<', 2))
        .filter(TestUtil.filter('i2', '==', 3));

    // TODO uncomment this when hashcode does not depend on filter order.
    /*
    Query q1b =
        Query.atPath(ResourcePath.fromString('foo'))
            .filter(TestUtil.filter('i2', '==', 3))
            .filter(TestUtil.filter('i1', '<', 2));
    */

    final Query q2a = Query.atPath(ResourcePath.fromString('foo'));
    final Query q2b = Query.atPath(ResourcePath.fromString('foo'));

    final Query q3a = Query.atPath(ResourcePath.fromString('foo/bar'));
    final Query q3b = Query.atPath(ResourcePath.fromString('foo/bar'));

    final Query q4a = Query.atPath(ResourcePath.fromString('foo'))
        .orderBy(TestUtil.orderBy('foo'))
        .orderBy(TestUtil.orderBy('bar'));
    final Query q4b = Query.atPath(ResourcePath.fromString('foo'))
        .orderBy(TestUtil.orderBy('foo'))
        .orderBy(TestUtil.orderBy('bar'));

    final Query q5a = Query.atPath(ResourcePath.fromString('foo'))
        .orderBy(TestUtil.orderBy('bar'))
        .orderBy(TestUtil.orderBy('foo'));

    final Query q6a = Query.atPath(ResourcePath.fromString('foo'))
        .filter(TestUtil.filter('bar', '>', 2))
        .orderBy(TestUtil.orderBy('bar'));

    final Query q7a = Query.atPath(ResourcePath.fromString('foo')).limit(10);

    // TODO: Add test cases with{Lower,Upper}Bound once cursors are implemented.
    TestUtil.testEquality(<List<int>>[
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
    final Query baseQuery = Query.atPath(TestUtil.path('foo'));
    // Default is ascending
    expect(baseQuery.getOrderBy(),
        <OrderBy>[TestUtil.orderBy(DocumentKey.keyFieldName, 'asc')]);

    // Explicit key ordering is respected
    expect(
        baseQuery
            .orderBy(TestUtil.orderBy(DocumentKey.keyFieldName, 'asc'))
            .getOrderBy(),
        <OrderBy>[TestUtil.orderBy(DocumentKey.keyFieldName, 'asc')]);
    expect(
        baseQuery
            .orderBy(TestUtil.orderBy(DocumentKey.keyFieldName, 'desc'))
            .getOrderBy(),
        <OrderBy>[TestUtil.orderBy(DocumentKey.keyFieldName, 'desc')]);
    expect(
        baseQuery
            .orderBy(TestUtil.orderBy('foo'))
            .orderBy(TestUtil.orderBy(DocumentKey.keyFieldName, 'asc'))
            .getOrderBy(),
        <OrderBy>[
          TestUtil.orderBy('foo'),
          TestUtil.orderBy(DocumentKey.keyFieldName, 'asc')
        ]);
    expect(
        baseQuery
            .orderBy(TestUtil.orderBy('foo'))
            .orderBy(TestUtil.orderBy(DocumentKey.keyFieldName, 'desc'))
            .getOrderBy(),
        <OrderBy>[
          TestUtil.orderBy('foo'),
          TestUtil.orderBy(DocumentKey.keyFieldName, 'desc')
        ]);

    // Inequality filters add order bys
    expect(
        baseQuery.filter(TestUtil.filter('foo', '<', 5)).getOrderBy(),
        <OrderBy>[
          TestUtil.orderBy('foo'),
          TestUtil.orderBy(DocumentKey.keyFieldName, 'asc')
        ]);

    // Descending order by applies to implicit key ordering
    expect(
        baseQuery.orderBy(TestUtil.orderBy('foo', 'desc')).getOrderBy(),
        <OrderBy>[
          TestUtil.orderBy('foo', 'desc'),
          TestUtil.orderBy(DocumentKey.keyFieldName, 'desc')
        ]);
    expect(
        baseQuery
            .orderBy(TestUtil.orderBy('foo', 'asc'))
            .orderBy(TestUtil.orderBy('bar', 'desc'))
            .getOrderBy(),
        <OrderBy>[
          TestUtil.orderBy('foo', 'asc'),
          TestUtil.orderBy('bar', 'desc'),
          TestUtil.orderBy(DocumentKey.keyFieldName, 'desc')
        ]);
    expect(
        baseQuery
            .orderBy(TestUtil.orderBy('foo', 'desc'))
            .orderBy(TestUtil.orderBy('bar', 'asc'))
            .getOrderBy(),
        <OrderBy>[
          TestUtil.orderBy('foo', 'desc'),
          TestUtil.orderBy('bar', 'asc'),
          TestUtil.orderBy(DocumentKey.keyFieldName, 'asc')
        ]);
  });
}
