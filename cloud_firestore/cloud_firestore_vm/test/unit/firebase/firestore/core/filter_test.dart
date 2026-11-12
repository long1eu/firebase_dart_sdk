// Copyright 2022 Google LLC
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

import 'package:cloud_firestore_vm/src/firebase/firestore/core/filter/filter.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/query.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';

/// Port of upstream core/FilterTest (the composite filter parts).
void main() {
  // Helper to get unique filters.
  FieldFilter nameFilter(String name) => filter('name', '==', name);

  final FieldFilter a = nameFilter('A');
  final FieldFilter b = nameFilter('B');
  final FieldFilter c = nameFilter('C');
  final FieldFilter d = nameFilter('D');

  test('testFieldFilterMembers', () {
    final FieldFilter f = filter('foo', '==', 'bar');
    expect(f.field.toString(), 'foo');
    expect(f.value, wrap('bar'));
    expect(f.operator, FilterOperator.equal);
    expect(f.filters, <Filter>[f]);
    expect(f.flattenedFilters, <FieldFilter>[f]);
  });

  test('testCompositeFilterMembers', () {
    final CompositeFilter andFilter = andFilters(<Filter>[a, b, c]);
    expect(andFilter.isConjunction, isTrue);
    expect(andFilter.filters, <Filter>[a, b, c]);

    final CompositeFilter orFilter = orFilters(<Filter>[a, b, c]);
    expect(orFilter.isDisjunction, isTrue);
    expect(orFilter.filters, <Filter>[a, b, c]);
  });

  test('testCompositeFilterNestedChecks', () {
    final CompositeFilter andFilter1 = andFilters(<Filter>[a, b, c]);
    expect(andFilter1.isFlat, isTrue);
    expect(andFilter1.isConjunction, isTrue);
    expect(andFilter1.isDisjunction, isFalse);
    expect(andFilter1.isFlatConjunction, isTrue);

    final CompositeFilter orFilter1 = orFilters(<Filter>[a, b, c]);
    expect(orFilter1.isConjunction, isFalse);
    expect(orFilter1.isDisjunction, isTrue);
    expect(orFilter1.isFlat, isTrue);
    expect(orFilter1.isFlatConjunction, isFalse);

    final CompositeFilter andFilter2 = andFilters(<Filter>[d, andFilter1]);
    expect(andFilter2.isConjunction, isTrue);
    expect(andFilter2.isDisjunction, isFalse);
    expect(andFilter2.isFlat, isFalse);
    expect(andFilter2.isFlatConjunction, isFalse);

    final CompositeFilter orFilter2 = orFilters(<Filter>[d, andFilter1]);
    expect(orFilter2.isConjunction, isFalse);
    expect(orFilter2.isDisjunction, isTrue);
    expect(orFilter2.isFlat, isFalse);
    expect(orFilter2.isFlatConjunction, isFalse);
  });

  test('testCanonicalIdOfFlatConjunctions', () {
    final Query q1 = query('col').filter(a).filter(b).filter(c);
    final Query q2 = query('col').filter(andFilters(<Filter>[a, b, c]));
    expect(q1.canonicalId, q2.canonicalId);
  });

  test('flattenedFilters returns the nested field filters in order', () {
    final CompositeFilter nested = orFilters(<Filter>[
      a,
      andFilters(<Filter>[b, orFilters(<Filter>[c, d])]),
    ]);
    expect(nested.flattenedFilters, <FieldFilter>[a, b, c, d]);
    expect(nested.filters.length, 2);
  });

  test('composite filter equality and hashCode', () {
    expect(andFilters(<Filter>[a, b]), andFilters(<Filter>[a, b]));
    expect(andFilters(<Filter>[a, b]).hashCode,
        andFilters(<Filter>[a, b]).hashCode);
    // The order of the filters matters.
    expect(andFilters(<Filter>[a, b]), isNot(andFilters(<Filter>[b, a])));
    expect(andFilters(<Filter>[a, b]), isNot(orFilters(<Filter>[a, b])));
    expect(andFilters(<Filter>[a, b]), isNot(andFilters(<Filter>[a])));
  });

  test('composite filter canonical id', () {
    expect(andFilters(<Filter>[a, b]).canonicalId,
        '${a.canonicalId}${b.canonicalId}');
    expect(orFilters(<Filter>[a, b]).canonicalId,
        'or(${a.canonicalId},${b.canonicalId})');
    expect(
        andFilters(<Filter>[a, orFilters(<Filter>[b, c])]).canonicalId,
        'and(${a.canonicalId},or(${b.canonicalId},${c.canonicalId}))');
  });

  test('composite filter matches documents', () {
    final Filter f = orFilters(<Filter>[
      filter('a', '==', 1),
      andFilters(<Filter>[filter('b', '>', 1), filter('c', '==', 'x')]),
    ]);
    expect(f.matches(doc('c/1', 0, map(<dynamic>['a', 1]))), isTrue);
    expect(f.matches(doc('c/2', 0, map(<dynamic>['b', 2, 'c', 'x']))), isTrue);
    expect(f.matches(doc('c/3', 0, map(<dynamic>['b', 2, 'c', 'y']))), isFalse);
    expect(f.matches(doc('c/4', 0, map(<dynamic>['a', 2]))), isFalse);
  });
}
