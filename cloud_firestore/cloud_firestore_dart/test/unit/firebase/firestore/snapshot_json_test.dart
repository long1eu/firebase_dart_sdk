// Copyright 2025 Google LLC
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

// Port of the JS SDK unit tests of DocumentSnapshot/QuerySnapshot toJSON() and fromJSON() (test/unit/api/database.test.ts),
// plus checks of the bundle format and of the read time.

import 'dart:convert';

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_element.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_metadata.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_reader.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundled_document_metadata.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundled_query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/named_query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/bound.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/document_view_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/filter/filter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart'
    as core;
import 'package:cloud_firestore_dart/src/firebase/firestore/core/view.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/view_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/document_reference.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/document_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/geo_point.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_set.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/vector_value.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:test/test.dart';

import '../../../util/test_util.dart' as util;

Firestore _testFirestore(DatabaseId databaseId) =>
    FirestoreInternal.detached(databaseId);

final Firestore firestore = _testFirestore(DatabaseId.forProject('project'));

DocumentSnapshot<Map<String, Object?>> documentSnapshot(
  String path,
  Map<String, Object?>? data, {
  bool hasPendingWrites = false,
}) {
  if (data == null) {
    return DocumentSnapshotInternal.fromNoDocument<Map<String, Object?>>(
        firestore, util.key(path),
        isFromCache: true, hasPendingWrites: hasPendingWrites);
  }
  return DocumentSnapshotInternal.fromDocument<Map<String, Object?>>(
      firestore, util.doc(path, 1000, data),
      isFromCache: true, hasPendingWrites: hasPendingWrites);
}

QuerySnapshot<Map<String, Object?>> querySnapshot(
  core.Query query,
  List<Document> docs, {
  SnapshotVersion readTime = SnapshotVersion.none,
  bool hasPendingWrites = false,
}) {
  DocumentSet documents = DocumentSet.emptySet(query.comparator);
  ImmutableSortedSet<DocumentKey> mutatedKeys = DocumentKey.emptyKeySet;
  for (final Document doc in docs) {
    documents = documents.add(doc);
    if (hasPendingWrites) {
      mutatedKeys = mutatedKeys.insert(doc.key);
    }
  }
  final ViewSnapshot snapshot = ViewSnapshot.fromInitialDocuments(
    query,
    documents,
    mutatedKeys,
    isFromCache: false,
    excludesMetadataChanges: false,
    hasCachedResults: false,
    readTime: readTime,
  );
  return QuerySnapshotInternal.create<Map<String, Object?>>(
      QueryInternal.create<Map<String, Object?>>(query, firestore), snapshot, firestore);
}

Matcher throwsFirestoreError(FirestoreErrorCode code, [Object? message]) {
  Matcher matcher =
      isA<FirestoreError>().having((FirestoreError e) => e.code, 'code', code);
  if (message != null) {
    matcher = allOf(
        matcher,
        isA<FirestoreError>()
            .having((FirestoreError e) => e.message, 'message', message));
  }
  return throwsA(matcher);
}

/// Reads [bundle] with the streaming [BundleReader] used by `loadBundle`.
Future<List<BundleElement>> readBundle(String bundle) async {
  final BundleReader reader = BundleReader.fromBytes(
      BundleSerializer(RemoteSerializer(firestore.modelDatabaseId)),
      utf8.encode(bundle));
  final List<BundleElement> elements = <BundleElement>[
    await reader.getBundleMetadata()
  ];
  BundleElement? element;
  while ((element = await reader.getNextElement()) != null) {
    elements.add(element!);
  }
  return elements;
}

void main() {
  group('DocumentSnapshot', () {
    test('toJson includes the JSON fields and a bundle', () {
      final Map<String, Object?> json =
          documentSnapshot('foo/bar', <String, Object?>{'a': 1}).toJson();
      expect(json['type'], 'firestore/documentSnapshot/1.0');
      expect(json['bundleSource'], 'DocumentSnapshot');
      expect(json['bundleName'], 'foo/bar');
      expect(json['bundle'], isA<String>());
      expect((json['bundle']! as String).length, greaterThan(0));
      // The object is JSON-serializable.
      expect(jsonDecode(jsonEncode(json)), json);
    });

    test('toJson returns an empty bundle when the document is missing', () {
      final Map<String, Object?> json =
          documentSnapshot('foo/bar', null).toJson();
      expect(json['bundle'], '');
      expect(json['bundleName'], 'foo/bar');
    });

    test('toJson throws when there are pending writes', () {
      expect(
          () => documentSnapshot('foo/bar', <String, Object?>{},
                  hasPendingWrites: true)
              .toJson(),
          throwsFirestoreError(
              FirestoreErrorCode.failedPrecondition,
              'DocumentSnapshot.toJson() attempted to serialize a document with pending writes. '
              'Await waitForPendingWrites() before invoking toJson().'));
    });

    test('the bundle is a valid bundle', () async {
      final Map<String, Object?> json =
          documentSnapshot('foo/bar', <String, Object?>{'a': 1}).toJson();
      final List<BundleElement> elements =
          await readBundle(json['bundle']! as String);
      expect(elements, hasLength(3));
      final BundleMetadata metadata = elements[0] as BundleMetadata;
      expect(metadata.schemaVersion, 1);
      expect(metadata.totalDocuments, 1);
      // totalBytes counts everything after the metadata element.
      final List<int> bytes = utf8.encode(json['bundle']! as String);
      final int openBracket = bytes.indexOf(0x7B);
      final int metadataLength =
          openBracket + int.parse(utf8.decode(bytes.sublist(0, openBracket)));
      expect(metadata.totalBytes, bytes.length - metadataLength);
      final BundledDocumentMetadata documentMetadata =
          elements[1] as BundledDocumentMetadata;
      expect(documentMetadata.key, util.key('foo/bar'));
      expect(documentMetadata.exists, isTrue);
      expect(documentMetadata.readTime, util.version(1000));
    });

    test('fromJson parses the toJson result', () {
      final DocumentSnapshot<Map<String, Object?>> snapshot =
          documentSnapshot('foo/bar', <String, Object?>{'a': 1});
      final DocumentSnapshot<Map<String, Object?>> fromJson =
          DocumentSnapshot<Map<String, Object?>>.fromJson(
              firestore, snapshot.toJson());
      expect(fromJson.exists, isTrue);
      expect(fromJson.id, 'bar');
      expect(fromJson.reference.path, 'foo/bar');
      expect(fromJson.data, <String, Object?>{'a': 1});
      expect(fromJson.metadata.isFromCache, isFalse);
      expect(fromJson.metadata.hasPendingWrites, isFalse);
      expect(fromJson.document!.version, util.version(1000));
    });

    test('fromJson of a missing document is a missing document', () {
      final DocumentSnapshot<Map<String, Object?>> fromJson =
          DocumentSnapshot<Map<String, Object?>>.fromJson(
              firestore, documentSnapshot('foo/bar', null).toJson());
      expect(fromJson.exists, isFalse);
      expect(fromJson.reference.path, 'foo/bar');
    });

    // Found by the interop tests with the JS SDK: toProto3Json() of the generated protos loses both.
    test('keeps an empty blob and the sign of -0.0', () {
      final DocumentSnapshot<Map<String, Object?>> snapshot =
          documentSnapshot('coll/doc', <String, Object?>{
        'emptyBlob': util.blob(),
        'negativeZero': -0.0,
        'zero': 0.0,
        'integral': 3.0,
        'nested': <Object?>[
          -0.0,
          util.blob(),
          <String, Object?>{'emptyMap': <String, Object?>{}}
        ],
      });
      final Map<String, Object?> json = snapshot.toJson();
      final String bundle = json['bundle']! as String;
      expect(bundle, contains('"emptyBlob":{"bytesValue":""}'));
      expect(bundle, contains('"negativeZero":{"doubleValue":"-0"}'));
      expect(
          bundle,
          contains('{"arrayValue":{"values":[{"doubleValue":"-0"},'
              '{"bytesValue":""},'
              '{"mapValue":{"fields":{"emptyMap":{"mapValue":{"fields":{}}}}}}]}}'));

      final Map<String, Object?> data =
          DocumentSnapshot<Map<String, Object?>>.fromJson(firestore, json)
              .data!;
      expect(data['emptyBlob'], util.blob());
      expect((data['negativeZero']! as double).isNegative, isTrue);
      expect(data['zero'], isA<double>());
      expect((data['zero']! as double).isNegative, isFalse);
      expect(data['integral'], isA<double>());
      expect(((data['nested']! as List<Object?>)[0]! as double).isNegative,
          isTrue);
      expect((data['nested']! as List<Object?>)[1], util.blob());
    });

    test('fromJson round-trips every value type', () {
      final Map<String, Object?> data = <String, Object?>{
        'null': null,
        'bool': true,
        'false': false,
        'int': 1,
        'zero': 0,
        'maxInt': 9223372036854775807,
        'double': 1.5,
        'zeroDouble': 0.0,
        'nan': double.nan,
        'infinity': double.infinity,
        'string': 'text',
        'empty': '',
        'timestamp': const Timestamp(1234, 5678),
        'geoPoint': const GeoPoint(1.5, -2.5),
        'blob': util.blob(<int>[1, 2, 3]),
        'reference': util.ref('coll/doc'),
        'array': <Object?>[
          1,
          'a',
          <String, Object?>{'b': true}
        ],
        'emptyArray': <Object?>[],
        'map': <String, Object?>{
          'nested': <String, Object?>{'deep': 1}
        },
        'emptyMap': <String, Object?>{},
        'vector': VectorValue(<double>[1, 2, 3]),
      };
      final DocumentSnapshot<Map<String, Object?>> snapshot =
          documentSnapshot('coll/doc', data);
      final DocumentSnapshot<Map<String, Object?>> fromJson =
          DocumentSnapshot<Map<String, Object?>>.fromJson(
              firestore,
              jsonDecode(jsonEncode(snapshot.toJson()))
                  as Map<String, Object?>);
      expect(fromJson.document!.data, snapshot.document!.data);
    });

    // Regression test for https://github.com/firebase/firebase-js-sdk/issues/10557
    for (final String value in <String>['é', '€', '\u{1F60A}']) {
      test('fromJson round-trips a multi-byte value ${value.runes.first}', () {
        final String path = 'coll$value/doc$value';
        final Map<String, Object?> data = <String, Object?>{
          'v': value,
          'nested': <String, Object?>{
            'k$value': <Object?>[value]
          },
        };
        final DocumentSnapshot<Map<String, Object?>> fromJson =
            DocumentSnapshot<Map<String, Object?>>.fromJson(
                firestore, documentSnapshot(path, data).toJson());
        expect(fromJson.reference.path, path);
        expect(fromJson.data, data);
      });
    }

    group('fromJson validation', () {
      Map<String, Object?> valid() =>
          documentSnapshot('foo/bar', <String, Object?>{'a': 1}).toJson();

      void expectInvalid(Map<String, Object?> json, [Object? message]) {
        expect(
            () => DocumentSnapshot<Map<String, Object?>>.fromJson(
                firestore, json),
            throwsFirestoreError(FirestoreErrorCode.invalidArgument, message));
      }

      test('missing type', () {
        expectInvalid(
            valid()..remove('type'), "JSON missing required field: 'type'");
      });
      test('invalid type', () {
        expectInvalid(valid()..['type'] = 'firestore/querySnapshot/1.0',
            "Expected 'type' field to equal 'firestore/documentSnapshot/1.0'");
        expectInvalid(
            valid()..['type'] = 1, "JSON field 'type' must be a string.");
      });
      test('missing bundleSource', () {
        expectInvalid(valid()..remove('bundleSource'),
            "JSON missing required field: 'bundleSource'");
      });
      test('invalid bundleSource', () {
        expectInvalid(valid()..['bundleSource'] = 'QuerySnapshot',
            "Expected 'bundleSource' field to equal 'DocumentSnapshot'");
        expectInvalid(valid()..['bundleSource'] = true,
            "JSON field 'bundleSource' must be a string.");
      });
      test('missing bundleName', () {
        expectInvalid(valid()..remove('bundleName'),
            "JSON missing required field: 'bundleName'");
      });
      test('invalid bundleName', () {
        expectInvalid(valid()..['bundleName'] = 1,
            "JSON field 'bundleName' must be a string.");
        expectInvalid(valid()..['bundleName'] = 'foo');
        expectInvalid(valid()..['bundleName'] = 'foo/baz');
      });
      test('missing bundle', () {
        expectInvalid(
            valid()..remove('bundle'), "JSON missing required field: 'bundle'");
      });
      test('invalid bundle', () {
        expectInvalid(
            valid()..['bundle'] = 1, "JSON field 'bundle' must be a string.");
        expectInvalid(valid()..['bundle'] = 'BadData');
        expectInvalid(valid()..['bundle'] = '10{"a":1}');
      });
      test('a length prefix that is not plain decimal digits', () {
        final String bundle = valid()['bundle']! as String;
        final int brace = bundle.indexOf('{');
        final int length = int.parse(bundle.substring(0, brace));
        for (final String prefix in <String>[
          '0x${length.toRadixString(16)}',
          '+$length',
          ' $length',
        ]) {
          expectInvalid(
              valid()..['bundle'] = '$prefix${bundle.substring(brace)}');
        }
      });
      test('the error does not repeat a huge element', () {
        final String element = '{"unknown":"${'x' * 100000}"}';
        final String bundle =
            '${valid()['bundle']}${utf8.encode(element).length}$element';
        expectInvalid(
            valid()..['bundle'] = bundle,
            allOf(contains('Cannot decode unknown Bundle element'),
                hasLength(lessThan(1000))));
      });
      test('a bundle written outside of Node by the JS SDK', () {
        expectInvalid(
            valid()..['bundle'] = 'NOT SUPPORTED',
            'The provided JSON object was created in a client environment, '
            'which is not supported.');
      });
      test('a bundle of another project', () {
        final Firestore other =
            _testFirestore(DatabaseId.forProject('other-project'));
        final Map<String, Object?> json =
            documentSnapshot('foo/bar', <String, Object?>{'a': 1}).toJson();
        expect(
            () => DocumentSnapshot<Map<String, Object?>>.fromJson(other, json),
            throwsFirestoreError(FirestoreErrorCode.invalidArgument));
      });
    });
  });

  group('DocumentReference', () {
    test('toJson includes the JSON fields', () {
      final Map<String, Object> json = DocumentReferenceInternal.create<Map<String, Object?>>(
              util.key('foo/bar'), firestore)
          .toJson();
      expect(json, <String, Object>{
        'type': 'firestore/documentReference/1.0',
        'referencePath': 'foo/bar',
      });
    });

    test('fromJson equals the original reference', () {
      final DocumentReference<Map<String, Object?>> reference =
          DocumentReferenceInternal.create<Map<String, Object?>>(
              util.key('foo/bar/baz/qux'), firestore);
      final DocumentReference<Map<String, Object?>> fromJson =
          DocumentReference<Map<String, Object?>>.fromJson(
              firestore,
              jsonDecode(jsonEncode(reference.toJson()))
                  as Map<String, Object?>);
      expect(fromJson, reference);
      expect(fromJson.path, 'foo/bar/baz/qux');
      expect(fromJson.toJson(), reference.toJson());
    });

    test('fromJson throws with invalid data', () {
      for (final Map<String, Object?> json in <Map<String, Object?>>[
        <String, Object?>{},
        <String, Object?>{'referencePath': 'foo/bar'},
        <String, Object?>{'type': 1, 'referencePath': 'foo/bar'},
        <String, Object?>{
          'type': 'firestore/documentSnapshot/1.0',
          'referencePath': 'foo/bar'
        },
        <String, Object?>{'type': 'firestore/documentReference/1.0'},
        <String, Object?>{
          'type': 'firestore/documentReference/1.0',
          'referencePath': 1
        },
        <String, Object?>{
          'type': 'firestore/documentReference/1.0',
          'referencePath': 'foo'
        },
        <String, Object?>{
          'type': 'firestore/documentReference/1.0',
          'referencePath': ''
        },
      ]) {
        expect(
            () => DocumentReference<Map<String, Object?>>.fromJson(
                firestore, json),
            throwsArgumentError,
            reason: '$json');
      }
    });
  });

  group('QuerySnapshot', () {
    final List<Document> docs = <Document>[
      util.doc('coll/a', 1000, <String, Object?>{'foo': 1, 'sort': 2}),
      util.doc('coll/b', 2000, <String, Object?>{'bar': 2, 'sort': 1}),
    ];

    test('toJson includes the JSON fields and a bundle', () {
      final Map<String, Object?> json =
          querySnapshot(util.query('coll'), docs).toJson();
      expect(json['type'], 'firestore/querySnapshot/1.0');
      expect(json['bundleSource'], 'QuerySnapshot');
      expect(json['bundleName'], isA<String>());
      expect((json['bundleName']! as String).length, 20);
      expect((json['bundle']! as String).length, greaterThan(0));
      expect(jsonDecode(jsonEncode(json)), json);
    });

    test('toJson returns a bundle when there are no documents', () {
      final Map<String, Object?> json =
          querySnapshot(util.query('coll'), <Document>[]).toJson();
      expect((json['bundle']! as String).length, greaterThan(0));
      final QuerySnapshot<Map<String, Object?>> fromJson =
          QuerySnapshot<Map<String, Object?>>.fromJson(firestore, json);
      expect(fromJson, isEmpty);
    });

    test('toJson throws when there are pending writes', () {
      expect(
          () => querySnapshot(util.query('coll'), docs, hasPendingWrites: true)
              .toJson(),
          throwsFirestoreError(
              FirestoreErrorCode.failedPrecondition,
              'QuerySnapshot.toJson() attempted to serialize a document with pending writes. '
              'Await waitForPendingWrites() before invoking toJson().'));
    });

    test('the bundle is a valid bundle with the named query', () async {
      final SnapshotVersion readTime = util.version(5000);
      final Map<String, Object?> json =
          querySnapshot(util.query('coll'), docs, readTime: readTime).toJson();
      final List<BundleElement> elements =
          await readBundle(json['bundle']! as String);
      expect(elements, hasLength(6));
      final BundleMetadata metadata = elements[0] as BundleMetadata;
      expect(metadata.bundleId, json['bundleName']);
      expect(metadata.totalDocuments, 2);
      expect(metadata.createTime, readTime);
      final NamedQuery namedQuery = elements[1] as NamedQuery;
      expect(namedQuery.name, json['bundleName']);
      expect(namedQuery.readTime, readTime);
      expect(namedQuery.bundledQuery,
          BundledQuery(util.query('coll'), BundledQueryLimitType.first));
      for (final BundleElement element in elements.skip(2)) {
        if (element is BundledDocumentMetadata) {
          expect(element.queries, <String>[json['bundleName']! as String]);
          expect(element.readTime, readTime);
        }
      }
    });

    test('without a read time the documents are read at their version',
        () async {
      final Map<String, Object?> json =
          querySnapshot(util.query('coll'), docs).toJson();
      final List<BundleElement> elements =
          await readBundle(json['bundle']! as String);
      expect((elements[1] as NamedQuery).readTime, SnapshotVersion.none);
      expect(
          elements
              .whereType<BundledDocumentMetadata>()
              .map((BundledDocumentMetadata m) => m.readTime),
          <SnapshotVersion>[util.version(1000), util.version(2000)]);
    });

    test('fromJson parses the toJson result', () {
      final core.Query query = util
          .query('coll')
          .orderBy(util.orderBy('sort'))
          .filter(util.filter('sort', '>', 0));
      final QuerySnapshot<Map<String, Object?>> snapshot =
          querySnapshot(query, docs, readTime: util.version(5000));
      final QuerySnapshot<Map<String, Object?>> fromJson =
          QuerySnapshot<Map<String, Object?>>.fromJson(
              firestore, snapshot.toJson());
      expect(fromJson.query.query, query);
      expect(fromJson.length, 2);
      expect(
          fromJson.docs.map((DocumentSnapshot<Map<String, Object?>> d) => d.id),
          <String>['b', 'a']);
      expect(fromJson.docs[0].data, <String, Object?>{'bar': 2, 'sort': 1});
      expect(fromJson.docs[1].data, <String, Object?>{'foo': 1, 'sort': 2});
      expect(fromJson.metadata.isFromCache, isFalse);
      expect(fromJson.metadata.hasPendingWrites, isFalse);
      expect(fromJson.snapshot.readTime, util.version(5000));
      expect(
          fromJson.docChanges
              .map((dynamic c) => (c.document as DocumentSnapshot<Object?>).id),
          <String>['b', 'a']);
      // Serializing the result again keeps the read time.
      final QuerySnapshot<Map<String, Object?>> again =
          QuerySnapshot<Map<String, Object?>>.fromJson(
              firestore, fromJson.toJson());
      expect(again.snapshot.readTime, util.version(5000));
      expect(again.query.query, query);
    });

    test('keeps an empty blob and the sign of -0.0 in the query', () {
      final core.Query query = util
          .query('coll')
          .filter(util.filter('blob', '==', util.blob()))
          .filter(util.orFilters(<Filter>[
            util.filter('n', '==', -0.0),
            util.filter('n', '==', 1),
          ]))
          .orderBy(util.orderBy('sort'))
          .startAt(
              Bound(position: <FieldValue>[util.wrap(-0.0)], inclusive: true))
          .endAt(Bound(
              position: <FieldValue>[util.wrap(util.blob())], inclusive: true));
      final Map<String, Object?> json =
          querySnapshot(query, <Document>[]).toJson();
      final String bundle = json['bundle']! as String;
      expect(bundle, contains('"value":{"bytesValue":""}'));
      expect(bundle, contains('"value":{"doubleValue":"-0"}'));
      expect(
          bundle,
          contains(
              '"startAt":{"values":[{"doubleValue":"-0"}],"before":true}'));
      expect(bundle,
          contains('"endAt":{"values":[{"bytesValue":""}],"before":false}'));
      expect(
          QuerySnapshot<Map<String, Object?>>.fromJson(firestore, json)
              .query
              .query,
          query);
    });

    test('fromJson round-trips queries', () {
      final List<core.Query> queries = <core.Query>[
        util.query('coll').limit(1),
        util.query('coll').orderBy(util.orderBy('sort', 'desc')).limitToLast(1),
        util.query('coll').filter(util.orFilters(<Filter>[
              util.filter('foo', '==', 1),
              util.andFilters(<Filter>[
                util.filter('bar', '==', 2),
                util.filter('sort', '==', 1),
              ]),
            ])),
        util
            .query('coll')
            .orderBy(util.orderBy('sort'))
            .startAt(
                Bound(position: <FieldValue>[util.wrap(1)], inclusive: true))
            .endAt(
                Bound(position: <FieldValue>[util.wrap(3)], inclusive: false)),
        util
            .query('rooms/eros/messages')
            .filter(util.filter('foo', 'array-contains-any', <Object?>[1, 2])),
        core.Query(util.path(''), collectionGroup: 'coll'),
      ];
      for (final core.Query query in queries) {
        final QuerySnapshot<Map<String, Object?>> fromJson =
            QuerySnapshot<Map<String, Object?>>.fromJson(
                firestore, querySnapshot(query, <Document>[]).toJson());
        expect(fromJson.query.query, query, reason: '$query');
      }
    });

    group('fromJson validation', () {
      Map<String, Object?> valid() =>
          querySnapshot(util.query('coll'), docs).toJson();

      void expectInvalid(Map<String, Object?> json, [Object? message]) {
        expect(
            () => QuerySnapshot<Map<String, Object?>>.fromJson(firestore, json),
            throwsFirestoreError(FirestoreErrorCode.invalidArgument, message));
      }

      test('invalid fields', () {
        expectInvalid(
            valid()..remove('type'), "JSON missing required field: 'type'");
        expectInvalid(valid()..['type'] = 'firestore/documentSnapshot/1.0',
            "Expected 'type' field to equal 'firestore/querySnapshot/1.0'");
        expectInvalid(valid()..['bundleSource'] = 'DocumentSnapshot',
            "Expected 'bundleSource' field to equal 'QuerySnapshot'");
        expectInvalid(valid()..remove('bundleName'),
            "JSON missing required field: 'bundleName'");
        expectInvalid(valid()..['bundle'] = 'BadData');
        expectInvalid(valid()..['bundle'] = '');
      });

      test('a document snapshot bundle', () {
        final Map<String, Object?> json = valid()
          ..['bundle'] = documentSnapshot('coll/a', <String, Object?>{'a': 1})
              .toJson()['bundle'];
        expectInvalid(
            json, 'Snapshot data expected 1 query but found 0 queries.');
      });
    });
  });

  group('ViewSnapshot.readTime', () {
    test('is the version of the last remote event once synced', () {
      final core.Query query = util.query('coll');
      final View view = View(query, DocumentKey.emptyKeySet);
      final Document doc = util.doc('coll/a', 1000, <String, Object?>{});

      // Not current yet: the snapshot is from cache and has no read time.
      ViewSnapshot snapshot = view
          .applyChanges(
              view.computeDocChanges(util.docUpdates(<Document>[doc])),
              null,
              false,
              util.version(2000))
          .snapshot!;
      expect(snapshot.isFromCache, isTrue);
      expect(snapshot.readTime, SnapshotVersion.none);

      snapshot = view
          .applyChanges(view.computeDocChanges(util.docUpdates(<Document>[])),
              util.ackTarget(<Document>[doc]), false, util.version(3000))
          .snapshot!;
      expect(snapshot.isFromCache, isFalse);
      expect(snapshot.readTime, util.version(3000));

      // A local change keeps the read time.
      final Document updated = util.doc('coll/a', 1000,
          <String, Object?>{'a': 1}, DocumentState.localMutations);
      snapshot = view
          .applyChanges(
              view.computeDocChanges(util.docUpdates(<Document>[updated])))
          .snapshot!;
      expect(snapshot.changes.single.type, DocumentViewChangeType.modified);
      expect(snapshot.readTime, util.version(3000));
    });
  });
}
