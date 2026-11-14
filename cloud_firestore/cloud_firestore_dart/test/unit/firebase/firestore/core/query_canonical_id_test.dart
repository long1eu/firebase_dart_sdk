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
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/geo_point.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:test/test.dart';

import '../../../../util/core_helpers.dart';
import '../../../../util/test_util.dart';

/// Ported from the JS SDK test/unit/core/query.test.ts 'canonical ids are
/// stable' (Android QueryTest.testCanonicalIdsAreStable). The persisted id is
/// the one of the Target (key of the target cache); Query.canonicalId adds a
/// `|lt:` suffix. The strings are the ones of the JS SDK.
void main() {
  final Query baseQuery = Query(ResourcePath.fromString('collection'));

  final Map<String, List<dynamic>> cases = <String, List<dynamic>>{
    'base query': <dynamic>[baseQuery, 'collection|f:|ob:__name__asc'],
    'greater than string': <dynamic>[
      baseQuery.filter(filter('a', '>', 'a')),
      'collection|f:a>a|ob:aasc,__name__asc',
    ],
    'geo point': <dynamic>[
      baseQuery.filter(filter('a', '<=', const GeoPoint(90.0, -90.0))),
      'collection|f:a<=geo(90,-90)|ob:aasc,__name__asc',
    ],
    'timestamp': <dynamic>[
      baseQuery.filter(filter('a', '<=', const Timestamp(60, 3000))),
      'collection|f:a<=time(60,3000)|ob:aasc,__name__asc',
    ],
    'blob': <dynamic>[
      baseQuery.filter(filter('a', '>=', blob(<int>[1, 2, 3]))),
      'collection|f:a>=AQID|ob:aasc,__name__asc',
    ],
    'equal array': <dynamic>[
      baseQuery.filter(filter('a', '==', <int>[1, 2, 3])),
      'collection|f:a==[1,2,3]|ob:__name__asc',
    ],
    'not equal array': <dynamic>[
      baseQuery.filter(filter('a', '!=', <int>[1, 2, 3])),
      'collection|f:a!=[1,2,3]|ob:aasc,__name__asc',
    ],
    'nan': <dynamic>[
      baseQuery.filter(filter('a', '==', double.nan)),
      'collection|f:a==NaN|ob:__name__asc',
    ],
    'key reference': <dynamic>[
      baseQuery.filter(filter('__name__', '==', ref('collection/id'))),
      'collection|f:__name__==collection/id|ob:__name__asc',
    ],
    'nested map': <dynamic>[
      baseQuery.filter(
        filter('a', '==', <String, Object>{
          'a': 'b',
          'inner': <String, Object>{'d': 'c'},
        }),
      ),
      'collection|f:a=={a:b,inner:{d:c}}|ob:__name__asc',
    ],
    'in': <dynamic>[
      baseQuery.filter(filter('a', 'in', <int>[1, 2, 3])),
      'collection|f:ain[1,2,3]|ob:__name__asc',
    ],
    'not-in': <dynamic>[
      baseQuery.filter(filter('a', 'not-in', <int>[1, 2, 3])),
      'collection|f:anot-in[1,2,3]|ob:aasc,__name__asc',
    ],
    'array-contains-any': <dynamic>[
      baseQuery.filter(filter('a', 'array-contains-any', <int>[1, 2, 3])),
      'collection|f:aarray-contains-any[1,2,3]|ob:__name__asc',
    ],
    'array-contains': <dynamic>[
      baseQuery.filter(filter('a', 'array-contains', 'a')),
      'collection|f:aarray-containsa|ob:__name__asc',
    ],
    'order by': <dynamic>[
      baseQuery.orderBy(orderBy('a')),
      'collection|f:|ob:aasc,__name__asc',
    ],
    'start at': <dynamic>[
      baseQuery
          .orderBy(orderBy('a'))
          .orderBy(orderBy('b'))
          .startAt(
            bound(true, <Object>[
              'foo',
              <int>[1, 2, 3],
            ]),
          ),
      'collection|f:|ob:aasc,basc,__name__asc|lb:b:foo,[1,2,3]',
    ],
    'end at': <dynamic>[
      baseQuery
          .orderBy(orderBy('a', 'desc'))
          .orderBy(orderBy('b', 'desc'))
          .endAt(
            bound(true, <Object>[
              'foo',
              <int>[1, 2, 3],
            ]),
          ),
      'collection|f:|ob:adesc,bdesc,__name__desc|ub:a:foo,[1,2,3]',
    ],
    'limit': <dynamic>[baseQuery.limit(5), 'collection|f:|ob:__name__asc|l:5'],
    'limit to last': <dynamic>[
      baseQuery.limitToLast(5),
      'collection|f:|ob:__name__desc|l:5',
    ],
  };

  group('testCanonicalIdsAreStable', () {
    cases.forEach((String name, List<dynamic> c) {
      test(name, () {
        expect((c[0] as Query).toTarget().canonicalId, c[1]);
      });
    });
  });

  test('query canonical id appends the limit type to the target id', () {
    // The JS `canonifyQuery`.
    expect(baseQuery.canonicalId, '${baseQuery.toTarget().canonicalId}|lt:F');
    expect(baseQuery.limitToLast(3).canonicalId, endsWith('|l:3|lt:L'));
  });

  test('canonical ids differ between filters on different operators', () {
    final Set<String> ids = <String>{
      for (final String op in <String>['<', '<=', '==', '!=', '>', '>='])
        baseQuery.filter(filter('a', op, 1)).canonicalId,
    };
    expect(ids.length, 6);
  });

  // The JS SDK test/unit/core/filter.test.ts.
  test('computes canonical id of flat conjunctions', () {
    final List<Filter> filters = <Filter>[
      filter('a', '==', 1),
      filter('b', '==', 2),
      filter('c', '==', 3),
    ];
    Query query1 = baseQuery;
    for (final Filter f in filters) {
      query1 = query1.filter(f);
    }
    final Query query2 = baseQuery.filter(andFilters(filters));
    expect(query1.canonicalId, query2.canonicalId);
    expect(
      query1.canonicalId,
      'collection|f:a==1,b==2,c==3|ob:__name__asc|lt:F',
    );
  });

  test('a disjunction names its operator', () {
    expect(
      baseQuery
          .filter(
            orFilters(<Filter>[filter('a', '==', 1), filter('b', '==', 2)]),
          )
          .toTarget()
          .canonicalId,
      'collection|f:or(a==1,b==2)|ob:__name__asc',
    );
  });
}
