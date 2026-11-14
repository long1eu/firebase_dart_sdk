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

import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/blob.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bson_object_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bson_timestamp.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/filter/filter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/target.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/decimal128_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/distance_measure.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/int32_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/max_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/min_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query.dart' as api;
import 'package:cloud_firestore_dart/src/firebase/firestore/regex_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/vector_query.dart';
import 'package:test/test.dart';

import '../../../../util/core_helpers.dart';
import '../../../../util/test_util.dart';
import '../test_util.dart' show firestore;

/// Canonical ids and equality of queries and targets compared with Android
/// (core/Target.java#getCanonicalId, Query.java#equals) and JS
/// (canonifyTarget, canonifyQuery, queryEquals).
///
/// The persisted canonical-id format is pinned here on purpose: it is the key
/// of the target cache. The ids are the ones of the JS SDK. The canonical id
/// only has to be a good hash: the target cache and the sync engine compare
/// targets with `==` after the lookup, so equality is what has to match
/// upstream.
void main() {
  final Query base = query('collection');

  String targetId(Query q) => q.toTarget().canonicalId;

  void expectSameQuery(Query a, Query b) {
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a.toTarget(), b.toTarget());
    expect(a.toTarget().hashCode, b.toTarget().hashCode);
  }

  group('BSON values', () {
    // Android QueryTest.testCanonicalIdsAreStable, "BSON types". The ids are
    // the upstream ones.
    final Map<String, List<Object>> cases = <String, List<Object>>{
      'object id': <Object>[
        const BsonObjectId('foo'),
        'collection|f:a<={__oid__:foo}|ob:aasc,__name__asc',
      ],
      'bson timestamp': <Object>[
        BsonTimestamp(1, 2),
        'collection|f:a<={__request_timestamp__:{increment:2,seconds:1}}|ob:aasc,__name__asc',
      ],
      'regex': <Object>[
        const RegexValue('^foo', 'i'),
        'collection|f:a<={__regex__:{options:i,pattern:^foo}}|ob:aasc,__name__asc',
      ],
      'int32': <Object>[
        Int32Value(1),
        'collection|f:a<={__int__:1}|ob:aasc,__name__asc',
      ],
      'decimal128': <Object>[
        Decimal128Value('1.2e3'),
        'collection|f:a<={__decimal128__:1.2e3}|ob:aasc,__name__asc',
      ],
      'min key': <Object>[
        MinKey.instance,
        'collection|f:a<={__min__:null}|ob:aasc,__name__asc',
      ],
      'max key': <Object>[
        MaxKey.instance,
        'collection|f:a<={__max__:null}|ob:aasc,__name__asc',
      ],
      // Android: 'collection|f:a<={__binary__:01010203}|ob:aasc,__name__asc'.
      'bson binary': <Object>[
        Blob.bsonBinary(1, Uint8List.fromList(<int>[1, 2, 3])),
        'collection|f:a<={__binary__:AQECAw==}|ob:aasc,__name__asc',
      ],
    };
    for (final MapEntry<String, List<Object>> c in cases.entries) {
      test(c.key, () {
        expect(
          targetId(base.filter(filter('a', '<=', c.value[0]))),
          c.value[1],
        );
      });
    }

    test('BSON values of different types give different queries', () {
      final List<Query> queries = <Query>[
        for (final List<Object> c in cases.values)
          base.filter(filter('a', '<=', c[0])),
        base.filter(filter('a', '<=', 1)),
      ];
      for (int i = 0; i < queries.length; i++) {
        for (int j = 0; j < queries.length; j++) {
          expect(queries[i] == queries[j], i == j, reason: '$i vs $j');
          expect(
            queries[i].canonicalId == queries[j].canonicalId,
            i == j,
            reason: '$i vs $j',
          );
        }
      }
    });

    test('a BSON binary of subtype 0 is a plain blob', () {
      expectSameQuery(
        base.filter(filter('a', '==', Blob(Uint8List.fromList(<int>[1])))),
        base.filter(
          filter('a', '==', Blob.bsonBinary(0, Uint8List.fromList(<int>[1]))),
        ),
      );
    });
  });

  group('numbers', () {
    // Dart follows JS numberEquals (type-strict, -0.0 != 0.0, NaN == NaN).
    // Android's current Values.equals compares numbers numerically
    // (compareNumbers == 0), so there `a == 1` equals `a == 1.0`.
    Query eq(Object? value) => base.filter(filter('a', '==', value));

    test('NaN equals NaN', () {
      expectSameQuery(eq(double.nan), eq(double.nan));
      expect(targetId(eq(double.nan)), 'collection|f:a==NaN|ob:__name__asc');
    });

    test('an integer and a double are different values', () {
      expect(eq(1), isNot(eq(1.0)));
      expect(targetId(eq(1)), 'collection|f:a==1|ob:__name__asc');
      // As in JS, where both are the number 1, they share the canonical id.
      expect(targetId(eq(1.0)), 'collection|f:a==1|ob:__name__asc');
    });

    test('0.0 and -0.0 are different values', () {
      expect(eq(0.0), isNot(eq(-0.0)));
      // As in JS (`'' + -0` is '0'), they share the canonical id.
      expect(eq(0.0).canonicalId, eq(-0.0).canonicalId);
    });

    test('int32 and decimal128 differ from an integer of the same value', () {
      expect(eq(Int32Value(1)), isNot(eq(1)));
      expect(eq(Decimal128Value('1')), isNot(eq(1)));
    });

    test('decimal128 values are equal by number, not by spelling', () {
      // Equal queries with different canonical ids only cost a target cache
      // miss; upstream (JS compareQuadruples) has the same behaviour.
      expectSameQuery(eq(Decimal128Value('1.0')), eq(Decimal128Value('1')));
      expect(
        eq(Decimal128Value('1.0')).canonicalId,
        isNot(eq(Decimal128Value('1')).canonicalId),
      );
    });

    test('a string and a number with the same spelling collide', () {
      // Upstream TODO(b/29183165): the canonical id does not carry the type.
      expect(eq('3').canonicalId, eq(3).canonicalId);
      expect(eq('3'), isNot(eq(3)));
    });
  });

  group('OR filters', () {
    final Filter a = filter('a', '==', 1);
    final Filter b = filter('b', '>', 2);

    test('canonical id', () {
      // Android: 'collection|f:or(a==1,b>2)|ob:basc,__name__asc'.
      expect(
        targetId(base.filter(orFilters(<Filter>[a, b]))),
        'collection|f:or(a==1,b>2)|ob:basc,__name__asc',
      );
    });

    test('equality depends on the order of the terms', () {
      final Query ab = base.filter(orFilters(<Filter>[a, b]));
      expectSameQuery(ab, base.filter(orFilters(<Filter>[a, b])));
      expect(ab, isNot(base.filter(orFilters(<Filter>[b, a]))));
      expect(
        ab.canonicalId,
        isNot(base.filter(orFilters(<Filter>[b, a])).canonicalId),
      );
    });

    test('OR and AND of the same terms differ', () {
      expect(
        base.filter(orFilters(<Filter>[a, b])),
        isNot(base.filter(andFilters(<Filter>[a, b]))),
      );
    });

    test('an explicit AND equals the chained filters', () {
      // Upstream keeps the AND as one CompositeFilter, so the queries have the
      // same canonical id but are not equal. The port adds the terms of an
      // AND to the implicit conjunction (Query.filter), so they are equal.
      final Query chained = base.filter(a).filter(b);
      final Query explicit = base.filter(andFilters(<Filter>[a, b]));
      expect(explicit.canonicalId, chained.canonicalId);
      expectSameQuery(explicit, chained);
    });
  });

  group('collection group', () {
    test('canonical id', () {
      final Query q = Query(
        path(''),
        collectionGroup: 'cg',
      ).filter(filter('a', '==', 1));
      expect(targetId(q), '|cg:cg|f:a==1|ob:__name__asc');
      expect(q.canonicalId, '|cg:cg|f:a==1|ob:__name__asc|lt:F');
    });

    test('differs from a collection query and from other groups', () {
      final Query group = Query(path(''), collectionGroup: 'x');
      expectSameQuery(group, Query(path(''), collectionGroup: 'x'));
      expect(group, isNot(query('x')));
      expect(group.canonicalId, isNot(query('x').canonicalId));
      expect(group, isNot(Query(path(''), collectionGroup: 'y')));
    });

    test('asCollectionQueryAtPath drops the group', () {
      final Query group = Query(path(''), collectionGroup: 'x');
      expectSameQuery(
        group.asCollectionQueryAtPath(path('a/b/x')),
        query('a/b/x'),
      );
    });
  });

  group('limitToLast', () {
    test('canonical id flips the orderings and swaps the cursors', () {
      final Query q = base
          .orderBy(orderBy('a'))
          .startAt(bound(true, <Object>['s']))
          .endAt(bound(false, <Object>['e']))
          .limitToLast(2);
      // The target is the one of the mirrored limitToFirst query.
      expect(
        targetId(q),
        'collection|f:|ob:adesc,__name__desc|l:2|lb:a:e|ub:a:s',
      );
      // JS appends `|lt:L` (Android `|lt:LIMIT_TO_LAST`).
      expect(q.canonicalId, '${targetId(q)}|lt:L');
    });

    test('mirror queries share the target but are different queries', () {
      final Query last = base.orderBy(orderBy('a')).limitToLast(2);
      final Query first = base.orderBy(orderBy('a', 'desc')).limitToFirst(2);
      expect(last.toTarget(), first.toTarget());
      expect(last.toTarget().hashCode, first.toTarget().hashCode);
      expect(last, isNot(first));
      expect(last.canonicalId, isNot(first.canonicalId));
    });
  });

  group('bounds', () {
    test('positions are separated by a comma', () {
      // As Android and JS ('lb:b:foo,[1,2,3]'): ['ab'] and ['a', 'b'] have
      // different ids.
      final Query one = base
          .orderBy(orderBy('a'))
          .startAt(bound(true, <Object>['ab']));
      final Query two = base
          .orderBy(orderBy('a'))
          .startAt(bound(true, <Object>['a', 'b']));
      expect(targetId(one), 'collection|f:|ob:aasc,__name__asc|lb:b:ab');
      expect(targetId(two), 'collection|f:|ob:aasc,__name__asc|lb:b:a,b');
      expect(one.toTarget(), isNot(two.toTarget()));
      expect(one, isNot(two));
    });

    test('inclusive and exclusive bounds differ', () {
      final Query q = base.orderBy(orderBy('a'));
      final List<Query> queries = <Query>[
        q.startAt(bound(true, <Object>[1])),
        q.startAt(bound(false, <Object>[1])),
        q.endAt(bound(true, <Object>[1])),
        q.endAt(bound(false, <Object>[1])),
      ];
      for (int i = 0; i < queries.length; i++) {
        for (int j = 0; j < queries.length; j++) {
          expect(queries[i] == queries[j], i == j);
          expect(targetId(queries[i]) == targetId(queries[j]), i == j);
        }
      }
    });
  });

  group('findNearest', () {
    api.Query<Map<String, Object?>> apiQuery(Query q) =>
        api.QueryInternal.create<Map<String, Object?>>(q, firestore);

    VectorQuery nearest(Query q, {int limit = 3, double? threshold}) =>
        apiQuery(q).findNearest(
          'v',
          <double>[1.0, 2.0],
          limit,
          DistanceMeasure.cosine,
          distanceThreshold: threshold,
        );

    test('equal vector queries over equal base queries', () {
      final VectorQuery a = nearest(base.filter(filter('x', '==', 1)));
      final VectorQuery b = nearest(base.filter(filter('x', '==', 1)));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('every option is part of the equality', () {
      final VectorQuery a = nearest(base);
      expect(a, isNot(nearest(base, limit: 4)));
      expect(a, isNot(nearest(base, threshold: 0.5)));
      expect(a, isNot(nearest(base.filter(filter('x', '==', 1)))));
      expect(
        a,
        isNot(
          apiQuery(
            base,
          ).findNearest('v', <double>[1.0, 2.0], 3, DistanceMeasure.euclidean),
        ),
      );
      expect(
        a,
        isNot(
          apiQuery(
            base,
          ).findNearest('w', <double>[1.0, 2.0], 3, DistanceMeasure.cosine),
        ),
      );
      expect(
        a,
        isNot(
          apiQuery(
            base,
          ).findNearest('v', <double>[1.0, 3.0], 3, DistanceMeasure.cosine),
        ),
      );
    });

    test('the aggregate target of the base query drops implicit orderings', () {
      final Query q = base.filter(filter('x', '>', 1)).orderBy(orderBy('y'));
      final Target target = q.toAggregateTarget();
      expect(target.orderBy, <Object>[orderBy('y')]);
      expect(target.canonicalId, 'collection|f:x>1|ob:yasc');
      expect(target, isNot(q.toTarget()));
    });
  });
}
