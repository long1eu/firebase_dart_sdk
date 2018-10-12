// File created by
// Lung Razvan <long1eu>
// on 08/10/2018

import 'dart:async';
import 'dart:io';

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_firestore/src/firebase/firestore/auth/empty_credentials_provider.dart';
import 'package:firebase_firestore/src/firebase/firestore/collection_reference.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/database_info.dart';
import 'package:firebase_firestore/src/firebase/firestore/document_reference.dart';
import 'package:firebase_firestore/src/firebase/firestore/document_snapshot.dart';
import 'package:firebase_firestore/src/firebase/firestore/firebase_firestore.dart';
import 'package:firebase_firestore/src/firebase/firestore/firebase_firestore_settings.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/persistence.dart';
import 'package:firebase_firestore/src/firebase/firestore/metadata_change.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/database_id.dart';
import 'package:firebase_firestore/src/firebase/firestore/query_snapshot.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/async_queue.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/database.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/util.dart';

import '../unit/firebase/firestore/local/mock/database_mock.dart';
import 'prod_provider/firestore_provider.dart';
import 'test_util.dart';

/// A set of helper methods for tests
class IntegrationTestUtil {
  // Alternate project ID for creating 'bad' references. Doesn't actually need
  // to work.
  static const String BAD_PROJECT_ID = 'test-project-2';

  /// Online status of all active Firestore clients.
  /*p*/
  static final Map<FirebaseFirestore, bool> firestoreStatus = <FirebaseFirestore, bool>{};

  /*p*/
  static const int SEMAPHORE_WAIT_TIMEOUT_MS = 30000;

  /*p*/
  static const int SHUTDOWN_WAIT_TIMEOUT_MS = 10000;

  /*p*/
  static const int BATCH_WAIT_TIMEOUT_MS = 120000;

  /*p*/
  static final FirestoreProvider provider = FirestoreProvider();

  /// TODO: There's some flakiness with hexa / emulator / whatever that causes
  /// the first write in a run to frequently time out. So for now we always send
  /// an initial write with an extra long timeout to improve test reliability.
  /*p*/
  static const int FIRST_WRITE_TIMEOUT_MS = 60000;

  /*p*/
  static bool sentFirstWrite = false;

  static String currentDatabasePath;

  static DatabaseInfo testEnvDatabaseInfo() {
    return DatabaseInfo(
        DatabaseId.forProject(provider.projectId),
        'test-persistenceKey',
        provider.firestoreHost,
        /*sslEnabled:*/ true);
  }

  static FirebaseFirestoreSettings newTestSettings() {
    return FirebaseFirestoreSettings();
  }

  /// Initializes a new Firestore instance that uses the default project,
  /// customized with the provided settings if provided.
  static Future<FirebaseFirestore> testFirestore([FirebaseFirestoreSettings settings, String dbPath]) async {
    settings ??= newTestSettings();
    final FirebaseFirestore firestore = await testFirestoreInstance(provider.projectId, LogLevel.d, settings, dbPath ?? currentDatabasePath);

    if (!sentFirstWrite) {
      sentFirstWrite = true;
      await firestore.document('test-collection/initial-write-doc').set(TestUtil.map(<dynamic>['foo', 1]));
    }
    return firestore;
  }

  /// Initializes a new Firestore instance that uses a non-existing default
  /// project.
  static Future<FirebaseFirestore> testAlternateFirestore() async {
    return testFirestoreInstance(BAD_PROJECT_ID, LogLevel.d, newTestSettings(), 'bad/projectId/path.db');
  }

  /*p*/
  static void clearPersistence(String path) {
    final String sqlLitePath = path;
    final String journalPath = sqlLitePath + '-journal';

    final File db = File(sqlLitePath);
    if (db.existsSync()) db.deleteSync();

    final File journal = File(journalPath);
    if (journal.existsSync()) journal.deleteSync();
  }

  /// Initializes a new Firestore instance that can be used in testing. It is
  /// guaranteed to not share state with other instances returned from this
  /// call.
  static Future<FirebaseFirestore> testFirestoreInstance(String projectId, LogLevel logLevel, FirebaseFirestoreSettings settings, String dbPath) async {
    // This unfortunately is a global setting that affects existing Firestore clients.
    Log.setLogLevel(logLevel);

    // TODO: Remove this once this is ready to ship.
    Persistence.indexingSupportEnabled = true;

    final DatabaseId databaseId = DatabaseId.forDatabase(projectId, DatabaseId.defaultDatabaseId);
    final String persistenceKey = 'db${firestoreStatus.length}';

    final String dbFullPath = '${Directory.current.path}/build/test/$dbPath';
    clearPersistence(dbFullPath);

    final AsyncQueue asyncQueue = AsyncQueue();

    final FirebaseFirestore firestore = await FirebaseFirestore.forTests(
      databaseId,
      persistenceKey,
      EmptyCredentialsProvider(),
      asyncQueue,
      (String path, {int version, OnConfigure onConfigure, OnCreate onCreate, OnVersionChange onUpgrade, OnVersionChange onDowngrade, OnOpen onOpen}) async {
        final DatabaseMock db = await DatabaseMock.create(dbPath, version: version, onConfigure: onConfigure, onCreate: onCreate, onUpgrade: onUpgrade, onDowngrade: onDowngrade, onOpen: onOpen);
        db.renamePath = false;
        return db;
      },
      settings,
    );

    firestoreStatus[firestore] = true;
    return firestore;
  }

  static Future<void> tearDown() async {
    for (FirebaseFirestore firestore in firestoreStatus.keys) {
      await firestore.shutdown();
    }
    firestoreStatus.clear();
  }

  static DocumentReference testDocument(FirebaseFirestore firestore) {
    return testCollection(firestore, 'test-collection').document();
  }

  static Future<DocumentReference> testDocumentWithData(FirebaseFirestore firestore, Map<String, Object> data) async {
    final DocumentReference docRef = testDocument(firestore);
    await docRef.set(data);
    return docRef;
  }

  static CollectionReference testCollection(FirebaseFirestore firestore, [String name]) {
    return firestore.collection(name == null ? Util.autoId() : '$name${Util.autoId()}');
  }

  static Future<CollectionReference> testCollectionWithDocs(FirebaseFirestore firestore, Map<String, Map<String, Object>> docs) async {
    final CollectionReference collection = testCollection(firestore);
    final CollectionReference writer = firestore.collection(collection.id);

    await writeAllDocs(writer, docs);
    return collection;
  }

  static Future<void> writeAllDocs(CollectionReference collection, Map<String, Map<String, Object>> docs) async {
    for (MapEntry<String, Map<String, Object>> doc in docs.entries) {
      await collection.document(doc.key).set(doc.value);
    }
  }

  static Future<void> waitForOnlineSnapshot(DocumentReference doc) {
    return doc.getSnapshots(MetadataChanges.include).where((DocumentSnapshot value) => !value.metadata.isFromCache).first;
  }

  static List<Map<String, Object>> querySnapshotToValues(QuerySnapshot querySnapshot) {
    final List<Map<String, Object>> res = <Map<String, Object>>[];
    for (DocumentSnapshot doc in querySnapshot) {
      res.add(doc.data);
    }
    return res;
  }

  static List<String> querySnapshotToIds(QuerySnapshot querySnapshot) {
    final List<String> res = <String>[];
    for (DocumentSnapshot doc in querySnapshot) {
      res.add(doc.id);
    }
    return res;
  }

  static Future<void> disableNetwork(FirebaseFirestore firestore) async {
    if (firestoreStatus[firestore]) {
      await firestore.disableNetwork();
      firestoreStatus[firestore] = false;
    }
  }

  static Future<void> enableNetwork(FirebaseFirestore firestore) async {
    if (!firestoreStatus[firestore]) {
      await firestore.enableNetwork();
      // Wait for the client to connect.
      await firestore.collection('unknown').document().delete();
      firestoreStatus[firestore] = true;
    }
  }

  static bool isNetworkEnabled(FirebaseFirestore firestore) {
    return firestoreStatus[firestore];
  }

  static Map<String, Object> toDataMap(QuerySnapshot qrySnap) {
    final Map<String, Object> result = <String, Object>{};
    for (DocumentSnapshot docSnap in qrySnap.documents) {
      result[docSnap.id] = docSnap.data;
    }
    return result;
  }
}
