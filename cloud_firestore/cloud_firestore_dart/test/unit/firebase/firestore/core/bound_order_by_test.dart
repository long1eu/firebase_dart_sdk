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

import 'package:cloud_firestore_dart/src/firebase/firestore/core/bound.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/order_by.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:test/test.dart';

import '../../../../util/core_helpers.dart';
import '../../../../util/test_util.dart';

/// Unit tests for [Bound], [OrderBy] and the cursor handling of [Query]. The
/// upstream unit tests at the sync point only have a TODO for cursors in
/// QueryTest (they were covered by the integration CursorTest); these cover
/// the same semantics deterministically without a backend.
void main() {
  Document d(int n, Object? a, [Object? b]) => doc(
      'collection/$n',
      0,
      b == null
          ? map<Object?>(<Object?>['a', a])
          : map<Object?>(<Object?>['a', a, 'b', b]));

  final List<Document> docs = <Document>[
    d(1, 1),
    d(2, 2),
    d(3, 3),
    d(4, 4),
    d(5, 5),
  ];

  List<String> ids(Query q) => docs
      .where(q.matches)
      .toList()
      .map((Document doc) => doc.key.path.last)
      .toList();

  final Query base = query('collection').orderBy(orderBy('a'));

  group('Bound', () {
    test('canonicalString distinguishes before/after', () {
      expect(bound(true, <Object>[1]).canonicalString(), startsWith('b:'));
      expect(bound(false, <Object>[1]).canonicalString(), startsWith('a:'));
    });

    test('equality and hashCode', () {
      expect(bound(true, <Object>[1, 'x']), bound(true, <Object>[1, 'x']));
      expect(bound(true, <Object>[1, 'x']).hashCode,
          bound(true, <Object>[1, 'x']).hashCode);
      expect(bound(true, <Object>[1]), isNot(bound(false, <Object>[1])));
      expect(bound(true, <Object>[1]), isNot(bound(true, <Object>[2])));
      expect(bound(true, <Object>[1]), isNot(bound(true, <Object>[1, 2])));
    });

    test('sortsBeforeDocument honours before flag', () {
      final List<OrderBy> order = <OrderBy>[orderBy('a')];
      final Document doc3 = d(3, 3);
      expect(bound(true, <Object>[3]).sortsBeforeDocument(order, doc3), isTrue);
      expect(
          bound(false, <Object>[3]).sortsBeforeDocument(order, doc3), isFalse);
      expect(bound(true, <Object>[2]).sortsBeforeDocument(order, doc3), isTrue);
      expect(
          bound(false, <Object>[2]).sortsBeforeDocument(order, doc3), isTrue);
      expect(
          bound(true, <Object>[4]).sortsBeforeDocument(order, doc3), isFalse);
      expect(
          bound(false, <Object>[4]).sortsBeforeDocument(order, doc3), isFalse);
    });

    test('sortsBeforeDocument respects descending order', () {
      final List<OrderBy> order = <OrderBy>[orderBy('a', 'desc')];
      final Document doc3 = d(3, 3);
      expect(bound(true, <Object>[4]).sortsBeforeDocument(order, doc3), isTrue);
      expect(
          bound(true, <Object>[2]).sortsBeforeDocument(order, doc3), isFalse);
    });

    test('sortsBeforeDocument compares on the document key', () {
      final List<OrderBy> order = <OrderBy>[orderBy('__name__')];
      final Document doc3 = d(3, 3);
      expect(
          Bound(
                  position: <dynamic>[wrap(ref('collection/3'))].cast(),
                  before: true)
              .sortsBeforeDocument(order, doc3),
          isTrue);
      expect(
          Bound(
                  position: <dynamic>[wrap(ref('collection/3'))].cast(),
                  before: false)
              .sortsBeforeDocument(order, doc3),
          isFalse);
      expect(
          Bound(
                  position: <dynamic>[wrap(ref('collection/4'))].cast(),
                  before: true)
              .sortsBeforeDocument(order, doc3),
          isFalse);
    });

    test('uses later order-by components to break ties', () {
      final List<OrderBy> order = <OrderBy>[orderBy('a'), orderBy('b')];
      final Document doc = d(1, 1, 5);
      expect(
          bound(true, <Object>[1, 5]).sortsBeforeDocument(order, doc), isTrue);
      expect(bound(false, <Object>[1, 5]).sortsBeforeDocument(order, doc),
          isFalse);
      expect(
          bound(true, <Object>[1, 6]).sortsBeforeDocument(order, doc), isFalse);
      expect(
          bound(true, <Object>[1, 4]).sortsBeforeDocument(order, doc), isTrue);
    });
  });

  group('Query cursors', () {
    test('startAt is inclusive', () {
      expect(
          ids(base.startAt(bound(true, <Object>[3]))), <String>['3', '4', '5']);
    });

    test('startAfter is exclusive', () {
      expect(ids(base.startAt(bound(false, <Object>[3]))), <String>['4', '5']);
    });

    test('endBefore is exclusive', () {
      expect(ids(base.endAt(bound(true, <Object>[3]))), <String>['1', '2']);
    });

    test('endAt is inclusive', () {
      expect(
          ids(base.endAt(bound(false, <Object>[3]))), <String>['1', '2', '3']);
    });

    test('start and end bounds combine', () {
      expect(
          ids(base
              .startAt(bound(true, <Object>[2]))
              .endAt(bound(false, <Object>[4]))),
          <String>['2', '3', '4']);
      expect(
          ids(base
              .startAt(bound(false, <Object>[2]))
              .endAt(bound(true, <Object>[4]))),
          <String>['3']);
    });

    test('bounds in descending order', () {
      final Query desc = query('collection').orderBy(orderBy('a', 'desc'));
      expect(
          ids(desc.startAt(bound(true, <Object>[3]))), <String>['1', '2', '3']);
      expect(
          ids(desc.endAt(bound(false, <Object>[3]))), <String>['3', '4', '5']);
    });

    test('bounds are part of equality, hashCode and canonical id', () {
      final Query q1 = base.startAt(bound(true, <Object>[3]));
      final Query q2 = base.startAt(bound(true, <Object>[3]));
      final Query q3 = base.startAt(bound(false, <Object>[3]));
      final Query q4 = base.endAt(bound(true, <Object>[3]));
      expect(q1, q2);
      expect(q1.hashCode, q2.hashCode);
      expect(q1.canonicalId, q2.canonicalId);
      expect(q1, isNot(q3));
      expect(q1, isNot(q4));
      expect(q1, isNot(base));
      expect(q1.canonicalId, isNot(q3.canonicalId));
      expect(q1.canonicalId, isNot(q4.canonicalId));
      expect(q1.canonicalId, contains('|lb:'));
      expect(q4.canonicalId, contains('|ub:'));
    });

    test('limit is part of equality and canonical id', () {
      expect(base.limit(2), base.limit(2));
      expect(base.limit(2), isNot(base.limit(3)));
      expect(base.limit(2).canonicalId, contains('|l:2'));
      expect(base.limit(2).canonicalId, isNot(base.limit(3).canonicalId));
      expect(base.limit(2).canonicalId, isNot(base.canonicalId));
      expect(base.limit(2).getLimit(), 2);
      expect(base.hasLimit, isFalse);
      expect(base.limit(2).hasLimit, isTrue);
    });
  });

  group('OrderBy', () {
    test('compare ascending and descending', () {
      final Document a = d(1, 1);
      final Document b = d(2, 2);
      expect(orderBy('a').compare(a, b), lessThan(0));
      expect(orderBy('a').compare(b, a), greaterThan(0));
      expect(orderBy('a').compare(a, a), 0);
      expect(orderBy('a', 'desc').compare(a, b), greaterThan(0));
      expect(orderBy('a', 'desc').compare(b, a), lessThan(0));
    });

    test('compare on key', () {
      expect(orderBy('__name__').compare(d(1, 9), d(2, 1)), lessThan(0));
      expect(orderBy('__name__', 'desc').compare(d(1, 9), d(2, 1)),
          greaterThan(0));
    });

    test('equality, hashCode and toString', () {
      expect(orderBy('a'), orderBy('a'));
      expect(orderBy('a').hashCode, orderBy('a').hashCode);
      expect(orderBy('a'), isNot(orderBy('a', 'desc')));
      expect(orderBy('a'), isNot(orderBy('b')));
      expect(orderBy('a').toString(), 'a');
      expect(orderBy('a', 'desc').toString(), '-a');
    });

    test('OrderByDirection equality', () {
      expect(OrderByDirection.ascending, OrderByDirection.ascending);
      expect(OrderByDirection.ascending, isNot(OrderByDirection.descending));
    });
  });
}
