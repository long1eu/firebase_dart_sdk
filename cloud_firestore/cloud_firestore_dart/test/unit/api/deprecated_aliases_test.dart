// Alias compatibility: every renamed API keeps working under its old name and
// both names behave identically. This file is the only place that is allowed
// to call deprecated members.
// ignore_for_file: deprecated_member_use_from_same_package, deprecated_member_use

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/src/internal_access.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/document_view_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/firestore_client.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart'
    as core;
import 'package:cloud_firestore_dart/src/firebase/firestore/core/view_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_set.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/timer_task.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../../util/test_util.dart' as util;

import '../../util/test_hygiene.dart';

class _Client extends Mock implements FirestoreClient {}

/// An instance typed through the `FirebaseFirestore` alias. (The class has
/// no public constructor, so it cannot be subclassed outside the SDK.)
FirebaseFirestore _testFirestore() => FirestoreInternal.create(
    DatabaseId.forProject('project'), null, _Client(), TaskScheduler('test'));

void main() {
  checkTestsLeaveNothingBehind();

  group('FirebaseFirestore alias of Firestore', () {
    test('is the same type', () {
      final FirebaseFirestore viaAlias = _testFirestore();
      final Firestore viaClass = viaAlias;
      expect(identical(viaAlias, viaClass), isTrue);
      expect(viaAlias, isA<Firestore>());
      expect(viaAlias, isA<FirebaseFirestore>());
      expect(FirebaseFirestore, Firestore);
    });

    test('statics are reachable through the alias', () {
      expect(identical(FirebaseFirestore.getInstance, Firestore.getInstance),
          isTrue);
      expect(identical(FirebaseFirestore.setLogLevel, Firestore.setLogLevel),
          isTrue);
      expect(identical(FirebaseFirestore.instanceFor, Firestore.instanceFor),
          isTrue);
      expect(
          identical(
              FirebaseFirestore.setLoggingEnabled, Firestore.setLoggingEnabled),
          isTrue);
    });

    test('doc and document agree', () {
      final Firestore firestore = _testFirestore();
      expect(firestore.doc('rooms/a/messages/1'),
          firestore.document('rooms/a/messages/1'));
      expect(firestore.doc('rooms/a').path, 'rooms/a');
      expect(firestore.doc('rooms/a').id, 'a');
    });
  });

  group('Settings alias of FirestoreSettings', () {
    test('constructor, statics and copyWith work through the alias', () {
      final Settings settings = Settings(persistenceEnabled: false);
      expect(settings, isA<FirestoreSettings>());
      expect(settings.persistenceEnabled, isFalse);
      expect(Settings.defaultHost, FirestoreSettings.defaultHost);
      expect(settings.copyWith(host: 'localhost', sslEnabled: false).sslEnabled,
          isFalse);
    });
  });

  group('CollectionReference', () {
    test('doc and document agree', () {
      final Firestore firestore = _testFirestore();
      final CollectionReference rooms = firestore.collection('rooms');
      expect(rooms.doc('a'), rooms.document('a'));
      expect(rooms.doc('a').path, 'rooms/a');
      expect(rooms.doc().parent.path, 'rooms');
      expect(rooms.doc().id, hasLength(20));
    });
  });

  group('DocumentSnapshot', () {
    test('ref and reference agree', () {
      final Firestore firestore = _testFirestore();
      final DocumentSnapshot snapshot = DocumentSnapshotInternal.fromNoDocument(
        firestore,
        util.key('rooms/a'),
        isFromCache: false,
        hasPendingWrites: false,
      );
      expect(snapshot.ref, snapshot.reference);
      expect(snapshot.ref.path, 'rooms/a');
    });
  });

  group('QuerySnapshot', () {
    QuerySnapshot snapshot(Firestore firestore) {
      final Document doc1Old = util.docForValue('foo/bar', 1,
          util.wrapList(<String>['a', 'b']), DocumentState.localMutations);
      final Document doc1New = util.docForValue('foo/bar', 1,
          util.wrapList(<String>['a', 'b']), DocumentState.synced);
      final Document doc2 = util.docForValue('foo/baz', 1,
          util.wrapList(<String>['a', 'c']), DocumentState.synced);
      final DocumentSet oldDocuments =
          util.docSet(Document.keyComparator, <Document>[doc1Old]);
      final DocumentSet newDocuments =
          util.docSet(Document.keyComparator, <Document>[doc1New, doc2]);
      final core.Query fooQuery = util.query('foo');
      final ViewSnapshot viewSnapshot = ViewSnapshot(
        fooQuery,
        newDocuments,
        oldDocuments,
        <DocumentViewChange>[
          DocumentViewChange(DocumentViewChangeType.added, doc2),
        ],
        util.keySet(),
        isFromCache: false,
        didSyncStateChange: true,
        excludesMetadataChanges: false,
        hasCachedResults: false,
      );
      return QuerySnapshotInternal.create(QueryInternal.create(fooQuery, firestore), viewSnapshot, firestore);
    }

    test('docs and documents agree', () {
      final QuerySnapshot querySnapshot = snapshot(_testFirestore());
      expect(querySnapshot.docs, isA<List<QueryDocumentSnapshot>>());
      expect(querySnapshot.docs.length, 2);
      expect(querySnapshot.docs, querySnapshot.documents);
      expect(querySnapshot.docs.map((QueryDocumentSnapshot d) => d.id),
          <String>['bar', 'baz']);
    });

    test('docChanges and documentChanges agree', () {
      final QuerySnapshot querySnapshot = snapshot(_testFirestore());
      expect(querySnapshot.docChanges, querySnapshot.documentChanges);
      expect(querySnapshot.docChanges.length, 1);
    });
  });

  group('FieldPath', () {
    test('documentIdField and documentId() agree', () {
      expect(FieldPath.documentIdField, FieldPath.documentId());
      expect(
          identical(FieldPath.documentIdField, FieldPath.documentId()), isTrue);
    });
  });

  group('Source', () {
    test('serverAndCache is the default source', () {
      expect(Source.serverAndCache, Source.defaultSource);
      expect(Source.values, <Source>[
        Source.defaultSource,
        Source.server,
        Source.cache,
      ]);
    });
  });

  test('ServerTimestampBehavior is exported from the library', () {
    expect(ServerTimestampBehavior.values, isNotEmpty);
  });
}
