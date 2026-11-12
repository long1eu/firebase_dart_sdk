// Properties that compare the SDK with a backend (the emulator). Shared by
// the standard suite (test/integration) and the Enterprise edition suite
// (test/integration_enterprise), which adds the BSON types.

import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart'
    as model;
import 'package:cloud_firestore_dart/src/firebase/firestore/util/util.dart'
    show autoId;
import 'package:test/test.dart';

import 'property.dart';

/// Adapts the generators to what the backend of this run can hold. Call it first in `main` of a test that compares
/// the client with the backend.
///
/// On the web transport (`FIRESTORE_TEST_TRANSPORT=webchannel*`) no negative zero is generated: the JSON endpoints
/// of the emulator store -0.0 as 0.0, so the backend could never agree with the client about its sign.
void configureGeneratorsForBackend() {
  Gen.negativeZero = !(Platform.environment['FIRESTORE_TEST_TRANSPORT'] ?? '')
      .startsWith('webchannel');
}

/// Writes [documents] (id to data) to [collection] in batches.
Future<void> writeAll(CollectionReference<Map<String, Object?>> collection,
    Map<String, Map<String, Object?>> documents) async {
  final List<MapEntry<String, Map<String, Object?>>> entries =
      documents.entries.toList();
  for (int start = 0; start < entries.length; start += 100) {
    final WriteBatch batch = collection.firestore.batch();
    for (final MapEntry<String, Map<String, Object?>> entry
        in entries.skip(start).take(100)) {
      batch.set(collection.doc(entry.key), entry.value);
    }
    await batch.commit();
  }
}

/// Property: the backend sorts the values of a field like the SDK does.
///
/// Writes [count] generated values (one document each) and compares the
/// order of `orderBy('v')` on the backend with the local order of the same
/// documents. On a failure the message shows the seed and the first pair of
/// neighbours that the two sides order differently.
Future<void> checkValueOrderAgainstBackend(
  Firestore firestore, {
  required int seed,
  required int count,
  required bool bson,
}) async {
  final Gen gen = Gen(seed);
  final CollectionReference<Map<String, Object?>> collection =
      firestore.collection('property_order_${autoId()}');
  final Map<String, Object?> values = <String, Object?>{
    for (int i = 0; i < count; i++)
      'd${i.toString().padLeft(4, '0')}': gen.value(
          bson: bson,
          reference: (String path) =>
              firestore.doc(path.replaceFirst('c/', '${collection.id}/')))
  };
  await writeAll(collection, <String, Map<String, Object?>>{
    for (final MapEntry<String, Object?> entry in values.entries)
      entry.key: <String, Object?>{'v': entry.value}
  });

  for (final Direction direction in Direction.values) {
    final QuerySnapshot<Map<String, Object?>> snapshot =
        await collection.orderBy('v', direction).get(Source.server);
    expect(snapshot.docs, hasLength(count),
        reason: 'seed $seed: the backend did not return every document');

    final List<Document> server = <Document>[
      for (final QueryDocumentSnapshot<Map<String, Object?>> doc
          in snapshot.docs)
        doc.document!
    ];
    model.FieldValue valueOf(Document doc) =>
        doc.getField(FieldPath.fromDotSeparatedPath('v').internalPath)!;
    int compare(Document a, Document b) {
      int result = valueOf(a).compareTo(valueOf(b));
      if (result == 0) {
        result = a.key.compareTo(b.key);
      }
      return direction == Direction.ascending ? result : -result;
    }

    for (int i = 0; i + 1 < server.length; i++) {
      if (compare(server[i], server[i + 1]) > 0) {
        final String a = server[i].key.path.last;
        final String b = server[i + 1].key.path.last;
        fail('Property "backend value order" failed.\n'
            '  seed: $seed, count: $count, bson: $bson, '
            'direction: ${direction.name} '
            '(rerun with PROPERTY_SEED=$seed)\n'
            '  the backend returns $a before $b, the SDK sorts $b first:\n'
            '    $a = ${describe(values[a])}\n'
            '    $b = ${describe(values[b])}');
      }
    }
  }
}

// ------------------------------------------------------------ query matching

/// Values that documents hold and that filters and cursors use. The pool is
/// small so that filters match and cursors fall between documents, and it
/// has the values with special rules: null, NaN, the zeros, an integer and
/// the equal double, values of several types in one field, arrays and maps.
List<Object?> queryValuePool(
        Gen gen, DocumentReference<Object?> Function(String id) doc) =>
    <Object?>[
      null, double.nan, false, true, 0, Gen.signedZero, 1, 1.0, 2, 2.5, -1, 3, //
      9007199254740993, 9007199254740992.0, '', 'a', 'b', 'aa', 'é', 'A',
      const <Object?>[], const <Object?>[1], const <Object?>[1, 2],
      const <Object?>['a', null], const <Object?>[double.nan],
      const <Object?>[2, 1], const <String, Object?>{},
      const <String, Object?>{'x': 1}, const <String, Object?>{'x': null},
      const Timestamp(1, 0), const Timestamp(2, 500000000),
      const GeoPoint(1, 2), Blob.fromBase64String('AQI='), doc('d00'),
      doc('d05'), VectorValue(const <double>[1, 2]),
    ];

/// A document for the query property: the fields `a` to `d` hold pool values
/// (or are missing) and `m.x` is a nested field.
Map<String, Object?> queryDocument(Gen gen, List<Object?> pool) {
  return <String, Object?>{
    for (final String field in const <String>['a', 'b', 'c', 'd'])
      if (gen.chance(85)) field: gen.pick(pool),
    if (gen.chance(60))
      'm': <String, Object?>{if (gen.chance(80)) 'x': gen.pick(pool)},
  };
}

/// A query built through the public API, with a description for messages.
class GeneratedQuery {
  GeneratedQuery(this.query, this.description);

  final Query<Map<String, Object?>> query;
  final String description;

  @override
  String toString() => description;
}

/// Builds a random query on [collection]. Returns null when the SDK rejects
/// the combination of constraints (the caller counts it as discarded).
GeneratedQuery? generateQuery(Gen gen,
    CollectionReference<Map<String, Object?>> collection, List<Object?> pool,
    {bool nullAndNaNOperands = false, bool limits = true}) {
  final StringBuffer text = StringBuffer('collection');
  const List<String> fields = <String>['a', 'b', 'c', 'd', 'm.x'];
  Object? scalar() => gen.pick(pool);
  bool special(Object? v) => v == null || v is double && v.isNaN;
  // An operand for `<=` and `>=`, see [nullAndNaNOperands].
  Object? bound() => nullAndNaNOperands
      ? scalar()
      : gen.pick(pool.where((Object? v) => !special(v)).toList());
  // The operands of the membership filters: no arrays (they cannot be
  // nested), and see [nullAndNaNOperands].
  final List<Object?> members = pool
      .where((Object? v) => v is! List && (nullAndNaNOperands || !special(v)))
      .toList();
  List<Object?> operands() =>
      <Object?>[for (int i = gen.between(1, 3); i > 0; i--) gen.pick(members)];

  (Filter, String) fieldFilter() {
    final String field = gen.pick(fields);
    switch (gen.below(12)) {
      case 0:
        final Object? v = scalar();
        return (Filter.notEqualTo(field, v), '$field != ${describe(v)}');
      case 1:
        final Object? v = scalar();
        return (Filter.lessThan(field, v), '$field < ${describe(v)}');
      case 2:
        final Object? v = bound();
        return (Filter.lessThanOrEqualTo(field, v), '$field <= ${describe(v)}');
      case 3:
        final Object? v = scalar();
        return (Filter.greaterThan(field, v), '$field > ${describe(v)}');
      case 4:
        final Object? v = bound();
        return (
          Filter.greaterThanOrEqualTo(field, v),
          '$field >= ${describe(v)}'
        );
      case 5:
        final Object? v = gen.pick(members);
        return (
          Filter.arrayContains(field, v),
          '$field array-contains ${describe(v)}'
        );
      case 6:
        final List<Object?> v = operands();
        return (
          Filter.arrayContainsAny(field, v),
          '$field array-contains-any ${describe(v)}'
        );
      case 7:
        final List<Object?> v = operands();
        return (Filter.inArray(field, v), '$field in ${describe(v)}');
      case 8:
        final List<Object?> v = operands();
        return (Filter.notInArray(field, v), '$field not-in ${describe(v)}');
      default:
        final Object? v = scalar();
        return (Filter.equalTo(field, v), '$field == ${describe(v)}');
    }
  }

  (Filter, String) filter(int depth) {
    if (depth == 0 || gen.chance(70)) {
      return fieldFilter();
    }
    final List<(Filter, String)> parts = <(Filter, String)>[
      for (int i = gen.between(2, 3); i > 0; i--) filter(depth - 1)
    ];
    final bool or = gen.chance(60);
    return (
      or
          ? Filter.or(parts.map(((Filter, String) p) => p.$1).toList())
          : Filter.and(parts.map(((Filter, String) p) => p.$1).toList()),
      '${or ? 'or' : 'and'}(${parts.map(((
            Filter,
            String
          ) p) => p.$2).join(', ')})'
    );
  }

  try {
    Query<Map<String, Object?>> query = collection;
    for (int i = gen.below(gen.size.clamp(0, 2) + 1); i > 0; i--) {
      final (Filter, String) f = filter(gen.size >= 4 ? 2 : 1);
      query = query.where(f.$1);
      text.write('\n      .where(${f.$2})');
    }

    final List<String> ordered = <String>[];
    for (int i = gen.below(gen.size.clamp(0, 2) + 1); i > 0; i--) {
      final String field = gen.pick(fields);
      if (ordered.contains(field)) {
        continue;
      }
      ordered.add(field);
      final Direction direction =
          gen.chance(50) ? Direction.ascending : Direction.descending;
      query = query.orderBy(field, direction);
      text.write('\n      .orderBy($field, ${direction.name})');
    }

    List<Object?> cursor() => <Object?>[
          for (int i = gen.between(1, ordered.length); i > 0; i--) scalar()
        ];
    if (ordered.isNotEmpty && gen.chance(35)) {
      final List<Object?> values = cursor();
      if (gen.chance(50)) {
        query = query.startAt(values);
        text.write('\n      .startAt(${describe(values)})');
      } else {
        query = query.startAfter(values);
        text.write('\n      .startAfter(${describe(values)})');
      }
    }
    if (ordered.isNotEmpty && gen.chance(35)) {
      final List<Object?> values = cursor();
      if (gen.chance(50)) {
        query = query.endAt(values);
        text.write('\n      .endAt(${describe(values)})');
      } else {
        query = query.endBefore(values);
        text.write('\n      .endBefore(${describe(values)})');
      }
    }
    if (limits && gen.chance(40)) {
      final int limit = gen.between(1, 6);
      if (ordered.isNotEmpty && gen.chance(40)) {
        query = query.limitToLast(limit);
        text.write('\n      .limitToLast($limit)');
      } else {
        query = query.limit(limit);
        text.write('\n      .limit($limit)');
      }
    }
    return GeneratedQuery(query, text.toString());
  } on ArgumentError {
    return null;
  } on StateError {
    return null;
  }
}

/// The ids of the documents of [all] that [query] returns according to the
/// SDK's own evaluation (`matches`, the query comparator and the limit).
List<String> evaluateLocally(
    Query<Map<String, Object?>> query, List<Document> all) {
  final List<Document> matching = all.where(query.query.matches).toList()
    ..sort(query.query.comparator);
  List<Document> limited = matching;
  if (query.query.hasLimitToFirst) {
    limited = matching.take(query.query.getLimit()).toList();
  } else if (query.query.hasLimitToLast) {
    final int limit = query.query.getLimit();
    limited = matching.length <= limit
        ? matching
        : matching.sublist(matching.length - limit);
  }
  return <String>[for (final Document doc in limited) doc.key.path.last];
}

/// The outcome of [checkQueriesAgainstBackend].
class QueryPropertyStats {
  int compared = 0;
  int rejectedBySdk = 0;
  final Map<String, int> rejectedByBackend = <String, int>{};

  /// The failures found so far. The property keeps going after a failure,
  /// up to [maxFailures], so that one run shows the kinds of disagreement.
  final List<String> failures = <String>[];

  static const int maxFailures = 8;

  @override
  String toString() => 'compared $compared queries; the SDK rejected '
      '$rejectedBySdk, the backend ${rejectedByBackend.values.fold<int>(0, (int a, int b) => a + b)} '
      '$rejectedByBackend';
}

/// Property: for random documents and random queries, the SDK's own
/// evaluation of a query returns the documents the backend returns, in the
/// same order.
///
/// One collection of [documentCount] documents is written for [seed], then
/// [queryCount] queries run against it. A failure shows the seed, the query
/// (regenerated with the smallest size that still fails) and the documents
/// on which the two sides disagree.
///
/// Two options account for the editions of the backend:
///  * [nullAndNaNOperands] generates null and NaN as operands of `in`,
///    `not-in`, the array filters, `<=` and `>=`. For the SDK (and an
///    Enterprise edition database) null and NaN are the same as themselves
///    in these filters; a Standard edition database never matches them, so
///    there a cached null or NaN document stays in limbo for such a query.
///    Off by default; on for an Enterprise edition database.
///  * [limits] generates `limit` and `limitToLast`. Off for an Enterprise
///    edition database: it returns more documents for `!=` and `not-in`
///    (null and missing fields), which the SDK drops from the result. With a
///    limit the backend counts them, so the page comes back short.
Future<void> checkQueriesAgainstBackend(
  Future<Firestore> Function() newFirestore, {
  required int seed,
  required int documentCount,
  required int queryCount,
  required QueryPropertyStats stats,
  bool limits = true,
  bool nullAndNaNOperands = false,
}) async {
  final Gen gen = Gen(seed);
  CollectionReference<Map<String, Object?>> collection =
      (await newFirestore()).collection('property_query_${autoId()}');
  String id(int i) => 'd${i.toString().padLeft(2, '0')}';
  final List<Object?> pool = queryValuePool(gen, collection.doc);
  final Map<String, Map<String, Object?>> data = <String, Map<String, Object?>>{
    for (int i = 0; i < documentCount; i++) id(i): queryDocument(gen, pool)
  };
  await writeAll(collection, data);
  final List<Document> all = <Document>[
    for (final QueryDocumentSnapshot<Map<String, Object?>> doc
        in (await collection.get(Source.server)).docs)
      doc.document!
  ];
  expect(all, hasLength(documentCount));

  /// Null when the two sides agree or the query is rejected.
  Future<String?> mismatch(int querySeed, int size) async {
    final GeneratedQuery? generated = generateQuery(
        Gen(querySeed, size: size), collection, pool,
        limits: limits, nullAndNaNOperands: nullAndNaNOperands);
    if (generated == null) {
      if (size == defaultSize) {
        stats.rejectedBySdk++;
      }
      return null;
    }
    if (traceProperties) {
      print('TRACE seed $seed query seed $querySeed size $size: $generated');
    }
    List<String> actual;
    String note = '';
    try {
      actual = <String>[
        for (final QueryDocumentSnapshot<Map<String, Object?>> doc
            in (await generated.query
                    .get(Source.server)
                    .timeout(const Duration(seconds: 10)))
                .docs)
          doc.id
      ];
    } on TimeoutException {
      // The view of the query never gets in sync, because the SDK keeps a
      // cached document in it that the backend does not return. Ask a new
      // instance, which has nothing cached, for the answer of the backend,
      // and go on with it (the old one still has the stuck listener).
      note = '  get(Source.server) did not complete within 10 seconds while '
          'the documents were cached.\n';
      final Firestore fresh = await newFirestore();
      collection = fresh.collection(collection.path);
      actual = <String>[
        for (final QueryDocumentSnapshot<Map<String, Object?>> doc
            in (await generateQuery(
                        Gen(querySeed, size: size), collection, pool,
                        limits: limits, nullAndNaNOperands: nullAndNaNOperands)!
                    .query
                    .get(Source.server)
                    .timeout(const Duration(seconds: 20)))
                .docs)
          doc.id
      ];
      await collection.get(Source.server);
    } on FirestoreError catch (e) {
      if (e.code == FirestoreErrorCode.invalidArgument ||
          e.code == FirestoreErrorCode.failedPrecondition ||
          e.code == FirestoreErrorCode.unimplemented) {
        if (size == defaultSize) {
          final String reason = e.message.split('\n').first;
          stats.rejectedByBackend[reason.length > 70
              ? '${reason.substring(0, 70)}...'
              : reason] = (stats.rejectedByBackend[reason.length > 70
                      ? '${reason.substring(0, 70)}...'
                      : reason] ??
                  0) +
              1;
        }
        return null;
      }
      rethrow;
    }
    final List<String> expected = evaluateLocally(generated.query, all);
    if (size == defaultSize) {
      stats.compared++;
    }
    if (expected.join(',') == actual.join(',') && note.isEmpty) {
      return null;
    }
    final Set<String> differing = <String>{
      ...expected.where((String d) => !actual.contains(d)),
      ...actual.where((String d) => !expected.contains(d)),
    };
    return '  query (size $size):\n    $generated\n$note'
        '  the SDK evaluates to: $expected\n'
        '  the backend returns:  $actual\n'
        '${differing.isEmpty ? '  (same documents, different order)\n' : '  documents only one side returns:\n${differing.map((String d) => '    $d = ${describe(data[d])}\n').join()}'}';
  }

  for (int q = 0;
      q < queryCount && stats.failures.length < QueryPropertyStats.maxFailures;
      q++) {
    final int querySeed = (seed + (q + 1) * 104729) & 0x7fffffff;
    final String? failure = await mismatch(querySeed, defaultSize);
    if (failure == null) {
      continue;
    }
    String smallest = failure;
    // A query that hangs takes 10 seconds per attempt: only try size 2.
    for (final int size in failure.contains('did not complete')
        ? const <int>[2, 4]
        : const <int>[0, 1, 2, 3, 4, 5]) {
      final String? smaller = await mismatch(querySeed, size);
      if (smaller != null) {
        smallest = smaller;
        break;
      }
    }
    stats.failures.add('Property "query results match the backend" failed.\n'
        '  seed: $seed, query #$q of $queryCount, $documentCount documents '
        '(rerun with PROPERTY_SEED=$seed)\n$smallest');
  }
}
