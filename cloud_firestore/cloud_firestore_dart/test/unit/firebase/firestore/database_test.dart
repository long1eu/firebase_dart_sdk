// Ported from the JS SDK's test/unit/api/database.test.ts.
//
// The Dart SDK always builds a bundle in toJson() (the JS SDK only does in
// Node), so the Node branch of each test is ported. JS's
// `JSON.stringify(x)` is `jsonEncode(x)` for the classes with a toJson() and
// `x.toString()` for the others. snapshot_json_test.dart has more checks of
// the snapshot JSON.

import 'dart:convert';

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/document_view_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart'
    as core;
import 'package:cloud_firestore_dart/src/firebase/firestore/core/view_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/document_reference.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/document_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_settings.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/load_bundle_task.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_set.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query_snapshot.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:test/test.dart';

import '../../../util/test_util.dart' as util;
import 'test_util.dart' show collectionReference, firestore;

/// The JS SDK's `MULTI_BYTE_VALUES` of test/unit/util/bundle_data.ts.
const Map<String, String> _multiByteValues = <String, String>{
  'empty string (control)': '',
  'em-dash': '—',
  'emoji (surrogate pairs)': '\u{1F600} \u{1F525}',
  'single 4-byte emoji': '\u{1F600}',
  'accented characters': 'café naïve Ångström',
};

DocumentReference<Map<String, Object?>> documentReference(String path) =>
    DocumentReferenceInternal.create<Map<String, Object?>>(
      util.key(path),
      firestore,
    );

/// The JS SDK's `documentSnapshot()` of test/util/api_helpers.ts.
DocumentSnapshot<Map<String, Object?>> documentSnapshot(
  String path,
  Map<String, Object?>? data,
  bool fromCache, [
  bool hasPendingWrites = false,
]) {
  if (data != null) {
    return DocumentSnapshotInternal.fromDocument<Map<String, Object?>>(
      firestore,
      util.doc(path, 1, data),
      isFromCache: fromCache,
      hasPendingWrites: hasPendingWrites,
    );
  }
  return DocumentSnapshotInternal.fromNoDocument<Map<String, Object?>>(
    firestore,
    util.key(path),
    isFromCache: fromCache,
    hasPendingWrites: hasPendingWrites,
  );
}

/// The JS SDK's `querySnapshot()` of test/util/api_helpers.ts.
QuerySnapshot<Map<String, Object?>> querySnapshot(
  String path,
  Map<String, Map<String, Object?>> oldDocs,
  Map<String, Map<String, Object?>> docsToAdd,
  ImmutableSortedSet<DocumentKey> mutatedKeys,
  bool fromCache,
  bool syncStateChanged, [
  bool hasCachedResults = false,
]) {
  final core.Query query = util.query(path);
  DocumentSet oldDocuments = DocumentSet.emptySet(Document.keyComparator);
  oldDocs.forEach((String key, Map<String, Object?> data) {
    oldDocuments = oldDocuments.add(util.doc('$path/$key', 1, data));
  });
  DocumentSet newDocuments = DocumentSet.emptySet(Document.keyComparator);
  final List<DocumentViewChange> documentChanges = <DocumentViewChange>[];
  docsToAdd.forEach((String key, Map<String, Object?> data) {
    final Document docToAdd = util.doc('$path/$key', 1, data);
    newDocuments = newDocuments.add(docToAdd);
    documentChanges.add(
      DocumentViewChange(DocumentViewChangeType.added, docToAdd),
    );
  });
  final ViewSnapshot viewSnapshot = ViewSnapshot(
    query,
    newDocuments,
    oldDocuments,
    documentChanges,
    mutatedKeys,
    isFromCache: fromCache,
    didSyncStateChange: syncStateChanged,
    excludesMetadataChanges: false,
    hasCachedResults: hasCachedResults,
  );
  return QuerySnapshotInternal.create<Map<String, Object?>>(
    QueryInternal.create<Map<String, Object?>>(query, firestore),
    viewSnapshot,
    firestore,
  );
}

/// The JS SDK's `querySnapshotWithQuery()` of test/util/api_helpers.ts.
QuerySnapshot<Map<String, Object?>> querySnapshotWithQuery(
  core.Query query,
  Map<String, Map<String, Object?>> docsToAdd,
) {
  DocumentSet newDocuments = DocumentSet.emptySet(query.comparator);
  final List<DocumentViewChange> documentChanges = <DocumentViewChange>[];
  docsToAdd.forEach((String key, Map<String, Object?> data) {
    final Document docToAdd = util.doc(
      '${query.path.canonicalString}/$key',
      1,
      data,
    );
    newDocuments = newDocuments.add(docToAdd);
    documentChanges.add(
      DocumentViewChange(DocumentViewChangeType.added, docToAdd),
    );
  });
  final ViewSnapshot viewSnapshot = ViewSnapshot(
    query,
    newDocuments,
    DocumentSet.emptySet(query.comparator),
    documentChanges,
    DocumentKey.emptyKeySet,
    isFromCache: false,
    didSyncStateChange: true,
    excludesMetadataChanges: false,
    hasCachedResults: false,
  );
  return QuerySnapshotInternal.create<Map<String, Object?>>(
    QueryInternal.create<Map<String, Object?>>(query, firestore),
    viewSnapshot,
    firestore,
  );
}

ImmutableSortedSet<DocumentKey> keys([List<String> paths = const <String>[]]) {
  ImmutableSortedSet<DocumentKey> result = DocumentKey.emptyKeySet;
  for (final String path in paths) {
    result = result.insert(util.key(path));
  }
  return result;
}

Matcher throwsInvalidArgument(String message) => throwsA(
  isA<FirestoreError>()
      .having(
        (FirestoreError e) => e.code,
        'code',
        FirestoreErrorCode.invalidArgument,
      )
      .having((FirestoreError e) => e.message, 'message', message),
);

void main() {
  group('Bundle', () {
    test('loadBundle does not throw with an empty bundle string)', () async {
      final FirebaseApp app = FirebaseApp.withOptions(
        const FirebaseOptions(
          apiKey: 'key',
          applicationId: 'appId',
          projectId: 'projectId',
        ),
        dependencies: null,
        name: 'database_test_load_bundle',
      );
      addTearDown(app.delete);
      // Points at a port nothing listens on, nothing reaches a backend.
      final Firestore db = Firestore.instanceFor(
        app: app,
        settings: FirestoreSettings().withEmulator('127.0.0.1', 1),
      );
      addTearDown(db.terminate);

      late final LoadBundleTask task;
      expect(() => task = db.loadBundle(utf8.encode('')), returnsNormally);
      // The error is reported on the task, as in the JS SDK.
      await expectLater(task.future, throwsA(anything));
    });
  });

  group('CollectionReference', () {
    test('support equality checking with isEqual()', () {
      expect(collectionReference('foo') == collectionReference('foo'), isTrue);
      expect(collectionReference('foo') == collectionReference('bar'), isFalse);
    });

    test('JSON.stringify() does not throw', () {
      expect(collectionReference('foo').toString, returnsNormally);
    });
  });

  group('DocumentReference', () {
    test('support equality checking with isEqual()', () {
      expect(
        documentReference('rooms/foo') == documentReference('rooms/foo'),
        isTrue,
      );
      expect(
        documentReference('rooms/foo') == documentReference('rooms/bar'),
        isFalse,
      );
    });

    test('JSON.stringify() does not throw', () {
      expect(() => jsonEncode(documentReference('foo/bar')), returnsNormally);
    });

    test('toJSON() does not throw', () {
      expect(documentReference('foo/bar').toJson, returnsNormally);
    });

    test('toJSON() includes correct JSON fields', () {
      final DocumentReference<Map<String, Object?>> docRef = documentReference(
        'foo/bar',
      );
      final Map<String, Object> json = docRef.toJson();
      expect(json, <String, Object>{
        'type': 'firestore/documentReference/1.0',
        'referencePath': 'foo/bar',
      });
    });

    // DocumentReference.fromJson throws an ArgumentError, like the fromJson of
    // the other value types, where the JS SDK throws a FirestoreError.
    test('fromJSON() throws with invalid data', () {
      expect(
        () => DocumentReference<Map<String, Object?>>.fromJson(
          firestore,
          <String, Object?>{},
        ),
        throwsArgumentError,
      );
    });

    test('fromJSON() throws with missing type data', () {
      expect(
        () => DocumentSnapshot<Map<String, Object?>>.fromJson(
          firestore,
          <String, Object?>{
            'bundleSource': 'DocumentSnapshot',
            'bundleName': 'test name',
            'bundle': 'test bundle',
          },
        ),
        throwsInvalidArgument("JSON missing required field: 'type'"),
      );
    });

    test('fromJSON() throws with invalid type data', () {
      expect(
        () => DocumentSnapshot<Map<String, Object?>>.fromJson(
          firestore,
          <String, Object?>{
            'type': 1,
            'bundleSource': 'DocumentSnapshot',
            'bundleName': 'test name',
            'bundle': 'test bundle',
          },
        ),
        throwsInvalidArgument("JSON field 'type' must be a string."),
      );
    });

    test('fromJSON() throws with missing bundleSource', () {
      expect(
        () => DocumentSnapshot<Map<String, Object?>>.fromJson(
          firestore,
          <String, Object?>{
            'type': DocumentSnapshot.jsonType,
            'bundleName': 'test name',
            'bundle': 'test bundle',
          },
        ),
        throwsInvalidArgument("JSON missing required field: 'bundleSource'"),
      );
    });

    test('fromJSON() throws with invalid bundleSource type', () {
      expect(
        () => DocumentSnapshot<Map<String, Object?>>.fromJson(
          firestore,
          <String, Object?>{
            'type': DocumentSnapshot.jsonType,
            'bundleSource': 1,
            'bundleName': 'test name',
            'bundle': 'test bundle',
          },
        ),
        throwsInvalidArgument("JSON field 'bundleSource' must be a string."),
      );
    });

    test('fromJSON() throws with invalid bundleSource value', () {
      expect(
        () => DocumentSnapshot<Map<String, Object?>>.fromJson(
          firestore,
          <String, Object?>{
            'type': DocumentSnapshot.jsonType,
            'bundleSource': 'QuerySnapshot',
            'bundleName': 'test name',
            'bundle': 'test bundle',
          },
        ),
        throwsInvalidArgument(
          "Expected 'bundleSource' field to equal 'DocumentSnapshot'",
        ),
      );
    });

    test('fromJSON() throws with missing bundleName', () {
      expect(
        () => DocumentSnapshot<Map<String, Object?>>.fromJson(
          firestore,
          <String, Object?>{
            'type': DocumentSnapshot.jsonType,
            'bundleSource': 'DocumentSnapshot',
            'bundle': 'test bundle',
          },
        ),
        throwsInvalidArgument("JSON missing required field: 'bundleName'"),
      );
    });

    test('fromJSON() throws with invalid bundleName', () {
      expect(
        () => DocumentSnapshot<Map<String, Object?>>.fromJson(
          firestore,
          <String, Object?>{
            'type': DocumentSnapshot.jsonType,
            'bundleSource': 'DocumentSnapshot',
            'bundleName': 1,
            'bundle': 'test bundle',
          },
        ),
        throwsInvalidArgument("JSON field 'bundleName' must be a string."),
      );
    });

    test('fromJSON() throws with missing bundle', () {
      expect(
        () => DocumentSnapshot<Map<String, Object?>>.fromJson(
          firestore,
          <String, Object?>{
            'type': DocumentSnapshot.jsonType,
            'bundleSource': 'DocumentSnapshot',
            'bundleName': 'test name',
          },
        ),
        throwsInvalidArgument("JSON missing required field: 'bundle'"),
      );
    });

    test('fromJSON() throws with invalid bundle', () {
      expect(
        () => DocumentSnapshot<Map<String, Object?>>.fromJson(
          firestore,
          <String, Object?>{
            'type': DocumentSnapshot.jsonType,
            'bundleSource': 'DocumentSnapshot',
            'bundleName': 'test name',
            'bundle': 1,
          },
        ),
        throwsInvalidArgument("JSON field 'bundle' must be a string."),
      );
    });

    test('fromJSON() does not throw', () {
      final DocumentReference<Map<String, Object?>> docRef = documentReference(
        'foo/bar',
      );
      final Map<String, Object> json = docRef.toJson();
      expect(
        () => DocumentReference<Map<String, Object?>>.fromJson(firestore, json),
        returnsNormally,
      );
    });

    test('fromJSON() equals original docRef', () {
      final DocumentReference<Map<String, Object?>> docRef = documentReference(
        'foo/bar',
      );
      final Map<String, Object> json = docRef.toJson();
      final DocumentReference<Map<String, Object?>> deserializedDocRef =
          DocumentReference<Map<String, Object?>>.fromJson(firestore, json);
      expect(docRef.id, deserializedDocRef.id);
      expect(docRef.path, deserializedDocRef.path);
      expect(docRef.toJson(), deserializedDocRef.toJson());
    });
  });

  group('DocumentSnapshot', () {
    test('support equality checking with isEqual()', () {
      expect(
        documentSnapshot('rooms/foo', <String, Object?>{'a': 1}, true) ==
            documentSnapshot('rooms/foo', <String, Object?>{'a': 1}, true),
        isTrue,
      );
      expect(
        documentSnapshot('rooms/foo', null, true) ==
            documentSnapshot('rooms/foo', null, true),
        isTrue,
      );
      // Both directions, like snapshotEqual().
      expect(
        documentSnapshot('rooms/foo', <String, Object?>{'a': 1}, true) ==
            documentSnapshot('rooms/foo', null, true),
        isFalse,
      );
      expect(
        documentSnapshot('rooms/foo', null, true) ==
            documentSnapshot('rooms/foo', <String, Object?>{'a': 1}, true),
        isFalse,
      );
      expect(
        documentSnapshot('rooms/foo', <String, Object?>{'a': 1}, true) ==
            documentSnapshot('rooms/bar', <String, Object?>{'a': 1}, true),
        isFalse,
      );
      expect(
        documentSnapshot('rooms/foo', <String, Object?>{'a': 1}, true) ==
            documentSnapshot('rooms/bar', <String, Object?>{'b': 1}, true),
        isFalse,
      );
      expect(
        documentSnapshot('rooms/foo', <String, Object?>{'a': 1}, true) ==
            documentSnapshot('rooms/bar', <String, Object?>{'a': 1}, false),
        isFalse,
      );
    });

    test('JSON.stringify() does not throw', () {
      expect(
        () => jsonEncode(
          documentSnapshot('foo/bar', <String, Object?>{'a': 1}, true),
        ),
        returnsNormally,
      );
    });

    test('toJSON returns a bundle', () {
      final Map<String, Object?> json = documentSnapshot(
        'foo/bar',
        <String, Object?>{'a': 1},
        /*fromCache=*/ true,
      ).toJson();
      expect(json['bundle'], isA<String>());
      expect((json['bundle']! as String).length, greaterThan(0));
    });

    test('toJSON returns an empty bundle when there are no documents', () {
      final Map<String, Object?> json = documentSnapshot(
        'foo/bar',
        /*data=*/ null,
        /*fromCache=*/ true,
      ).toJson();
      expect(json['bundle'], isA<String>());
      expect((json['bundle']! as String).length, 0);
    });

    test('toJSON throws when there are pending writes', () {
      expect(
        () => documentSnapshot(
          'foo/bar',
          <String, Object?>{},
          /*fromCache=*/ true,
          /*hasPendingWrites=*/ true,
        ).toJson(),
        throwsA(
          isA<FirestoreError>().having(
            (FirestoreError e) => e.message,
            'message',
            'DocumentSnapshot.toJson() attempted to serialize a document with '
                'pending writes. Await waitForPendingWrites() before invoking '
                'toJson().',
          ),
        ),
      );
    });

    // The JS SDK only checks this outside of Node, where toJSON() writes
    // 'NOT SUPPORTED' as the bundle.
    test('fromJSON throws when parsing client-side toJSON result', () {
      final Map<String, Object?> json = documentSnapshot(
        'foo/bar',
        <String, Object?>{'a': 1},
        /*fromCache=*/ true,
      ).toJson()..['bundle'] = 'NOT SUPPORTED';
      expect(
        () => DocumentSnapshot<Map<String, Object?>>.fromJson(firestore, json),
        throwsA(isA<FirestoreError>()),
      );
    });

    test('fromJSON parses toJSON result', () {
      final DocumentSnapshot<Map<String, Object?>> docSnap = documentSnapshot(
        'foo/bar',
        <String, Object?>{'a': 1},
        /*fromCache=*/ true,
      );
      expect(
        () => DocumentSnapshot<Map<String, Object?>>.fromJson(
          firestore,
          docSnap.toJson(),
        ),
        returnsNormally,
      );
    });

    test('fromJSON produces valid snapshot data.', () {
      final DocumentSnapshot<Map<String, Object?>> docSnap = documentSnapshot(
        'foo/bar',
        <String, Object?>{'a': 1},
        /*fromCache=*/ true,
      );
      final DocumentSnapshot<Map<String, Object?>> docSnapFromJSON =
          DocumentSnapshot<Map<String, Object?>>.fromJson(
            firestore,
            docSnap.toJson(),
          );
      final Map<String, Object?>? data = docSnapFromJSON.data;
      expect(data, isNotNull);
      expect(data!['a'], 1);
    });

    // Regression test for https://github.com/firebase/firebase-js-sdk/issues/10557
    _multiByteValues.forEach((String name, String value) {
      test('fromJSON round-trips toJSON result containing $name', () {
        final String path = 'coll$value/doc$value';
        final DocumentSnapshot<Map<String, Object?>> docSnap = documentSnapshot(
          path,
          <String, Object?>{
            'v': value,
            'nested': <String, Object?>{
              'k$value': <Object?>[value],
            },
          },
          /*fromCache=*/ true,
        );
        final DocumentSnapshot<Map<String, Object?>> docSnapFromJSON =
            DocumentSnapshot<Map<String, Object?>>.fromJson(
              firestore,
              docSnap.toJson(),
            );
        expect(docSnapFromJSON.reference.path, path);
        expect(docSnapFromJSON.data, <String, Object?>{
          'v': value,
          'nested': <String, Object?>{
            'k$value': <Object?>[value],
          },
        });
      });
    });
  });

  group('Query', () {
    Query<Map<String, Object?>> query(String path) =>
        QueryInternal.create<Map<String, Object?>>(util.query(path), firestore);

    test('support equality checking with isEqual()', () {
      expect(query('foo') == query('foo'), isTrue);
      expect(query('foo') == query('bar'), isFalse);
    });

    test('JSON.stringify() does not throw', () {
      expect(query('foo').toString, returnsNormally);
    });
  });

  group('QuerySnapshot', () {
    const Map<String, Map<String, Object?>> noDocs =
        <String, Map<String, Object?>>{};
    const Map<String, Map<String, Object?>> docA =
        <String, Map<String, Object?>>{
          'a': <String, Object?>{'a': 1},
        };

    test('support equality checking with isEqual()', () {
      expect(
        querySnapshot('foo', noDocs, docA, keys(), false, false) ==
            querySnapshot('foo', noDocs, docA, keys(), false, false),
        isTrue,
      );
      expect(
        querySnapshot('foo', noDocs, docA, keys(), false, false) ==
            querySnapshot('bar', noDocs, docA, keys(), false, false),
        isFalse,
      );
      expect(
        querySnapshot('foo', noDocs, docA, keys(), false, false) ==
            querySnapshot(
              'foo',
              <String, Map<String, Object?>>{
                'b': <String, Object?>{'b': 1},
              },
              docA,
              keys(),
              false,
              false,
            ),
        isFalse,
      );
      expect(
        querySnapshot('foo', noDocs, docA, keys(), false, false) ==
            querySnapshot(
              'foo',
              noDocs,
              <String, Map<String, Object?>>{
                'a': <String, Object?>{'b': 1},
              },
              keys(),
              false,
              false,
            ),
        isFalse,
      );
      expect(
        querySnapshot(
              'foo',
              noDocs,
              docA,
              keys(<String>['foo/a']),
              false,
              false,
            ) ==
            querySnapshot('foo', noDocs, docA, keys(), false, false),
        isFalse,
      );
      expect(
        querySnapshot(
              'foo',
              noDocs,
              docA,
              keys(<String>['foo/a']),
              false,
              false,
            ) ==
            querySnapshot(
              'foo',
              noDocs,
              docA,
              keys(<String>['foo/b']),
              false,
              false,
            ),
        isFalse,
      );
      expect(
        querySnapshot(
              'foo',
              noDocs,
              docA,
              keys(<String>['foo/a']),
              false,
              false,
            ) ==
            querySnapshot(
              'foo',
              noDocs,
              docA,
              keys(<String>['foo/a']),
              true,
              false,
            ),
        isFalse,
      );
      expect(
        querySnapshot(
              'foo',
              noDocs,
              docA,
              keys(<String>['foo/a']),
              false,
              false,
            ) ==
            querySnapshot(
              'foo',
              noDocs,
              docA,
              keys(<String>['foo/a']),
              false,
              true,
            ),
        isFalse,
      );
      // hasCachedResults should affect querySnapshot equality
      expect(
        querySnapshot(
              'foo',
              noDocs,
              docA,
              keys(<String>['foo/a']),
              false,
              false,
              true,
            ) ==
            querySnapshot(
              'foo',
              noDocs,
              docA,
              keys(<String>['foo/a']),
              false,
              false,
              true,
            ),
        isTrue,
      );
      expect(
        querySnapshot(
              'foo',
              noDocs,
              docA,
              keys(<String>['foo/a']),
              false,
              false,
              true,
            ) ==
            querySnapshot(
              'foo',
              noDocs,
              docA,
              keys(<String>['foo/a']),
              false,
              false,
              false,
            ),
        isFalse,
      );
    });

    test('JSON.stringify() does not throw', () {
      expect(
        () => jsonEncode(
          querySnapshot('foo', noDocs, docA, keys(), false, false),
        ),
        returnsNormally,
      );
    });

    test('toJSON returns a bundle', () {
      final Map<String, Object?> json = querySnapshot(
        'foo',
        noDocs,
        docA,
        // An empty set of mutated document keys signifies that there are no
        // pending writes.
        keys(),
        false,
        false,
      ).toJson();
      expect(json['bundle'], isA<String>());
      expect((json['bundle']! as String).length, greaterThan(0));
    });

    test('toJSON returns a bundle when there are no documents', () {
      final Map<String, Object?> json = querySnapshot(
        'foo',
        noDocs,
        noDocs,
        keys(),
        false,
        false,
      ).toJson();
      expect(json['bundle'], isA<String>());
      expect((json['bundle']! as String).length, greaterThan(0));
    });

    test('toJSON throws when there are pending writes', () {
      expect(
        () => querySnapshot(
          'foo',
          noDocs,
          docA,
          // A non empty set of mutated keys signifies pending writes.
          keys(<String>['foo/a']),
          false,
          false,
        ).toJson(),
        throwsA(
          isA<FirestoreError>().having(
            (FirestoreError e) => e.message,
            'message',
            'QuerySnapshot.toJson() attempted to serialize a document with '
                'pending writes. Await waitForPendingWrites() before invoking '
                'toJson().',
          ),
        ),
      );
    });

    test('fromJSON() throws with invalid data', () {
      expect(
        () => QuerySnapshot<Map<String, Object?>>.fromJson(
          firestore,
          <String, Object?>{},
        ),
        throwsInvalidArgument("JSON missing required field: 'type'"),
      );
    });

    test('fromJSON() throws with missing type data', () {
      expect(
        () => QuerySnapshot<Map<String, Object?>>.fromJson(
          firestore,
          <String, Object?>{
            'bundleSource': 'QuerySnapshot',
            'bundleName': 'test name',
            'bundle': 'test bundle',
          },
        ),
        throwsInvalidArgument("JSON missing required field: 'type'"),
      );
    });

    test('fromJSON() throws with invalid type data', () {
      expect(
        () => QuerySnapshot<Map<String, Object?>>.fromJson(
          firestore,
          <String, Object?>{
            'type': 1,
            'bundleSource': 'QuerySnapshot',
            'bundleName': 'test name',
            'bundle': 'test bundle',
          },
        ),
        throwsInvalidArgument("JSON field 'type' must be a string."),
      );
    });

    test('fromJSON() throws with missing bundle source data', () {
      expect(
        () => QuerySnapshot<Map<String, Object?>>.fromJson(
          firestore,
          <String, Object?>{
            'type': QuerySnapshot.jsonType,
            'bundleName': 'test name',
            'bundle': 'test bundle',
          },
        ),
        throwsInvalidArgument("JSON missing required field: 'bundleSource'"),
      );
    });

    test('fromJSON() throws with invalid bundleSource type', () {
      expect(
        () => QuerySnapshot<Map<String, Object?>>.fromJson(
          firestore,
          <String, Object?>{
            'type': QuerySnapshot.jsonType,
            'bundleSource': 1,
            'bundleName': 'test name',
            'bundle': 'test bundle',
          },
        ),
        throwsInvalidArgument("JSON field 'bundleSource' must be a string."),
      );
    });

    test('fromJSON() throws with invalid bundleSource value', () {
      expect(
        () => QuerySnapshot<Map<String, Object?>>.fromJson(
          firestore,
          <String, Object?>{
            'type': QuerySnapshot.jsonType,
            'bundleSource': 'DocumentSnapshot',
            'bundleName': 'test name',
            'bundle': 'test bundle',
          },
        ),
        throwsInvalidArgument(
          "Expected 'bundleSource' field to equal 'QuerySnapshot'",
        ),
      );
    });

    test('fromJSON() throws with missing bundleName', () {
      expect(
        () => QuerySnapshot<Map<String, Object?>>.fromJson(
          firestore,
          <String, Object?>{
            'type': QuerySnapshot.jsonType,
            'bundleSource': 'QuerySnapshot',
            'bundle': 'test bundle',
          },
        ),
        throwsInvalidArgument("JSON missing required field: 'bundleName'"),
      );
    });

    test('fromJSON() throws with invalid bundleName', () {
      expect(
        () => QuerySnapshot<Map<String, Object?>>.fromJson(
          firestore,
          <String, Object?>{
            'type': QuerySnapshot.jsonType,
            'bundleSource': 'QuerySnapshot',
            'bundleName': 1,
            'bundle': 'test bundle',
          },
        ),
        throwsInvalidArgument("JSON field 'bundleName' must be a string."),
      );
    });

    test('fromJSON() throws with missing bundle field', () {
      expect(
        () => QuerySnapshot<Map<String, Object?>>.fromJson(
          firestore,
          <String, Object?>{
            'type': QuerySnapshot.jsonType,
            'bundleSource': 'QuerySnapshot',
            'bundleName': 'test name',
          },
        ),
        throwsInvalidArgument("JSON missing required field: 'bundle'"),
      );
    });

    test('fromJSON() throws with invalid bundle field', () {
      expect(
        () => QuerySnapshot<Map<String, Object?>>.fromJson(
          firestore,
          <String, Object?>{
            'type': QuerySnapshot.jsonType,
            'bundleSource': 'QuerySnapshot',
            'bundleName': 'test name',
            'bundle': 1,
          },
        ),
        throwsInvalidArgument("JSON field 'bundle' must be a string."),
      );
    });

    const Map<String, Map<String, Object?>> docsAB =
        <String, Map<String, Object?>>{
          'a': <String, Object?>{'a': 1},
          'b': <String, Object?>{'bar': 2},
        };

    test('fromJSON does not throw', () {
      final QuerySnapshot<Map<String, Object?>> snapshot = querySnapshot(
        'foo',
        noDocs,
        docsAB,
        keys(),
        false,
        false,
      );
      expect(
        () => QuerySnapshot<Map<String, Object?>>.fromJson(
          firestore,
          snapshot.toJson(),
        ),
        returnsNormally,
      );
    });

    test('fromJSON produces valid snapshot data', () {
      final QuerySnapshot<Map<String, Object?>> snapshot = querySnapshot(
        'foo',
        noDocs,
        docsAB,
        keys(),
        false,
        false,
      );
      final QuerySnapshot<Map<String, Object?>> querySnap =
          QuerySnapshot<Map<String, Object?>>.fromJson(
            firestore,
            snapshot.toJson(),
          );
      final List<QueryDocumentSnapshot<Map<String, Object?>>> docs =
          querySnap.docs;
      expect(docs, hasLength(2));
      expect(docs[0].data['a'], 1);
      expect(docs[1].data['bar'], 2);
    });

    test('fromJSON respects query sort order', () {
      final core.Query q = util.query('foo').orderBy(util.orderBy('title'));
      final QuerySnapshot<Map<String, Object?>> snapshot =
          querySnapshotWithQuery(q, <String, Map<String, Object?>>{
            'docA': <String, Object?>{'title': 'C'},
            'docB': <String, Object?>{'title': 'B'},
            'docC': <String, Object?>{'title': 'A'},
          });
      final QuerySnapshot<Map<String, Object?>> querySnap =
          QuerySnapshot<Map<String, Object?>>.fromJson(
            firestore,
            snapshot.toJson(),
          );
      final List<Object?> titles = <Object?>[
        for (final QueryDocumentSnapshot<Map<String, Object?>> d
            in querySnap.docs)
          d.data['title'],
      ];
      expect(titles, <Object?>['A', 'B', 'C']);
    });

    // Regression test for https://github.com/firebase/firebase-js-sdk/issues/10557
    _multiByteValues.forEach((String name, String value) {
      test('fromJSON round-trips toJSON result containing $name', () {
        final String collectionPath = 'coll$value';
        final QuerySnapshot<Map<String, Object?>> snapshot = querySnapshot(
          collectionPath,
          noDocs,
          <String, Map<String, Object?>>{
            'a$value': <String, Object?>{'v': value, 'k$value': 'key'},
            'b$value': <String, Object?>{'v': '$value-$value', 'n': 2},
          },
          // An empty set of mutated document keys signifies that there are no
          // pending writes.
          keys(),
          false,
          false,
        );
        final QuerySnapshot<Map<String, Object?>> querySnap =
            QuerySnapshot<Map<String, Object?>>.fromJson(
              firestore,
              snapshot.toJson(),
            );
        expect(
          <String>[
            for (final QueryDocumentSnapshot<Map<String, Object?>> d
                in querySnap.docs)
              d.reference.path,
          ],
          <String>['$collectionPath/a$value', '$collectionPath/b$value'],
        );
        expect(querySnap.docs[0].data, <String, Object?>{
          'v': value,
          'k$value': 'key',
        });
        expect(querySnap.docs[1].data, <String, Object?>{
          'v': '$value-$value',
          'n': 2,
        });
      });
    });

    // The JS SDK only checks this outside of Node, where toJSON() writes
    // 'NOT SUPPORTED' as the bundle.
    test('fromJSON throws when parsing client-side toJSON result', () {
      final Map<String, Object?> json = querySnapshot(
        'foo',
        noDocs,
        docA,
        keys(),
        false,
        false,
      ).toJson()..['bundle'] = 'NOT SUPPORTED';
      expect(
        () => QuerySnapshot<Map<String, Object?>>.fromJson(firestore, json),
        throwsA(isA<FirestoreError>()),
      );
    });
  });

  group('SnapshotMetadata', () {
    test('from DocumentSnapshot support equality checking with isEqual()', () {
      expect(
        documentSnapshot('rooms/foo', <String, Object?>{}, true).metadata,
        documentSnapshot('rooms/foo', <String, Object?>{}, true).metadata,
      );
      expect(
        documentSnapshot('rooms/foo', <String, Object?>{}, true).metadata,
        isNot(
          documentSnapshot('rooms/foo', <String, Object?>{}, false).metadata,
        ),
      );
    });

    test('from QuerySnapshot support equality checking with isEqual()', () {
      const Map<String, Map<String, Object?>> noDocs =
          <String, Map<String, Object?>>{};
      expect(
        querySnapshot(
          'foo',
          noDocs,
          noDocs,
          keys(<String>['foo/a']),
          true,
          false,
        ).metadata,
        querySnapshot(
          'foo',
          noDocs,
          noDocs,
          keys(<String>['foo/a']),
          true,
          false,
        ).metadata,
      );
      expect(
        querySnapshot(
          'foo',
          noDocs,
          noDocs,
          keys(<String>['foo/a']),
          true,
          false,
        ).metadata,
        isNot(
          querySnapshot('foo', noDocs, noDocs, keys(), true, false).metadata,
        ),
      );
      expect(
        querySnapshot(
          'foo',
          noDocs,
          noDocs,
          keys(<String>['foo/a']),
          true,
          false,
        ).metadata,
        isNot(
          querySnapshot(
            'foo',
            noDocs,
            noDocs,
            keys(<String>['foo/a']),
            false,
            false,
          ).metadata,
        ),
      );
      expect(
        querySnapshot(
          'foo',
          noDocs,
          noDocs,
          keys(<String>['foo/a']),
          true,
          false,
        ).metadata,
        isNot(
          querySnapshot('foo', noDocs, noDocs, keys(), false, false).metadata,
        ),
      );
    });
  });

  // JS's db._setSettings(settings) / db._getSettings() is the
  // FirestoreSettings constructor here, and connectFirestoreEmulator() is
  // withEmulator(). Not ported: timeoutSeconds (no such setting), the
  // coercion of truthy and falsy values (the options are typed), the Cloud
  // Workstations host (JS only), grpcFlowControlWindow (see
  // firestore_settings_test.dart) and the mockUserToken credentials (see
  // emulator_mock_user_token_test.dart).
  group('Settings', () {
    test('cannot use mutually exclusive settings together', () {
      expect(
        () => FirestoreSettings(
          experimentalForceLongPolling: true,
          experimentalAutoDetectLongPolling: true,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.message,
            'message',
            'experimentalForceLongPolling and experimentalAutoDetectLongPolling '
                'cannot be used together.',
          ),
        ),
      );
    });

    void expectLongPolling(
      FirestoreSettings settings, {
      required bool autoDetect,
      required bool force,
    }) {
      expect(settings.experimentalAutoDetectLongPolling, autoDetect);
      expect(settings.experimentalForceLongPolling, force);
    }

    test('long polling should be in auto-detect mode by default', () {
      expectLongPolling(FirestoreSettings(), autoDetect: true, force: false);
    });

    test('long polling should be in force mode if force=true', () {
      expectLongPolling(
        FirestoreSettings(experimentalForceLongPolling: true),
        autoDetect: false,
        force: true,
      );
    });

    test('long polling should be in auto-detect mode if autoDetect=true', () {
      expectLongPolling(
        FirestoreSettings(experimentalAutoDetectLongPolling: true),
        autoDetect: true,
        force: false,
      );
    });

    test('long polling should be in auto-detect mode if force=false', () {
      expectLongPolling(
        FirestoreSettings(experimentalForceLongPolling: false),
        autoDetect: true,
        force: false,
      );
    });

    test('long polling should be disabled if autoDetect=false', () {
      expectLongPolling(
        FirestoreSettings(experimentalAutoDetectLongPolling: false),
        autoDetect: false,
        force: false,
      );
    });

    test('long polling should be in auto-detect mode if autoDetect=true and '
        'force=false', () {
      expectLongPolling(
        FirestoreSettings(
          experimentalAutoDetectLongPolling: true,
          experimentalForceLongPolling: false,
        ),
        autoDetect: true,
        force: false,
      );
    });

    test('long polling should be in force mode if autoDetect=false and '
        'force=true', () {
      expectLongPolling(
        FirestoreSettings(
          experimentalAutoDetectLongPolling: false,
          experimentalForceLongPolling: true,
        ),
        autoDetect: false,
        force: true,
      );
    });

    test(
      'long polling should be disabled if autoDetect=false and force=false',
      () {
        expectLongPolling(
          FirestoreSettings(
            experimentalAutoDetectLongPolling: false,
            experimentalForceLongPolling: false,
          ),
          autoDetect: false,
          force: false,
        );
      },
    );

    test('gets settings from useEmulator', () {
      final FirestoreSettings settings = FirestoreSettings().withEmulator(
        '127.0.0.1',
        9000,
      );

      expect('${settings.host}:${settings.port}', '127.0.0.1:9000');
      expect(settings.sslEnabled, isFalse);
    });

    test('gets privateSettings from useEmulator', () {
      final FirestoreSettings settings = FirestoreSettings().withEmulator(
        '127.0.0.1',
        9000,
        mockUserToken: 'test',
      );

      expect('${settings.host}:${settings.port}', '127.0.0.1:9000');
      expect(settings.sslEnabled, isFalse);
      expect(settings.mockUserToken, 'test');
    });

    test('prefers host from useEmulator to host from settings', () {
      final FirestoreSettings settings = FirestoreSettings(
        host: 'other.host',
      ).withEmulator('127.0.0.1', 9000);

      expect('${settings.host}:${settings.port}', '127.0.0.1:9000');
      expect(settings.sslEnabled, isFalse);
    });
  });
}
