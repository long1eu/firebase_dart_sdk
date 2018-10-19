// File created by
// Lung Razvan <long1eu>
// on 08/10/2018

import 'dart:async';
import 'dart:io';

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_firestore/src/firebase/firestore/auth/credentials_provider.dart';
import 'package:firebase_firestore/src/firebase/firestore/auth/empty_credentials_provider.dart';
import 'package:firebase_firestore/src/firebase/firestore/collection_reference.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/database_info.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/firestore_client.dart';
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

/// A set of helper methods for tests
class IntegrationTestUtil {
  static int dbIndex = 0;

  // Alternate project ID for creating 'bad' references. Doesn't actually need
  // to work.
  static const String badProjectId = 'test-project-2';

  /// Online status of all active Firestore clients.
  static final Map<FirebaseFirestore, bool> firestoreStatus =
      <FirebaseFirestore, bool>{};

  static final FirestoreProvider provider = FirestoreProvider();

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
  static Future<FirebaseFirestore> testFirestore(
      [FirebaseFirestoreSettings settings, String dbPath]) async {
    settings ??= newTestSettings();
    return testFirestoreInstance(
      provider.projectId,
      LogLevel.d,
      settings,
      dbPath ?? currentDatabasePath,
    );
  }

  /// Initializes a new Firestore instance that uses a non-existing default
  /// project.
  static Future<FirebaseFirestore> testAlternateFirestore() async {
    return testFirestoreInstance(
      badProjectId,
      LogLevel.d,
      newTestSettings(),
      'bad/projectId/path.db',
    );
  }

  /*p*/
  static void clearPersistence(String path) {
    final String sqlLitePath = path;
    final String journalPath = '$sqlLitePath-journal';

    final File db = File(sqlLitePath);
    if (db.existsSync()) {
      db.deleteSync();
    }

    final File journal = File(journalPath);
    if (journal.existsSync()) {
      journal.deleteSync();
    }
  }

  static Future<FirebaseFirestore> forTests(
      DatabaseId databaseId,
      String persistenceKey,
      CredentialsProvider provider,
      AsyncQueue queue,
      OpenDatabase openDatabase,
      FirebaseFirestoreSettings settings) async {
    final FirestoreClient client = await FirestoreClient.initialize(
      DatabaseInfo(
        databaseId,
        persistenceKey,
        settings.host,
        settings.sslEnabled,
      ),
      settings.persistenceEnabled,
      provider,
      queue,
      openDatabase,
    );

    return FirebaseFirestore(databaseId, queue, null, client);
  }

  /// Initializes a new Firestore instance that can be used in testing. It is
  /// guaranteed to not share state with other instances returned from this
  /// call.
  static Future<FirebaseFirestore> testFirestoreInstance(
      String projectId,
      LogLevel logLevel,
      FirebaseFirestoreSettings settings,
      String dbPath) async {
    // This unfortunately is a global setting that affects existing Firestore
    // clients.
    Log.level = logLevel;

    // TODO: Remove this once this is ready to ship.
    Persistence.indexingSupportEnabled = true;

    final DatabaseId databaseId =
        DatabaseId.forDatabase(projectId, DatabaseId.defaultDatabaseId);
    final String persistenceKey = 'db${firestoreStatus.length}';

    print('index: $dbIndex');
    final String dbFullPath =
        '${Directory.current.path}/build/test/$dbPath\_${dbIndex++}.db';

    clearPersistence(dbFullPath);

    final AsyncQueue asyncQueue = AsyncQueue();

    final FirebaseFirestore firestore = await forTests(
      databaseId,
      persistenceKey,
      EmptyCredentialsProvider(),
      asyncQueue,
      (String path,
          {int version,
          OnConfigure onConfigure,
          OnCreate onCreate,
          OnVersionChange onUpgrade,
          OnVersionChange onDowngrade,
          OnOpen onOpen}) async {
        final DatabaseMock db = await DatabaseMock.create(dbFullPath,
            version: version,
            onConfigure: onConfigure,
            onCreate: onCreate,
            onUpgrade: onUpgrade,
            onDowngrade: onDowngrade,
            onOpen: onOpen);
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

  static Future<DocumentReference> testDocument() async {
    return (await testCollection('test-collection')).document();
  }

  static Future<DocumentReference> testDocumentWithData(
      Map<String, Object> data) async {
    final DocumentReference docRef = await testDocument();
    await docRef.set(data);
    return docRef;
  }

  static Future<CollectionReference> testCollection([String name]) async {
    return (await testFirestore())
        .collection(name == null ? autoId() : '$name${autoId()}');
  }

  static Future<CollectionReference> testCollectionWithDocs(
      Map<String, Map<String, Object>> docs) async {
    final CollectionReference collection = await testCollection();
    final CollectionReference writer =
        (await testFirestore()).collection(collection.id);

    await writeAllDocs(writer, docs);
    return collection;
  }

  static Future<void> writeAllDocs(CollectionReference collection,
      Map<String, Map<String, Object>> docs) async {
    for (MapEntry<String, Map<String, Object>> doc in docs.entries) {
      await collection.document(doc.key).set(doc.value);
    }
  }

  static Future<void> waitForOnlineSnapshot(DocumentReference doc) {
    return doc
        .getSnapshots(MetadataChanges.include)
        .where((DocumentSnapshot value) => !value.metadata.isFromCache)
        .first;
  }

  static List<Map<String, Object>> querySnapshotToValues(
      QuerySnapshot querySnapshot) {
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
