// Interop of the port with the real JS SDK (and firebase-admin), against the Firestore emulator.
//
// The JS side is the Node harness in tool/interop (see its README). These tests are skipped unless `node` and the
// harness's node_modules are present and FIRESTORE_EMULATOR_HOST is set.
//
// What is covered:
//  1. Snapshot JSON: JS toJSON() read by Dart fromJson / resume, and Dart toJson() read by JS fromJSON /
//     onSnapshotResume.
//  2. Value JSON helpers: Timestamp, GeoPoint, Bytes (Blob), DocumentReference and VectorValue, both ways.
//  3. Bundles built by firebase-admin loaded by loadBundle.
//  4. Data: every value type written by one SDK and read by the other, and the order of a mixed-type field.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:test/test.dart';

import '../../../util/integration_test_util.dart';

/// The directory of the Node harness (the tests run with the package as the working directory).
final Directory harnessDirectory =
    Directory('${Directory.current.path}/../../tool/interop');

/// Why the tests cannot run here, or null if they can.
String? get skipReason {
  if (IntegrationTestUtil.emulatorHost == null) {
    return 'FIRESTORE_EMULATOR_HOST is not set: the JS interop tests only run against the emulator';
  }
  if (!File('${harnessDirectory.path}/harness.mjs').existsSync()) {
    return 'The Node harness is missing: ${harnessDirectory.path}';
  }
  if (!Directory('${harnessDirectory.path}/node_modules/firebase')
      .existsSync()) {
    return 'The JS SDK is not installed: run `npm install` in tool/interop';
  }
  try {
    final ProcessResult result = Process.runSync('node', <String>['--version']);
    if (result.exitCode != 0) {
      return '`node --version` failed: ${result.stderr}';
    }
  } on ProcessException catch (e) {
    return '`node` is not installed: ${e.message}';
  }
  return null;
}

int _runs = 0;

/// Runs the harness [command] with [input] and returns its output.
Future<Map<String, Object?>> runHarness(String command,
    [Map<String, Object?> input = const <String, Object?>{}]) async {
  final String emulator = IntegrationTestUtil.emulatorHost!;
  final int separator = emulator.lastIndexOf(':');
  final Directory temp =
      Directory.systemTemp.createTempSync('firestore_js_interop_${_runs++}_');
  try {
    final File inputFile = File('${temp.path}/input.json');
    final File outputFile = File('${temp.path}/output.json');
    inputFile.writeAsStringSync(jsonEncode(<String, Object?>{
      'projectId': IntegrationTestUtil.provider.projectId,
      'host': emulator.substring(0, separator),
      'port': int.parse(emulator.substring(separator + 1)),
      'tempDirectory': temp.path,
      ...input,
    }));
    final ProcessResult result = await Process.run('node',
        <String>['harness.mjs', command, inputFile.path, outputFile.path],
        workingDirectory: harnessDirectory.path);
    if (result.exitCode != 0) {
      fail(
          'harness $command failed (${result.exitCode}):\n${result.stdout}\n${result.stderr}');
    }
    // The numeric strings of the descriptions are normalized, so that they compare equal to the Dart ones.
    final Map<String, Object?> output = asMap(
        command == 'write-snapshots' || command == 'write-data'
            ? jsonDecode(outputFile.readAsStringSync())
            : normalize(jsonDecode(outputFile.readAsStringSync()),
                jsNumbers: true));
    final Object? bundleFile = input['bundleFile'];
    if (bundleFile is String) {
      output['bundleBytes'] =
          File('${temp.path}/$bundleFile').readAsBytesSync();
    }
    return output;
  } finally {
    temp.deleteSync(recursive: true);
  }
}

String uniqueName(String prefix) =>
    '$prefix${DateTime.now().microsecondsSinceEpoch}';

Map<String, Object?> asMap(Object? value) => value! as Map<String, Object?>;

List<Object?> asList(Object? value) => value! as List<Object?>;

// ---- The tagged description of values shared with the harness ----

Map<String, Object?> _spec(String type,
        [Map<String, Object?> fields = const <String, Object?>{}]) =>
    <String, Object?>{'t': type, ...fields};

Map<String, Object?> nullSpec() => _spec('null');
Map<String, Object?> boolSpec(bool v) =>
    _spec('bool', <String, Object?>{'v': v});
Map<String, Object?> intSpec(int v) =>
    _spec('int', <String, Object?>{'v': '$v'});
Map<String, Object?> doubleSpec(double v) =>
    _spec('double', <String, Object?>{'v': doubleToString(v)});
Map<String, Object?> stringSpec(String v) =>
    _spec('string', <String, Object?>{'v': v});
Map<String, Object?> timestampSpec(int seconds, int nanos) =>
    _spec('timestamp', <String, Object?>{'s': '$seconds', 'n': nanos});
Map<String, Object?> geoSpec(double lat, double lng) => _spec('geo',
    <String, Object?>{'lat': doubleToString(lat), 'lng': doubleToString(lng)});
Map<String, Object?> bytesSpec(List<int> bytes) =>
    _spec('bytes', <String, Object?>{'v': base64Encode(bytes)});
Map<String, Object?> refSpec(String path) =>
    _spec('ref', <String, Object?>{'v': path});
Map<String, Object?> vectorSpec(List<double> values) => _spec(
    'vector', <String, Object?>{'v': values.map(doubleToString).toList()});
Map<String, Object?> arraySpec(List<Map<String, Object?>> values) =>
    _spec('array', <String, Object?>{'v': values});
Map<String, Object?> mapSpec(Map<String, Map<String, Object?>> values) =>
    _spec('map', <String, Object?>{'v': values});

/// A string both Dart's `double.parse` and JS's `Number()` read back exactly.
String doubleToString(double v) {
  if (v.isNaN) {
    return 'NaN';
  } else if (v == double.infinity) {
    return 'Infinity';
  } else if (v == double.negativeInfinity) {
    return '-Infinity';
  } else if (v == 0 && v.isNegative) {
    return '-0';
  }
  return v.toString();
}

/// Builds the Dart value to write for [spec].
Object? build(Firestore db, Map<String, Object?> spec) {
  switch (spec['t']) {
    case 'null':
      return null;
    case 'bool':
    case 'string':
      return spec['v'];
    case 'int':
      return int.parse(spec['v']! as String);
    case 'double':
      return double.parse(spec['v']! as String);
    case 'timestamp':
      return Timestamp(int.parse(spec['s']! as String), spec['n']! as int);
    case 'geo':
      return GeoPoint(double.parse(spec['lat']! as String),
          double.parse(spec['lng']! as String));
    case 'bytes':
      return Blob.fromBase64String(spec['v']! as String);
    case 'ref':
      return db.doc(spec['v']! as String);
    case 'vector':
      return VectorValue(asList(spec['v'])
          .map((Object? v) => double.parse(v! as String))
          .toList());
    case 'array':
      return asList(spec['v']).map((Object? v) => build(db, asMap(v))).toList();
    case 'map':
      return asMap(spec['v']).map((String key, Object? v) =>
          MapEntry<String, Object?>(key, build(db, asMap(v))));
  }
  throw StateError('Unknown spec $spec');
}

/// Describes a value read by the Dart SDK. Unlike in JS, integers and doubles are different types.
Map<String, Object?> describe(Object? value) {
  if (value == null) {
    return nullSpec();
  } else if (value is bool) {
    return boolSpec(value);
  } else if (value is int) {
    return intSpec(value);
  } else if (value is double) {
    return doubleSpec(value);
  } else if (value is String) {
    return stringSpec(value);
  } else if (value is Timestamp) {
    return timestampSpec(value.seconds, value.nanoseconds);
  } else if (value is GeoPoint) {
    return geoSpec(value.latitude, value.longitude);
  } else if (value is Blob) {
    return bytesSpec(value.bytes);
  } else if (value is DocumentReference) {
    return refSpec(value.path);
  } else if (value is VectorValue) {
    return vectorSpec(value.toArray());
  } else if (value is List) {
    return arraySpec(value.map(describe).toList());
  } else if (value is Map) {
    return mapSpec(value.map((dynamic key, dynamic v) =>
        MapEntry<String, Map<String, Object?>>(key as String, describe(v))));
  }
  throw StateError('Cannot describe $value');
}

/// Converts the description of a value to the form the JS SDK reports: numbers have a single type, and the numeric
/// strings are normalized.
Object? normalize(Object? description, {required bool jsNumbers}) {
  if (description is List) {
    return description
        .map((Object? e) => normalize(e, jsNumbers: jsNumbers))
        .toList();
  }
  if (description is! Map) {
    return description;
  }
  final Map<String, Object?> result = <String, Object?>{};
  description.forEach((dynamic key, dynamic value) {
    result[key as String] = normalize(value, jsNumbers: jsNumbers);
  });
  String number(Object? v) => doubleToString(double.parse(v! as String));
  switch (result['t']) {
    case 'int':
      if (jsNumbers) {
        result['t'] = 'number';
        result['v'] = number(result['v']);
      }
      break;
    case 'double':
    case 'number':
      if (jsNumbers) {
        result['t'] = 'number';
      }
      result['v'] = number(result['v']);
      break;
    case 'geo':
      result['lat'] = number(result['lat']);
      result['lng'] = number(result['lng']);
      break;
    case 'vector':
      result['v'] = asList(result['v']).map(number).toList();
      break;
  }
  return result;
}

/// What the Dart SDK reads after the JS SDK wrote [spec]: the JS SDK writes every number that is a safe integer
/// (other than -0) as an integer, and it cannot represent integers outside of the safe range.
Object? afterJsWrite(Object? spec) {
  if (spec is List) {
    return spec.map(afterJsWrite).toList();
  }
  if (spec is! Map) {
    return spec;
  }
  final Map<String, Object?> result = <String, Object?>{};
  spec.forEach((dynamic key, dynamic value) {
    result[key as String] = afterJsWrite(value);
  });
  if (result['t'] == 'double') {
    final double value = double.parse(result['v']! as String);
    final bool isSafeInteger = value.isFinite &&
        value == value.truncateToDouble() &&
        value.abs() <= 9007199254740991;
    if (isSafeInteger && !(value == 0 && value.isNegative)) {
      return intSpec(value.toInt());
    }
  }
  return result;
}

void main() {
  IntegrationTestUtil.currentDatabasePath = 'integration/js_interop';
  final String? skip = skipReason;

  // With metadata changes, so that the event of the listener getting in sync is raised when no document changed.
  const SnapshotListenOptions metadata =
      SnapshotListenOptions(metadataChanges: MetadataChanges.include);

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await IntegrationTestUtil.tearDown();
  });

  /// Waits until an element of [events] matches [test] and returns it.
  Future<T> waitFor<T>(List<T> events, bool Function(T event) test,
      [List<Object>? errors]) async {
    for (int i = 0; i < 200; i++) {
      for (final T event in events) {
        if (test(event)) {
          return event;
        }
      }
      if (errors != null && errors.isNotEmpty) {
        fail('The listener failed: ${errors.first}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    fail('No matching event in $events');
  }

  List<String> ids(QuerySnapshot<Object?> snapshot) =>
      snapshot.docs.map((QueryDocumentSnapshot<Object?> d) => d.id).toList();

  List<String> jsIds(Object? docs) =>
      asList(docs).map((Object? d) => asMap(d)['id']! as String).toList();

  /// The ids of the documents of a query snapshot that the listener of [json] raises once in sync.
  Future<List<String>> resumeQuery(
      Firestore db, Map<String, Object?> json) async {
    final List<QuerySnapshot<Map<String, Object?>>> events =
        <QuerySnapshot<Map<String, Object?>>>[];
    final List<Object> errors = <Object>[];
    final StreamSubscription<QuerySnapshot<Map<String, Object?>>> sub = db
        .querySnapshotsFromJson<Map<String, Object?>>(json, options: metadata)
        .listen(events.add, onError: errors.add);
    try {
      return ids(await waitFor<QuerySnapshot<Map<String, Object?>>>(
          events,
          (QuerySnapshot<Map<String, Object?>> s) => !s.metadata.isFromCache,
          errors));
    } finally {
      await sub.cancel();
    }
  }

  group('snapshot JSON', () {
    // The documents of the cases, as written by both SDKs.
    const Map<String, Object?> docA = <String, Object?>{'n': 1, 's': 'one'};
    const String threeText = 'three \u{1F60A} é';

    test('written by the JS SDK is read by fromJson and resumed', () async {
      final String name = uniqueName('jsSnapshots');
      final Map<String, Object?> snapshots = await runHarness(
          'write-snapshots', <String, Object?>{'collection': name});
      final Firestore db = await IntegrationTestUtil.testFirestore();
      final CollectionReference<Map<String, Object?>> collection =
          db.collection(name);

      // A document.
      final Map<String, Object?> documentJson = asMap(snapshots['document']);
      final DocumentSnapshot<Map<String, Object?>> document =
          DocumentSnapshot<Map<String, Object?>>.fromJson(db, documentJson);
      expect(document.exists, isTrue);
      expect(document.reference.path, '$name/a');
      expect(document.data, docA);

      final List<DocumentSnapshot<Map<String, Object?>>> documentEvents =
          <DocumentSnapshot<Map<String, Object?>>>[];
      final StreamSubscription<DocumentSnapshot<Map<String, Object?>>> sub = db
          .documentSnapshotsFromJson<Map<String, Object?>>(documentJson,
              options: metadata)
          .listen(documentEvents.add);
      expect(documentEvents, isEmpty);
      final DocumentSnapshot<Map<String, Object?>> first = await waitFor(
          documentEvents, (DocumentSnapshot<Map<String, Object?>> s) => true);
      expect(first.data, docA);
      await collection.doc('a').set(<String, Object?>{'n': 1, 's': 'uno'});
      await waitFor(
          documentEvents,
          (DocumentSnapshot<Map<String, Object?>> s) =>
              s.data?['s'] == 'uno' && !s.metadata.isFromCache);
      await sub.cancel();
      await collection.doc('a').set(docA);

      // A missing document: the JS SDK writes an empty bundle, which it cannot read back itself.
      final Map<String, Object?> missingJson =
          asMap(snapshots['missingDocument']);
      expect(missingJson['bundle'], '');
      final DocumentSnapshot<Map<String, Object?>> missing =
          DocumentSnapshot<Map<String, Object?>>.fromJson(db, missingJson);
      expect(missing.exists, isFalse);
      expect(missing.reference.path, '$name/missing');

      // Queries: the documents, the query and what the resumed listener is in sync with.
      Future<QuerySnapshot<Map<String, Object?>>> check(
        String key,
        List<String> expectedIds, {
        Query<Map<String, Object?>>? expectedQuery,
        List<String>? expectedResumedIds,
      }) async {
        final Map<String, Object?> json = asMap(snapshots[key]);
        final QuerySnapshot<Map<String, Object?>> snapshot =
            QuerySnapshot<Map<String, Object?>>.fromJson(db, json);
        expect(ids(snapshot), expectedIds, reason: '$key: fromJson');
        if (expectedQuery != null) {
          expect(snapshot.query, expectedQuery, reason: '$key: query');
        }
        expect(await resumeQuery(db, json), expectedResumedIds ?? expectedIds,
            reason: '$key: resume');
        return snapshot;
      }

      final QuerySnapshot<Map<String, Object?>> all = await check(
          'query', <String>['a', 'b', 'c'],
          expectedQuery: collection.orderBy('n'));
      expect(all.docs[0].data, docA);
      expect(all.docs[2].data, <String, Object?>{'n': 3, 's': threeText});

      await check('limit', <String>['a', 'b'],
          expectedQuery: collection.orderBy('n').limit(2));
      await check('filter', <String>['c', 'b'],
          expectedQuery: collection
              .where('n', isGreaterThanOrEqualTo: 2)
              .orderBy('n', Direction.descending));
      await check('or', <String>['a', 'c'],
          expectedQuery: collection.where(Filter.or(<Filter>[
            Filter.equalTo('n', 1),
            Filter.equalTo('n', 3),
          ])));
      await check('collectionGroup', <String>['x', 'y'],
          expectedQuery: db.collectionGroup('sub-$name').orderBy('n'));
      await check('empty', <String>[],
          expectedQuery: collection.where('n', isGreaterThan: 100));

      // JS SDK limitation: toJSON() of a limitToLast() query writes the query it sends to the backend (inverted
      // orders, limit to first) without the 'LAST' limit type. The snapshot holds the right documents, but they
      // and the resumed listener are in the inverted order. querySnapshotFromJSON() of the JS SDK reads the same.
      await check('limitToLast', <String>['c', 'b'],
          expectedQuery:
              collection.orderBy('n', Direction.descending).limit(2));

      // JS SDK bug: toJSON() of a subcollection query writes the database root as the parent, so the query read
      // back is the one of a root collection with the same id. The snapshot still holds the documents, but the
      // resumed listener is on the wrong (empty) collection. querySnapshotFromJSON() of the JS SDK reads the same.
      await check('subcollection', <String>['x', 'y'],
          expectedQuery: db.collection('sub-$name').orderBy('n'),
          expectedResumedIds: <String>[]);
    });

    test('written by toJson is read by the JS SDK and resumed', () async {
      final String name = uniqueName('dartSnapshots');
      final Firestore db = await IntegrationTestUtil.testFirestore();
      final CollectionReference<Map<String, Object?>> collection =
          db.collection(name);
      await collection.doc('a').set(docA);
      await collection.doc('b').set(<String, Object?>{'n': 2, 's': 'two'});
      await collection.doc('c').set(<String, Object?>{'n': 3, 's': threeText});
      final CollectionReference<Map<String, Object?>> sub =
          db.collection('$name/a/sub-$name');
      await sub.doc('x').set(<String, Object?>{'n': 10});
      await sub.doc('y').set(<String, Object?>{'n': 20});

      final Map<String, Query<Map<String, Object?>>> queries =
          <String, Query<Map<String, Object?>>>{
        'query': collection.orderBy('n'),
        'limit': collection.orderBy('n').limit(2),
        'limitToLast': collection.orderBy('n').limitToLast(2),
        'filter': collection
            .where('n', isGreaterThanOrEqualTo: 2)
            .orderBy('n', Direction.descending),
        'or': collection.where(Filter.or(<Filter>[
          Filter.equalTo('n', 1),
          Filter.equalTo('n', 3),
        ])),
        'subcollection': sub.orderBy('n'),
        'collectionGroup': db.collectionGroup('sub-$name').orderBy('n'),
        'empty': collection.where('n', isGreaterThan: 100),
      };
      const Map<String, List<String>> expectedIds = <String, List<String>>{
        'query': <String>['a', 'b', 'c'],
        'limit': <String>['a', 'b'],
        'limitToLast': <String>['b', 'c'],
        'filter': <String>['c', 'b'],
        'or': <String>['a', 'c'],
        'subcollection': <String>['x', 'y'],
        'collectionGroup': <String>['x', 'y'],
        'empty': <String>[],
      };

      final Map<String, Object?> snapshots = <String, Object?>{
        'document': (await collection.doc('a').get()).toJson(),
        'missingDocument': (await collection.doc('missing').get()).toJson(),
      };
      for (final MapEntry<String, Query<Map<String, Object?>>> entry
          in queries.entries) {
        final QuerySnapshot<Map<String, Object?>> snapshot =
            await entry.value.get();
        expect(ids(snapshot), expectedIds[entry.key], reason: entry.key);
        snapshots[entry.key] = snapshot.toJson();
      }

      final Map<String, Object?> result = await runHarness(
          'read-snapshots', <String, Object?>{'snapshots': snapshots});

      // The document.
      final Map<String, Object?> document = asMap(result['document']);
      expect(asMap(document['fromJson']), <String, Object?>{
        'exists': true,
        'path': '$name/a',
        'data': normalize(describe(docA), jsNumbers: true),
      });
      final List<Object?> documentEvents =
          asList(asMap(document['resume'])['events']);
      expect(asMap(documentEvents.first)['data'],
          normalize(describe(docA), jsNumbers: true));
      expect(asMap(documentEvents.last)['fromCache'], isFalse);

      // JS SDK limitation: it cannot read the empty bundle of a missing document, not even its own.
      final Map<String, Object?> missing = asMap(result['missingDocument']);
      expect(asMap(missing['fromJson'])['error'], isA<String>(),
          reason: 'The JS SDK now reads a missing document: $missing');
      expect(asMap(missing['resume'])['error'],
          contains("snapshotJson field 'bundle' cannot be an empty string"));

      // The queries: documents in the order of the query, then the listener in sync with the backend.
      for (final String key in queries.keys) {
        final Map<String, Object?> entry = asMap(result[key]);
        final Map<String, Object?> fromJson = asMap(entry['fromJson']);
        expect(fromJson['error'], isNull, reason: '$key: fromJSON');
        expect(jsIds(fromJson['docs']), expectedIds[key],
            reason: '$key: fromJSON');
        final Map<String, Object?> resume = asMap(entry['resume']);
        expect(resume['error'], isNull, reason: '$key: onSnapshotResume');
        final List<Object?> events = asList(resume['events']);
        expect(jsIds(asMap(events.last)['docs']), expectedIds[key],
            reason: '$key: onSnapshotResume');
        if (expectedIds[key]!.isNotEmpty) {
          // The first event comes from the documents of the bundle.
          expect(jsIds(asMap(events.first)['docs']), expectedIds[key],
              reason: '$key: first event');
        }
      }
      final Map<String, Object?> allDocs = asMap(result['query']);
      expect(
          asMap(asList(asMap(allDocs['fromJson'])['docs'])[2])['data'],
          normalize(describe(<String, Object?>{'n': 3, 's': threeText}),
              jsNumbers: true));
    });
  }, skip: skip);

  group('value JSON', () {
    test('toJSON of the JS SDK is read by fromJson, and the reverse', () async {
      final Firestore db = await IntegrationTestUtil.testFirestore();
      final Map<String, Object?> js = await runHarness('values-to-json');

      const Timestamp timestamp = Timestamp(1234567890, 123456789);
      const Timestamp negativeTimestamp = Timestamp(-62135596800, 0);
      const GeoPoint geoPoint = GeoPoint(12.5, -77.25);
      final Blob bytes = Blob(Uint8List.fromList(<int>[0, 1, 2, 254, 255]));
      final Blob emptyBytes = Blob(Uint8List(0));
      final DocumentReference<Map<String, Object?>> reference =
          db.doc('rooms/eros/messages/1');
      final VectorValue vector = VectorValue(<double>[1, 2.5, -3]);
      final VectorValue emptyVector = VectorValue(<double>[]);

      // JS -> Dart.
      expect(Timestamp.fromJson(asMap(js['timestamp'])), timestamp);
      expect(Timestamp.fromJson(asMap(js['negativeTimestamp'])),
          negativeTimestamp);
      expect(GeoPoint.fromJson(asMap(js['geoPoint'])), geoPoint);
      expect(Blob.fromJson(asMap(js['bytes'])), bytes);
      expect(Blob.fromJson(asMap(js['emptyBytes'])), emptyBytes);
      expect(
          DocumentReference<Map<String, Object?>>.fromJson(
              db, asMap(js['documentReference'])),
          reference);
      expect(VectorValue.fromJson(asMap(js['vector'])), vector);
      expect(VectorValue.fromJson(asMap(js['emptyVector'])), emptyVector);

      // The JSON objects are the same (after encoding: 1.0 and 1 are the same JSON number for the reader).
      final Map<String, Object?> dart = <String, Object?>{
        'timestamp': timestamp.toJson(),
        'negativeTimestamp': negativeTimestamp.toJson(),
        'geoPoint': geoPoint.toJson(),
        'bytes': bytes.toJson(),
        'emptyBytes': emptyBytes.toJson(),
        'documentReference': reference.toJson(),
        'vector': vector.toJson(),
        'emptyVector': emptyVector.toJson(),
      };
      Object? numbersAsDoubles(Object? value) {
        if (value is num) {
          return value.toDouble();
        } else if (value is List) {
          return value.map(numbersAsDoubles).toList();
        } else if (value is Map) {
          return value.map((dynamic k, dynamic v) =>
              MapEntry<String, Object?>(k as String, numbersAsDoubles(v)));
        }
        return value;
      }

      expect(
          numbersAsDoubles(jsonDecode(jsonEncode(dart))), numbersAsDoubles(js));

      // Dart -> JS.
      final Map<String, Object?> read = await runHarness('values-from-json',
          <String, Object?>{'values': jsonDecode(jsonEncode(dart))});
      final Map<String, Object?> expected = <String, Object?>{
        'timestamp': describe(timestamp),
        'negativeTimestamp': describe(negativeTimestamp),
        'geoPoint': describe(geoPoint),
        'bytes': describe(bytes),
        'emptyBytes': describe(emptyBytes),
        'documentReference': describe(reference),
        'vector': describe(vector),
        'emptyVector': describe(emptyVector),
      };
      expect(normalize(read, jsNumbers: true),
          normalize(expected, jsNumbers: true));
    });
  }, skip: skip);

  group('bundles', () {
    test('built by firebase-admin are loaded by loadBundle', () async {
      final String name = uniqueName('adminBundle');
      final Map<String, Object?> result =
          await runHarness('build-bundle', <String, Object?>{
        'collection': name,
        'bundleId': 'bundle-$name',
        'bundleFile': 'admin.bundle',
      });
      final Uint8List bundle = result['bundleBytes']! as Uint8List;
      expect(bundle.length, result['bytes']);

      final Firestore db = await IntegrationTestUtil.testFirestore();
      await db.disableNetwork();
      final LoadBundleTaskProgress progress =
          await db.loadBundle(bundle).future;
      expect(progress.taskState, LoadBundleTaskState.success);
      // a, b, c and the missing document.
      expect(progress.totalDocuments, 4);
      expect(progress.documentsLoaded, 4);
      expect(progress.bytesLoaded, progress.totalBytes);

      final CollectionReference<Map<String, Object?>> collection =
          db.collection(name);
      Future<QuerySnapshot<Map<String, Object?>>> named(
          String queryName) async {
        final Query<Map<String, Object?>>? query =
            await db.getNamedQuery(queryName);
        expect(query, isNotNull, reason: queryName);
        return query!.get(Source.cache);
      }

      final QuerySnapshot<Map<String, Object?>> all = await named('all');
      expect(all.query, collection.orderBy('n'));
      expect(ids(all), <String>['a', 'b', 'c']);
      expect(
          describe(all.docs[0].data),
          describe(<String, Object?>{
            'n': 1,
            's': 'one',
            // The backend keeps microseconds.
            'when': const Timestamp(100, 5000),
          }));
      expect(
          describe(all.docs[1].data),
          describe(<String, Object?>{
            'n': 2,
            's': 'two \u{1F60A}',
            'where': const GeoPoint(1, 2),
          }));
      expect(
          describe(all.docs[2].data),
          describe(<String, Object?>{
            'n': 3,
            'ref': collection.doc('a'),
            'bytes': Blob(Uint8List.fromList(<int>[1, 2, 3])),
            'list': <Object?>[1, 'x', null],
          }));

      final QuerySnapshot<Map<String, Object?>> lastTwo =
          await named('last-two');
      expect(lastTwo.query, collection.orderBy('n').limitToLast(2));
      expect(ids(lastTwo), <String>['b', 'c']);

      final QuerySnapshot<Map<String, Object?>> firstOne =
          await named('first-one');
      expect(firstOne.query,
          collection.orderBy('n', Direction.descending).limit(1));
      expect(ids(firstOne), <String>['c']);

      expect((await collection.doc('a').get(Source.cache)).data?['s'], 'one');
      // The missing document is known to be missing.
      expect(
          (await collection.doc('missing').get(Source.cache)).exists, isFalse);

      // Back online, a bundled query is listened to and in sync with the backend.
      await db.enableNetwork();
      final QuerySnapshot<Map<String, Object?>> server =
          await (await db.getNamedQuery('last-two'))!.get(Source.server);
      expect(ids(server), <String>['b', 'c']);
    });
  }, skip: skip);

  group('data', () {
    /// Every supported value type. [jsWritable] is false for the values the JS SDK cannot write.
    Map<String, Map<String, Object?>> allTypes(String refPath,
        {required bool jsWritable}) {
      // Written by the Dart SDK over the web transport, -0.0 arrives as 0.0:
      // the JSON endpoints of the emulator (v1.22.0) drop the sign, whatever
      // the client sends (`-0.0`, `-0`, `"-0"`). The JS SDK writes over gRPC.
      final bool dartWritesJson = !jsWritable &&
          (Platform.environment['FIRESTORE_TEST_TRANSPORT'] ?? '')
              .startsWith('webchannel');
      final double negativeZero = dartWritesJson ? 0.0 : -0.0;
      return <String, Map<String, Object?>>{
        'null': nullSpec(),
        'true': boolSpec(true),
        'false': boolSpec(false),
        'intZero': intSpec(0),
        'intOne': intSpec(1),
        'intNegative': intSpec(-42),
        'intMaxSafe': intSpec(9007199254740991),
        'intMinSafe': intSpec(-9007199254740991),
        if (!jsWritable) ...<String, Map<String, Object?>>{
          'int64Max': intSpec(9223372036854775807),
          'int64Min': intSpec(-9223372036854775808),
        },
        'double': doubleSpec(1.5),
        'doubleIntegral': doubleSpec(3.0),
        'doubleNegativeZero': doubleSpec(negativeZero),
        'doubleZero': doubleSpec(0.0),
        'doubleNaN': doubleSpec(double.nan),
        'doubleInfinity': doubleSpec(double.infinity),
        'doubleNegativeInfinity': doubleSpec(double.negativeInfinity),
        'doubleMax': doubleSpec(double.maxFinite),
        'doubleMin': doubleSpec(double.minPositive),
        'doubleLarge': doubleSpec(1e300),
        'string': stringSpec('text'),
        'stringEmpty': stringSpec(''),
        'stringUnicode': stringSpec('é € \u{1F60A} ￿ \u{10000}'),
        // The backend keeps microseconds.
        'timestamp': timestampSpec(1234567890, 123456000),
        'timestampEpoch': timestampSpec(0, 0),
        'timestampNegative': timestampSpec(-12345, 999999000),
        'timestampMin': timestampSpec(-62135596800, 0),
        'timestampMax': timestampSpec(253402300799, 999999000),
        'geoPoint': geoSpec(12.5, -77.25),
        'geoPointEdges': geoSpec(-90, 180),
        'bytes': bytesSpec(<int>[0, 1, 2, 127, 128, 254, 255]),
        'bytesEmpty': bytesSpec(<int>[]),
        'reference': refSpec(refPath),
        'vector': vectorSpec(<double>[1, 2.5, -3, 1e-10]),
        'array': arraySpec(<Map<String, Object?>>[
          intSpec(1),
          stringSpec('a'),
          nullSpec(),
          doubleSpec(double.nan),
          mapSpec(<String, Map<String, Object?>>{
            'inner': arraySpec(<Map<String, Object?>>[boolSpec(true)]),
          }),
          timestampSpec(1, 1000),
          geoSpec(1, 2),
          bytesSpec(<int>[9]),
          refSpec(refPath),
        ]),
        'arrayEmpty': arraySpec(<Map<String, Object?>>[]),
        'map': mapSpec(<String, Map<String, Object?>>{
          'a': intSpec(1),
          'nested': mapSpec(<String, Map<String, Object?>>{
            'deep': mapSpec(<String, Map<String, Object?>>{
              'deeper': arraySpec(<Map<String, Object?>>[
                stringSpec('x'),
                doubleSpec(negativeZero),
              ]),
            }),
          }),
          'key with spaces. and dots': stringSpec('v'),
          'é\u{1F60A}': nullSpec(),
        }),
        'mapEmpty': mapSpec(<String, Map<String, Object?>>{}),
      };
    }

    test('written by the Dart SDK is read by the JS SDK', () async {
      final String name = uniqueName('dartData');
      final Firestore db = await IntegrationTestUtil.testFirestore();
      final Map<String, Object?> spec =
          mapSpec(allTypes('$name/other', jsWritable: false));
      await db
          .collection(name)
          .doc('all')
          .set(build(db, spec)! as Map<String, Object?>);

      final Map<String, Object?> result =
          await runHarness('read-data', <String, Object?>{'collection': name});
      final Map<String, Object?> data =
          asMap(asMap(asMap(asList(result['docs']).single)['data'])['v']);
      final Map<String, Object?> expected =
          asMap(asMap(normalize(spec, jsNumbers: true))['v']);

      // JS SDK limitation: integers outside of the safe range are read as the nearest double.
      expect(asMap(data.remove('int64Max'))['v'],
          doubleToString(9223372036854775807.toDouble()));
      expect(asMap(data.remove('int64Min'))['v'],
          doubleToString(-9223372036854775807.toDouble()));
      expected
        ..remove('int64Max')
        ..remove('int64Min');

      expect(data.keys.toSet(), expected.keys.toSet());
      for (final String key in expected.keys) {
        expect(data[key], expected[key], reason: key);
      }

      // The same document through toJson(): every value type in the bundle is read by the JS SDK.
      final Map<String, Object?> snapshots =
          await runHarness('read-snapshots', <String, Object?>{
        'snapshots': <String, Object?>{
          'all': (await db.collection(name).doc('all').get()).toJson(),
        },
      });
      final Map<String, Object?> fromJson =
          asMap(asMap(snapshots['all'])['fromJson']);
      expect(fromJson['error'], isNull);
      final Map<String, Object?> jsonData = asMap(asMap(fromJson['data'])['v']);
      // The bundle keeps the integers as strings, but the JS SDK still reads them as doubles.
      jsonData
        ..remove('int64Max')
        ..remove('int64Min');
      expect(jsonData.keys.toSet(), expected.keys.toSet());
      for (final String key in expected.keys) {
        expect(jsonData[key], expected[key], reason: 'toJson: $key');
      }
    });

    test('written by the JS SDK is read by the Dart SDK', () async {
      final String name = uniqueName('jsData');
      final Map<String, Object?> spec =
          mapSpec(allTypes('$name/other', jsWritable: true));
      final Map<String, Object?> written =
          await runHarness('write-data', <String, Object?>{
        'collection': name,
        'documents': <String, Object?>{'all': spec},
      });

      final Firestore db = await IntegrationTestUtil.testFirestore();
      final DocumentSnapshot<Map<String, Object?>> snapshot =
          await db.collection(name).doc('all').get();
      final Map<String, Object?> data = asMap(
          asMap(normalize(describe(snapshot.data), jsNumbers: false))['v']);
      // The JS SDK writes a double that is a safe integer (but not -0) as an integer.
      final Map<String, Object?> expected =
          asMap(asMap(normalize(afterJsWrite(spec), jsNumbers: false))['v']);
      expect(asMap(expected['doubleIntegral'])['t'], 'int');
      expect(asMap(expected['doubleZero'])['t'], 'int');
      expect(asMap(expected['doubleNegativeZero'])['t'], 'double');

      expect(data.keys.toSet(), expected.keys.toSet());
      for (final String key in expected.keys) {
        expect(data[key], expected[key], reason: key);
      }

      // The same document through toJSON() of the JS SDK: every value type in its bundle is read by fromJson.
      final DocumentSnapshot<Map<String, Object?>> fromJson =
          DocumentSnapshot<Map<String, Object?>>.fromJson(
              db, asMap(asMap(written['snapshots'])['all']));
      final Map<String, Object?> jsonData = asMap(
          asMap(normalize(describe(fromJson.data), jsNumbers: false))['v']);
      expect(jsonData.keys.toSet(), expected.keys.toSet());
      for (final String key in expected.keys) {
        expect(jsonData[key], expected[key], reason: 'toJSON: $key');
      }
    });

    test('both SDKs order a mixed-type field the same way', () async {
      final String name = uniqueName('mixedOrder');
      final Firestore db = await IntegrationTestUtil.testFirestore();
      final CollectionReference<Map<String, Object?>> collection =
          db.collection(name);

      // In the order of the backend. Values that compare equal share a rank (they are ordered by document id).
      final List<(int, Map<String, Object?>)> values =
          <(int, Map<String, Object?>)>[
        (0, nullSpec()),
        (1, boolSpec(false)),
        (2, boolSpec(true)),
        (3, doubleSpec(double.nan)),
        (4, doubleSpec(double.negativeInfinity)),
        (5, intSpec(-9223372036854775808)),
        (6, doubleSpec(-1.5)),
        (7, intSpec(-1)),
        (8, doubleSpec(-0.0)),
        (8, intSpec(0)),
        (8, doubleSpec(0.0)),
        (9, doubleSpec(double.minPositive)),
        (10, doubleSpec(0.5)),
        (11, intSpec(1)),
        (11, doubleSpec(1.0)),
        (12, intSpec(9007199254740993)),
        (13, intSpec(9223372036854775807)),
        (14, doubleSpec(1e300)),
        (15, doubleSpec(double.infinity)),
        (16, timestampSpec(-1, 0)),
        (17, timestampSpec(0, 1000)),
        (18, timestampSpec(1, 0)),
        (19, stringSpec('')),
        (20, stringSpec('A')),
        (21, stringSpec('a')),
        (22, stringSpec('aa')),
        (23, stringSpec('b')),
        (24, stringSpec('é')),
        // UTF-8 order, not UTF-16 code unit order: U+FFFF sorts before U+10000.
        (25, stringSpec('￿')),
        (26, stringSpec('\u{10000}')),
        (27, bytesSpec(<int>[])),
        (28, bytesSpec(<int>[0])),
        (29, bytesSpec(<int>[0, 1])),
        (30, bytesSpec(<int>[1])),
        (31, bytesSpec(<int>[255])),
        (32, refSpec('$name/a')),
        (33, refSpec('$name/a/sub/a')),
        (34, refSpec('$name/b')),
        (35, geoSpec(-90, 0)),
        (36, geoSpec(0, -180)),
        (37, geoSpec(0, 0)),
        (38, geoSpec(0, 180)),
        (39, geoSpec(90, 0)),
        (40, arraySpec(<Map<String, Object?>>[])),
        (41, arraySpec(<Map<String, Object?>>[nullSpec()])),
        (42, arraySpec(<Map<String, Object?>>[intSpec(1)])),
        (43, arraySpec(<Map<String, Object?>>[intSpec(1), intSpec(0)])),
        (44, arraySpec(<Map<String, Object?>>[intSpec(2)])),
        (45, arraySpec(<Map<String, Object?>>[stringSpec('a')])),
        (46, vectorSpec(<double>[100])),
        (47, vectorSpec(<double>[1, 2])),
        (48, vectorSpec(<double>[1, 3])),
        (49, vectorSpec(<double>[1, 2, 3])),
        (50, mapSpec(<String, Map<String, Object?>>{})),
        (51, mapSpec(<String, Map<String, Object?>>{'a': intSpec(1)})),
        (52, mapSpec(<String, Map<String, Object?>>{'a': intSpec(2)})),
        (
          53,
          mapSpec(
              <String, Map<String, Object?>>{'a': intSpec(2), 'b': nullSpec()})
        ),
        (54, mapSpec(<String, Map<String, Object?>>{'b': intSpec(0)})),
      ];

      // Document ids that do not follow the order of the values.
      final Map<String, int> ranks = <String, int>{};
      for (int i = 0; i < values.length; i++) {
        final String id =
            'doc${((i * 37) % values.length).toString().padLeft(3, '0')}';
        expect(ranks.containsKey(id), isFalse);
        ranks[id] = values[i].$1;
        await collection
            .doc(id)
            .set(<String, Object?>{'v': build(db, values[i].$2)});
      }
      final List<String> expected = ranks.keys.toList()
        ..sort((String a, String b) {
          final int rank = ranks[a]!.compareTo(ranks[b]!);
          return rank != 0 ? rank : a.compareTo(b);
        });

      // The documents of a snapshot are ordered by the SDK (not by the order the backend sent them in).
      final List<String> dart = ids(await collection.orderBy('v').get());
      final Map<String, Object?> result = await runHarness(
          'read-data', <String, Object?>{'collection': name, 'orderBy': 'v'});
      final List<String> js = jsIds(result['docs']);

      expect(dart, expected, reason: 'Dart SDK order');
      expect(js, expected, reason: 'JS SDK order');
      expect(dart, js);

      // Also with the documents only in the cache, where the Dart SDK alone orders and filters them.
      final List<String> cached =
          ids(await collection.orderBy('v').get(Source.cache));
      expect(cached, expected, reason: 'Dart SDK order from cache');
    });
  }, skip: skip);
}
