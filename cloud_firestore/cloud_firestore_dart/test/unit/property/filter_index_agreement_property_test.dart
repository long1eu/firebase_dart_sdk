// Property: query matching, the order of values and the index agree.
//
//  * Query.matches (with the field filters) gives what the order of values
//    (FieldValue.compareTo and the type order) says, with the rules of
//    Android core/FieldFilter.java and the filters next to it:
//      - `!=` matches every present, non-null value that does not compare
//        equal;
//      - the other comparisons only match values of the same type order, NaN
//        being a type of its own (Values.TYPE_ORDER_NUMBER_NAN);
//      - `in`, `not-in`, `array-contains` and `array-contains-any` test
//        membership with Values.equals, which is "compares equal" (numbers
//        by numeric value, Values.numberEquals).
//  * The SQLite index (FirestoreIndexValueWriter, the bounds of the target
//    and the SQL range scan) returns exactly the documents that match when
//    every number is replaced by a double, plus the two kinds of extra
//    documents of upstream's index that the query engine filters out again
//    (see [_indexOracle]). Numbers are indexed as doubles in the Android and
//    JS SDKs too, so numbers that compare different can share an index
//    entry; where that makes the index miss a matching document is pinned in
//    'quirk:' tests below.
//
// That the index encoding sorts like FieldValue.compareTo is checked by
// value_order_property_test.dart.
//
// The values are random values of every type, BSON types, NaN, -0.0, nested
// maps and arrays included. Runs locally, no emulator, in about 2 s.
// Environment (see test/util/property.dart): PROPERTY_SEED picks the first
// case, PROPERTY_SCALE multiplies the number of cases for long runs
// (PROPERTY_SCALE=20 takes about 10 s).

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart'
    show Decimal128Value, Int32Value, MaxKey, MinKey;
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/filter/filter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/index_manager.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../util/index_helpers.dart';
import '../../util/property.dart';
import '../../util/test_util.dart' as util;
import '../firebase/firestore/local/persistence_test_helpers.dart';

const String _field = 'a';

const List<String> _comparisons = <String>['<', '<=', '==', '!=', '>=', '>'];

/// Values that the generator rarely produces but where the three parts most
/// easily disagree.
final List<Object? Function()> _special = <Object? Function()>[
  () => null,
  () => double.nan,
  () => -0.0,
  () => 0.0,
  () => 0,
  () => 1,
  () => 1.0,
  () => Int32Value(0),
  () => Int32Value(1),
  () => Decimal128Value('-0'),
  () => Decimal128Value('1.0'),
  () => Decimal128Value('NaN'),
  // Numbers that are not exactly a double: the index stores them as the
  // nearest double, which they share with other numbers.
  () => Decimal128Value('1e-6176'),
  () => Decimal128Value('1.000000000000000000000000000000001'),
  () => Decimal128Value('0.99999999999999999999'),
  () => 9007199254740992.0,
  () => 9007199254740992,
  () => 9007199254740993,
  () => MinKey.instance,
  () => MaxKey.instance,
  () => <Object?>[double.nan],
  () => <Object?>[-0.0, 1],
  () => <Object?>[0, 1.0],
  () => <String, Object?>{'x': -0.0},
  () => <String, Object?>{
    'x': 0,
    'y': <Object?>[double.nan],
  },
];

/// One generated case: the documents of a collection and a filter.
class Case {
  Case(this.collection, this.docs, this.filters, this.disjunction, this.kind);

  final String collection;

  /// User data of the field of each document; [_missing] for a document
  /// without the field.
  final List<Object?> docs;

  /// `[operator, value]` pairs.
  final List<List<Object?>> filters;

  /// Whether [filters] are or'ed (otherwise there is one filter).
  final bool disjunction;

  final SegmentKind kind;

  @override
  String toString() =>
      '${disjunction ? 'OR ' : ''}'
      '${filters.map((List<Object?> f) => '$_field ${f[0]} ${describe(f[1])}').join(' | ')}'
      ' (index ${kind.name})\n    docs: '
      '${docs.map((Object? d) => identical(d, _missing) ? '<missing>' : describe(d)).join(', ')}';
}

const Object _missing = Object();

Object? _value(Gen gen) => gen.chance(25)
    ? gen.pick(_special)()
    : gen.value(bson: true, reference: util.ref);

/// A filter value: often one of the document values, to hit equality.
Object? _operand(Gen gen, List<Object?> docs) {
  final List<Object?> present = <Object?>[
    for (final Object? d in docs)
      if (!identical(d, _missing)) d,
  ];
  if (present.isNotEmpty && gen.chance(50)) {
    return gen.pick(present);
  }
  return _value(gen);
}

bool _isNaNValue(Object? v) =>
    v is double && v.isNaN || v is Decimal128Value && v.stringValue == 'NaN';

/// A filter that the API accepts: `null` and NaN only with `==` and `!=`
/// (they become IS_NULL / IS_NAN), no array as an `array-contains` value or
/// inside an `array-contains-any` list, and non-empty lists.
List<Object?> _filter(Gen gen, List<Object?> docs, bool arrays) {
  for (;;) {
    if (arrays) {
      final String op = gen.pick(<String>[
        'array-contains',
        'array-contains-any',
      ]);
      Object? element() {
        // An element of an array of one of the documents, or any value.
        final List<Object?> elements = <Object?>[
          for (final Object? d in docs)
            if (d is List) ...d,
        ];
        return elements.isNotEmpty && gen.chance(60)
            ? gen.pick(elements)
            : _value(gen);
      }

      if (op == 'array-contains') {
        final Object? v = element();
        if (v is List) {
          continue;
        }
        return <Object?>[op, v];
      }
      final List<Object?> list = <Object?>[
        for (int i = gen.between(1, 3); i > 0; i--) element(),
      ];
      if (list.any((Object? v) => v is List)) {
        continue;
      }
      return <Object?>[op, list];
    }

    final String op = gen.chance(70)
        ? gen.pick(_comparisons)
        : gen.pick(<String>['in', 'not-in']);
    if (op == 'in' || op == 'not-in') {
      return <Object?>[
        op,
        <Object?>[
          for (int i = gen.between(1, 3); i > 0; i--) _operand(gen, docs),
        ],
      ];
    }
    final Object? v = _operand(gen, docs);
    if ((v == null || _isNaNValue(v)) && op != '==' && op != '!=') {
      continue;
    }
    return <Object?>[op, v];
  }
}

Case _generate(Gen gen, int index) {
  final List<Object?> docs = <Object?>[
    for (int i = 0; i < 3 + gen.size * 2; i++)
      gen.chance(10) ? _missing : _value(gen),
  ];
  final bool arrays = gen.chance(30);
  if (arrays) {
    // Array-contains needs arrays in the documents.
    for (int i = 0; i < docs.length; i++) {
      if (gen.chance(60)) {
        docs[i] = <Object?>[
          for (int j = gen.below(4); j > 0; j--)
            gen.chance(30)
                ? gen.pick(_special)()
                : gen.value(
                    bson: true,
                    reference: util.ref,
                    depth: 1,
                    insideArray: true,
                  ),
        ];
      }
    }
  }
  final bool disjunction = !arrays && gen.chance(25);
  return Case(
    'c$index',
    docs,
    <List<Object?>>[
      for (int i = disjunction ? 2 : 1; i > 0; i--) _filter(gen, docs, arrays),
    ],
    disjunction,
    arrays
        ? SegmentKind.contains
        : gen.pick(<SegmentKind>[
            SegmentKind.ascending,
            SegmentKind.descending,
          ]),
  );
}

// ------------------------------------------------------------------ oracle

/// The type order of Android's Values.typeOrder: NaN is a type of its own,
/// between booleans and numbers.
double _typeOrder(FieldValue v) =>
    _isNaNField(v) ? FieldValue.typeOrderNumber - 0.5 : v.typeOrder.toDouble();

bool _isNaNField(FieldValue v) {
  final Object? value = v.value;
  return value is double && value.isNaN ||
      value is Decimal128Value && value.stringValue.toLowerCase() == 'nan';
}

/// Android Values.equals: same type order and compares equal.
bool _same(FieldValue a, FieldValue b) =>
    _typeOrder(a) == _typeOrder(b) && a.compareTo(b) == 0;

bool _contains(List<FieldValue> list, FieldValue value) =>
    list.any((FieldValue e) => _same(e, value));

bool _expected(FieldValue? other, String op, FieldValue value) {
  switch (op) {
    case '!=':
      return other != null &&
          other.typeOrder != FieldValue.typeOrderNull &&
          other.compareTo(value) != 0;
    case 'in':
      return other != null && _contains(_elements(value), other);
    case 'not-in':
      final List<FieldValue> list = _elements(value);
      if (list.any((FieldValue v) => v.typeOrder == FieldValue.typeOrderNull)) {
        return false;
      }
      return other != null &&
          other.typeOrder != FieldValue.typeOrderNull &&
          !_contains(list, other);
    case 'array-contains':
      return other != null &&
          other.typeOrder == FieldValue.typeOrderArray &&
          _contains(_elements(other), value);
    case 'array-contains-any':
      return other != null &&
          other.typeOrder == FieldValue.typeOrderArray &&
          _elements(
            other,
          ).any((FieldValue e) => _contains(_elements(value), e));
  }
  if (other == null || _typeOrder(other) != _typeOrder(value)) {
    return false;
  }
  final int c = other.compareTo(value);
  switch (op) {
    case '<':
      return c < 0;
    case '<=':
      return c <= 0;
    case '==':
      return c == 0;
    case '>=':
      return c >= 0;
    default:
      return c > 0;
  }
}

List<FieldValue> _elements(FieldValue array) =>
    (array as ArrayValue).internalValue;

/// [value] with every number replaced by the double the index stores.
Object? _asDoubles(Object? value) {
  if (value is int) {
    return value.toDouble();
  } else if (value is Int32Value) {
    return value.value.toDouble();
  } else if (value is Decimal128Value) {
    return double.parse(value.stringValue);
  } else if (value is List) {
    return value.map(_asDoubles).toList();
  } else if (value is Map) {
    return <Object?, Object?>{
      for (final MapEntry<Object?, Object?> e in value.entries)
        e.key: _asDoubles(e.value),
    };
  }
  return value;
}

// ------------------------------------------------------------- the checks

Document _doc(Case c, int i) {
  final Object? data = c.docs[i];
  return util.doc(
    '${c.collection}/d$i',
    1,
    identical(data, _missing)
        ? <String, Object?>{'other': 1}
        : <String, Object?>{_field: data},
  );
}

Filter _coreFilter(List<Object?> f, Object? Function(Object? v) map) =>
    util.filter(_field, f[0]! as String, map(f[1]));

/// The query of [c]. An ordered index only serves a query ordered by the
/// field in the direction of the index (TargetIndexMatcher).
Query _query(Case c, [Object? Function(Object? v) map = _identity]) {
  Query base = Query(util.path(c.collection));
  if (c.kind != SegmentKind.contains) {
    base = base.orderBy(
      util.orderBy(_field, c.kind == SegmentKind.ascending ? 'asc' : 'desc'),
    );
  }
  if (c.disjunction) {
    return base.filter(
      util.orFilters(<Filter>[
        for (final List<Object?> f in c.filters) _coreFilter(f, map),
      ]),
    );
  }
  return base.filter(_coreFilter(c.filters.single, map));
}

Object? _identity(Object? v) => v;

/// What the oracle says for document [i], with [map] applied to every value.
bool _oracle(Case c, int i, [Object? Function(Object? v) map = _identity]) {
  final Object? data = c.docs[i];
  final FieldValue? other = identical(data, _missing)
      ? null
      : util.wrap(map(data));
  return c.filters.any(
    (List<Object?> f) =>
        _expected(other, f[0]! as String, util.wrap(map(f[1]))),
  );
}

/// Whether the index returns document [i] for case [c], as upstream's
/// index does: the filters are evaluated with every number replaced by the
/// double the index stores, and in addition
///  * a `<` / `<=` on a number also returns the NaNs: the lowest number is a
///    NaN (Values.getLowerBound returns MIN_NUMBER), and
///  * a `not-in` that lists null returns what the other listed values do not
///    exclude: the index only excludes the listed values
///    (Target.getNotInValues), while the filter matches nothing.
bool _indexOracle(Case c, int i) {
  final Object? data = c.docs[i];
  if (identical(data, _missing)) {
    return false;
  }
  final FieldValue other = util.wrap(_asDoubles(data));
  return c.filters.any((List<Object?> f) {
    final String op = f[0]! as String;
    final FieldValue value = util.wrap(_asDoubles(f[1]));
    if ((op == '<' || op == '<=') &&
        _isNaNField(other) &&
        value.typeOrder == FieldValue.typeOrderNumber) {
      return true;
    }
    if (op == 'not-in') {
      return other.typeOrder != FieldValue.typeOrderNull &&
          !_contains(_elements(value), other);
    }
    return _expected(other, op, value);
  });
}

void main() {
  test('Query.matches agrees with the order of values', () {
    forAll<Case>(
      'matching',
      count: cases(1500),
      generate: (Gen gen) => _generate(gen, 0),
      show: (Case c) => '$c',
      check: (Case c) {
        final Query query = _query(c);
        for (int i = 0; i < c.docs.length; i++) {
          final bool actual = query.matches(_doc(c, i));
          final bool expected = _oracle(c, i);
          if (actual != expected) {
            fail(
              'Query.matches gives $actual, the order of values $expected '
              'for d$i',
            );
          }
        }
      },
    );
  });

  group('the index', () {
    late SQLitePersistence persistence;
    late IndexManager indexManager;

    setUpAll(() async {
      persistence = await createSQLitePersistence(
        'property/filter_index_agreement-${const Uuid().v4()}.db',
      );
      indexManager = persistence.getIndexManager(User.unauthenticated);
      await indexManager.start();
    });

    tearDownAll(() => persistence.shutdown());

    // Pinned upstream behaviour (Android SQLiteIndexManager, JS
    // IndexedDbIndexManager): numbers are indexed as doubles, so a number
    // that is not exactly a double shares its index entry with others. An
    // exclusive bound or a `!=` / `not-in` on that entry drops documents that
    // match. A fix needs an index encoding that tells these numbers apart (a
    // persisted format change); see the summary of this change.
    test('quirk: the index misses numbers that share an entry', () async {
      final Map<String, List<Object>> cases = <String, List<Object>>{
        // op, filter value, document value that matches but is missed
        'a != 1e-6176 misses 0': <Object>['!=', Decimal128Value('1e-6176'), 0],
        'a not-in [0] misses 1e-6176': <Object>[
          'not-in',
          <Object>[0],
          Decimal128Value('1e-6176'),
        ],
        'a < 1 misses 0.99999999999999999999': <Object>[
          '<',
          1,
          Decimal128Value('0.99999999999999999999'),
        ],
        'a > 1 misses 1.000000000000000000000000000000001': <Object>[
          '>',
          1,
          Decimal128Value('1.000000000000000000000000000000001'),
        ],
        'a > 2^53 misses 2^53 + 1': <Object>[
          '>',
          9007199254740992.0,
          9007199254740993,
        ],
      };
      int n = 0;
      for (final MapEntry<String, List<Object>> e in cases.entries) {
        final String collection = 'quirk${n++}';
        final Document d = util.doc('$collection/d', 1, <String, Object?>{
          _field: e.value[2],
        });
        final Query query = Query(util.path(collection))
            .orderBy(util.orderBy(_field))
            .filter(util.filter(_field, e.value[0] as String, e.value[1]));
        await indexManager.addFieldIndex(
          fieldIndex(
            collection,
            fieldsAndKinds: <Object>[_field, SegmentKind.ascending],
          ),
        );
        await indexManager.updateIndexEntries(<DocumentKey, MaybeDocument?>{
          d.key: d,
        });
        expect(query.matches(d), isTrue, reason: e.key);
        expect(
          await indexManager.getDocumentsMatchingTarget(query.toTarget()),
          isEmpty,
          reason: e.key,
        );
      }
    });

    test('returns the documents that match on doubles', () async {
      int index = 0;
      await forAllAsync<Case>(
        'index',
        count: cases(500),
        generate: (Gen gen) => _generate(gen, index++),
        show: (Case c) => '$c',
        check: (Case c) async {
          await indexManager.addFieldIndex(
            fieldIndex(c.collection, fieldsAndKinds: <Object>[_field, c.kind]),
          );
          await indexManager.updateIndexEntries(<DocumentKey, MaybeDocument?>{
            for (int i = 0; i < c.docs.length; i++) _doc(c, i).key: _doc(c, i),
          });

          final Query query = _query(c);
          final List<DocumentKey>? keys = await indexManager
              .getDocumentsMatchingTarget(query.toTarget());
          expect(keys, isNotNull, reason: 'the index cannot serve $query');
          final Set<String> fromIndex = <String>{
            for (final DocumentKey key in keys!) key.path.getLastSegment(),
          };

          for (int i = 0; i < c.docs.length; i++) {
            final bool indexed = fromIndex.contains('d$i');
            final bool expected = _indexOracle(c, i);
            if (indexed != expected) {
              fail(
                'the index ${indexed ? 'returns' : 'does not return'} d$i '
                '(Query.matches: ${query.matches(_doc(c, i))})',
              );
            }
          }
        },
      );
    });
  });
}
