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

import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/geo_point.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:test/test.dart';

import '../../../../util/core_helpers.dart';
import '../../../../util/test_util.dart';

/// Ported from upstream QueryTest.testCanonicalIdsAreStable. The persisted id
/// is the one of the Target (key of the target cache); Query.canonicalId adds
/// a `|lt:` suffix. The Dart format differs from upstream by design (never
/// changed to keep existing caches valid): filters are `field op value` with
/// spaces and values use their toString(); entries whose value rendering is a
/// multi-line toString are matched by prefix only.
void main() {
  final Query baseQuery = Query(ResourcePath.fromString('collection'));

  final Map<String, List<dynamic>> cases = <String, List<dynamic>>{
    'base query': <dynamic>[baseQuery, 'collection|f:|ob:__name__asc'],
    'greater than string': <dynamic>[
      baseQuery.filter(filter('a', '>', 'a')),
      'collection|f:a > a|ob:aasc__name__asc'
    ],
    'geo point': <dynamic>[
      baseQuery.filter(filter('a', '<=', const GeoPoint(90.0, -90.0))),
      startsWith('collection|f:a <= GeoPoint {')
    ],
    'timestamp': <dynamic>[
      baseQuery.filter(filter('a', '<=', const Timestamp(60, 3000))),
      startsWith('collection|f:a <= Timestamp {')
    ],
    'blob': <dynamic>[
      baseQuery.filter(filter('a', '>=', blob(<int>[1, 2, 3]))),
      'collection|f:a >= Blob { bytes= 010203 }|ob:aasc__name__asc'
    ],
    'equal array': <dynamic>[
      baseQuery.filter(filter('a', '==', <int>[1, 2, 3])),
      'collection|f:a == [1, 2, 3]|ob:__name__asc'
    ],
    'not equal array': <dynamic>[
      baseQuery.filter(filter('a', '!=', <int>[1, 2, 3])),
      'collection|f:a != [1, 2, 3]|ob:aasc__name__asc'
    ],
    'nan': <dynamic>[
      baseQuery.filter(filter('a', '==', double.nan)),
      'collection|f:a == NaN|ob:__name__asc'
    ],
    'key reference': <dynamic>[
      baseQuery.filter(filter('__name__', '==', ref('collection/id'))),
      startsWith('collection|f:__name__ == DocumentKey {')
    ],
    'nested map': <dynamic>[
      baseQuery.filter(filter('a', '==', <String, Object>{
        'a': 'b',
        'inner': <String, Object>{'d': 'c'}
      })),
      allOf(startsWith('collection|f:a == '), endsWith('|ob:__name__asc'))
    ],
    'in': <dynamic>[
      baseQuery.filter(filter('a', 'in', <int>[1, 2, 3])),
      'collection|f:a in [1, 2, 3]|ob:__name__asc'
    ],
    'not-in': <dynamic>[
      baseQuery.filter(filter('a', 'not-in', <int>[1, 2, 3])),
      'collection|f:a not_in [1, 2, 3]|ob:aasc__name__asc'
    ],
    'array-contains-any': <dynamic>[
      baseQuery.filter(filter('a', 'array-contains-any', <int>[1, 2, 3])),
      'collection|f:a array_contains_any [1, 2, 3]|ob:__name__asc'
    ],
    'array-contains': <dynamic>[
      baseQuery.filter(filter('a', 'array-contains', 'a')),
      'collection|f:a array_contains a|ob:__name__asc'
    ],
    'order by': <dynamic>[
      baseQuery.orderBy(orderBy('a')),
      'collection|f:|ob:aasc__name__asc'
    ],
    'start at': <dynamic>[
      baseQuery
          .orderBy(orderBy('a'))
          .startAt(bound(true, <Object>['foo', <int>[1, 2, 3]])),
      'collection|f:|ob:aasc__name__asc|lb:b:foo[1, 2, 3]'
    ],
    'end at': <dynamic>[
      baseQuery
          .orderBy(orderBy('a'))
          .endAt(bound(true, <Object>['foo', <int>[1, 2, 3]])),
      'collection|f:|ob:aasc__name__asc|ub:b:foo[1, 2, 3]'
    ],
    'limit': <dynamic>[baseQuery.limit(5), 'collection|f:|ob:__name__asc|l:5'],
  };

  group('testCanonicalIdsAreStable', () {
    cases.forEach((String name, List<dynamic> c) {
      test(name, () {
        expect((c[0] as Query).toTarget().canonicalId, c[1]);
      });
    });
  });

  test('query canonical id appends the limit type to the target id', () {
    expect(baseQuery.canonicalId,
        '${baseQuery.toTarget().canonicalId}|lt:LIMIT_TO_FIRST');
    expect(baseQuery.limitToLast(3).canonicalId,
        endsWith('|l:3|lt:LIMIT_TO_LAST'));
  });

  test('canonical ids differ between filters on different operators', () {
    final Set<String> ids = <String>{
      for (final String op in <String>['<', '<=', '==', '!=', '>', '>='])
        baseQuery.filter(filter('a', op, 1)).canonicalId
    };
    expect(ids.length, 6);
  });
}
