// Properties of canonical ids. They identify a target in the local store and
// are persisted, so equal targets need equal ids, different targets
// different ids, and an id must not change between releases.

import 'dart:typed_data';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart' as api;
import 'package:cloud_firestore_dart/src/firebase/firestore/core/bound.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/filter/filter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/order_by.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/target.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:test/test.dart';

import '../../util/property.dart';
import '../../util/property_model.dart';

void main() {
  test('equal targets have equal canonical ids and hash codes', () {
    forAll<List<Query>>(
      'equal targets',
      count: cases(400),
      // The same query, generated twice.
      generate: (Gen gen) => <Query>[
        Gen(gen.seed, size: gen.size).query(),
        Gen(gen.seed, size: gen.size).query(),
      ],
      show: (List<Query> queries) => queries.first.toTarget().canonicalId,
      check: (List<Query> queries) {
        final Target a = queries[0].toTarget();
        final Target b = queries[1].toTarget();
        expect(a, b);
        expect(a.hashCode, b.hashCode);
        expect(a.canonicalId, b.canonicalId);
        expect(queries[0], queries[1]);
        expect(queries[0].hashCode, queries[1].hashCode);
        expect(queries[0].canonicalId, queries[1].canonicalId);
      },
    );
  });

  test('targets with equal canonical ids are equal', () {
    // Many small targets, so that near misses (same filter, other value type)
    // are likely.
    final Map<String, Target> byId = <String, Target>{};
    forAll<Query>(
      'different targets',
      count: cases(3000),
      generate: (Gen gen) => Gen(gen.seed, size: gen.size.clamp(0, 2)).query(),
      show: (Query query) => query.toTarget().canonicalId,
      check: (Query query) {
        final Target target = query.toTarget();
        final Target other = byId.putIfAbsent(
          target.canonicalId,
          () => target,
        );
        if (other != target) {
          fail(
            'Two different targets share the canonical id '
            '${target.canonicalId}\n    $target\n    $other',
          );
        }
      },
    );
  });

  test('queries with equal canonical ids are equal', () {
    final Map<String, Query> byId = <String, Query>{};
    forAll<Query>(
      'different queries',
      count: cases(3000),
      generate: (Gen gen) => Gen(gen.seed, size: gen.size.clamp(0, 2)).query(),
      show: (Query query) => query.canonicalId,
      check: (Query query) {
        final Query other = byId.putIfAbsent(query.canonicalId, () => query);
        if (other != query) {
          fail(
            'Two different queries share the canonical id '
            '${query.canonicalId}\n    $query\n    $other',
          );
        }
      },
    );
  });

  // As upstream ("make this collision robust"): the id shows a value as
  // text, so a string and a number with the same text are not told apart.
  // The target cache compares the targets after the lookup by id.
  test('quirk: values with the same text share a canonical id', () {
    Query where(Object? value) => Query(ResourcePath.fromString('coll')).filter(
      FieldFilter(
        FieldPath.fromSingleSegment('a'),
        FilterOperator.equal,
        toModel(value),
      ),
    );

    expect(where(1), isNot(where('1')));
    expect(where(1).canonicalId, where('1').canonicalId);
    expect(
      where(1.5).toTarget().canonicalId,
      where('1.5').toTarget().canonicalId,
    );
    expect(where(null).canonicalId, where('null').canonicalId);
    expect(where(true).canonicalId, where('true').canonicalId);
    // An integer and the same double are different.
    expect(where(1).canonicalId, isNot(where(1.0).canonicalId));
    expect(where(0.0).canonicalId, isNot(where(-0.0).canonicalId));
  });

  group('canonical ids are stable (they are persisted)', () {
    // A change of one of these strings means that the targets a released
    // version stored in the local cache are no longer found. The ids show
    // values with their toString(), so changing the toString() of Timestamp,
    // GeoPoint, Blob, DocumentKey or of the map behind ObjectValue changes
    // them too.
    Query base() => Query(ResourcePath.fromString('coll'));
    FieldFilter filter(String field, FilterOperator op, Object? value) =>
        FieldFilter(FieldPath.fromServerFormat(field), op, toModel(value));

    test('hand-written targets', () {
      final Map<String, Query> queries = <String, Query>{
        'coll|f:|ob:__name__asc': base(),
        '|cg:coll|f:|ob:__name__asc': Query(
          ResourcePath.empty,
          collectionGroup: 'coll',
        ),
        'coll|f:a == 1|ob:__name__asc': base().filter(
          filter('a', FilterOperator.equal, 1),
        ),
        'coll|f:a == 1.0|ob:__name__asc': base().filter(
          filter('a', FilterOperator.equal, 1.0),
        ),
        'coll|f:a == text|ob:__name__asc': base().filter(
          filter('a', FilterOperator.equal, 'text'),
        ),
        'coll|f:a == null|ob:__name__asc': base().filter(
          filter('a', FilterOperator.equal, null),
        ),
        'coll|f:a == NaN|ob:__name__asc': base().filter(
          filter('a', FilterOperator.equal, double.nan),
        ),
        'coll|f:a.b > true|ob:a.basc__name__asc': base().filter(
          filter('a.b', FilterOperator.graterThan, true),
        ),
        'coll|f:a != 1|ob:aasc__name__asc': base().filter(
          filter('a', FilterOperator.notEqual, 1),
        ),
        'coll|f:a in [1, x]|ob:__name__asc': base().filter(
          filter('a', FilterOperator.IN, <Object?>[1, 'x']),
        ),
        'coll|f:a not_in [1]|ob:aasc__name__asc': base().filter(
          filter('a', FilterOperator.NOT_IN, <Object?>[1]),
        ),
        'coll|f:a array_contains 1|ob:__name__asc': base().filter(
          filter('a', FilterOperator.arrayContains, 1),
        ),
        'coll|f:a array_contains_any [1]|ob:__name__asc': base().filter(
          filter('a', FilterOperator.arrayContainsAny, <Object?>[1]),
        ),
        // A flat AND is written without a separator, as in the Android SDK.
        'coll|f:or(a == 1,b == 2c == 3)|ob:__name__asc': base().filter(
          CompositeFilter.or(<Filter>[
            filter('a', FilterOperator.equal, 1),
            CompositeFilter.and(<Filter>[
              filter('b', FilterOperator.equal, 2),
              filter('c', FilterOperator.equal, 3),
            ]),
          ]),
        ),
        'coll|f:|ob:adesc__name__desc|l:5': base()
            .orderBy(
              OrderBy.getInstance(
                OrderByDirection.descending,
                FieldPath.fromSingleSegment('a'),
              ),
            )
            .limitToFirst(5),
        'coll|f:|ob:aasc__name__asc|lb:b:1|ub:a:2': base()
            .orderBy(
              OrderBy.getInstance(
                OrderByDirection.ascending,
                FieldPath.fromSingleSegment('a'),
              ),
            )
            .startAt(Bound(position: <FieldValue>[toModel(1)], inclusive: true))
            .endAt(Bound(position: <FieldValue>[toModel(2)], inclusive: true)),
        'coll|f:a == Timestamp {\n  seconds=1,\n  nanoseconds=2000,\n}|ob:__name__asc':
            base().filter(
              filter('a', FilterOperator.equal, const api.Timestamp(1, 2000)),
            ),
        'coll|f:a == GeoPoint { latitude=1.0, longitude=2.0 }|ob:__name__asc':
            base().filter(
              filter('a', FilterOperator.equal, const api.GeoPoint(1, 2)),
            ),
        'coll|f:a == Blob { bytes= 0102 }|ob:__name__asc': base().filter(
          filter(
            'a',
            FilterOperator.equal,
            api.Blob(Uint8List.fromList(<int>[1, 2])),
          ),
        ),
        'coll|f:a == DocumentKey {\n  path=c/d,\n}|ob:__name__asc': base()
            .filter(filter('a', FilterOperator.equal, modelReference('c/d'))),
        'coll|f:a == VectorValue([1.0, 2.0])|ob:__name__asc': base().filter(
          filter('a', FilterOperator.equal, api.VectorValue(<double>[1, 2])),
        ),
        'coll|f:a == [1, {b: 2}]|ob:__name__asc': base().filter(
          filter('a', FilterOperator.equal, <Object?>[
            1,
            <String, Object?>{'b': 2},
          ]),
        ),
        'coll|f:a == ArraySortedMap<String, FieldValue>{(b=>2), (c=>x)};|ob:__name__asc':
            base().filter(
              filter('a', FilterOperator.equal, <String, Object?>{
                'c': 'x',
                'b': 2,
              }),
            ),
        'coll|f:a == {__int__:7}|ob:__name__asc': base().filter(
          filter('a', FilterOperator.equal, api.Int32Value(7)),
        ),
        'coll|f:a == {__min__:null}|ob:__name__asc': base().filter(
          filter('a', FilterOperator.equal, api.MinKey.instance),
        ),
      };
      queries.forEach((String id, Query query) {
        expect(query.toTarget().canonicalId, id);
      });
    });

    test('generated targets (by hash)', () {
      // FNV-1a over the UTF-16 code units of the id of the query of a seed.
      // These also change when the query generator changes; the hand-written
      // targets above then tell whether the ids themselves changed.
      int hash(String text) {
        int h = 0x811c9dc5;
        for (final int unit in text.codeUnits) {
          h = ((h ^ unit) * 0x01000193) & 0xffffffff;
        }
        return h;
      }

      const Map<int, int> pinned = <int, int>{
        1: 158198358,
        2: 2127590354,
        3: 1130152560,
        5: 1228955145,
        8: 2158989775,
        13: 603518596,
        21: 3120479133,
        34: 2374660318,
        55: 1195256439,
        89: 3176914865,
        144: 1074331126,
        233: 195457582,
      };
      final Map<int, int> actual = <int, int>{
        for (final int seed in <int>[
          1,
          2,
          3,
          5,
          8,
          13,
          21,
          34,
          55,
          89,
          144,
          233,
        ])
          seed: hash(Gen(seed).query().toTarget().canonicalId),
      };
      expect(actual, pinned);
    });
  });
}
