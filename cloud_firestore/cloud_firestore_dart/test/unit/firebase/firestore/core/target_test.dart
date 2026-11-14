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

import 'package:cloud_firestore_dart/src/firebase/firestore/core/filter/filter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/target.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';

/// The parts of upstream core/TargetTest that apply without a field index
/// engine: Targets with (composite) filters.
void main() {
  Target orTarget() => query('coll')
      .filter(orFilters(<Filter>[
        filter('a', '==', 1),
        andFilters(<Filter>[filter('b', '>', 2), filter('c', '==', 3)]),
      ]))
      .toTarget();

  test('target canonical id includes composite filters', () {
    expect(orTarget().canonicalId,
        'coll|f:or(a==1,b>2,c==3)|ob:basc,__name__asc');
  });

  test('targets with equal composite filters are equal', () {
    expect(orTarget(), orTarget());
    expect(orTarget().hashCode, orTarget().hashCode);
    expect(
        orTarget(),
        isNot(query('coll')
            .filter(orFilters(<Filter>[
              filter('a', '==', 1),
              andFilters(<Filter>[filter('b', '>', 2), filter('c', '==', 4)]),
            ]))
            .toTarget()));
    expect(
        orTarget(),
        isNot(query('coll')
            .filter(andFilters(<Filter>[
              filter('a', '==', 1),
              andFilters(<Filter>[filter('b', '>', 2), filter('c', '==', 3)]),
            ]))
            .toTarget()));
  });

  test('a composite filter is not a document query filter', () {
    final Target target = Target(path('coll/doc'),
        filters: <Filter>[orFilters(<Filter>[filter('a', '==', 1)])]);
    expect(target.isDocumentQuery, isFalse);
    expect(Target(path('coll/doc')).isDocumentQuery, isTrue);
  });

  test('toString lists the filters of a target', () {
    expect(query('coll')
            .filter(filter('a', '==', 1))
            .filter(orFilters(<Filter>[filter('b', '==', 2), filter('c', '==', 3)]))
            .toTarget()
            .toString(),
        contains('where a == 1 and or {b == 2, c == 3}'));
  });
}
