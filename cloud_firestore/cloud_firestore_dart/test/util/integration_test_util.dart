// File created by
// Lung Razvan <long1eu>
// on 08/10/2018

import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/credentials_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/collection_reference.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/database_info.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/firestore_client.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/document_reference.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/document_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_settings.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/metadata_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/source.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/database.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/timer_task.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/util.dart';
import 'package:firebase_app_dart/internal.dart';
import 'package:rxdart/subjects.dart';
import 'package:test/test.dart';

import '../unit/firebase/firestore/local/mock/database_mock.dart';
import 'prod_provider/firestore_provider.dart';
import 'test_backend.dart';

// ignore: avoid_classes_with_only_static_members
/// A set of helper methods for tests
class IntegrationTestUtil {
  static int dbIndex = 0;

  // Alternate project ID for creating 'bad' references. Doesn't actually need
  // to work.
  static const String badProjectId = 'test-project-2';

  /// Online status of all active Firestore clients.
  static final Map<Firestore, bool> firestoreStatus = <Firestore, bool>{};

  /// The credentials provider of each test instance, to be able to switch the user.
  static final Map<Firestore, MockCredentialsProvider> credentialsProviders =
      <Firestore, MockCredentialsProvider>{};

  /// Switches the user of the given test [firestore] instance.
  static void testChangeUserTo(Firestore firestore, User user) {
    credentialsProviders[firestore]!.changeUserTo(user);
  }

  static final FirestoreProvider provider = FirestoreProvider();

  static bool sentFirstWrite = false;

  static String currentDatabasePath = 'test';

  /// The `host:port` of the Firestore emulator, taken from the
  /// `FIRESTORE_EMULATOR_HOST` environment variable, or null if it is not set.
  static String? get emulatorHost => TestBackend().emulatorHost;

  /// The `host:port` of the Enterprise edition emulator, taken from the
  /// `FIRESTORE_ENTERPRISE_EMULATOR_HOST` environment variable, or null if it
  /// is not set (see `tool/start_enterprise_emulator.sh`).
  static String? get enterpriseEmulatorHost =>
      TestBackend().enterpriseEmulatorHost;

  /// The reason to skip a test that needs the Enterprise edition emulator, or
  /// null when it is configured: `test('...', skip: enterpriseEmulatorSkipReason, ...)`.
  static String? get enterpriseEmulatorSkipReason =>
      TestBackend().enterpriseEmulatorSkipReason;

  /// The project of the Enterprise edition emulator.
  static const String enterpriseProjectId = FirestoreProvider.fallbackProjectId;

  /// Whether the suite runs against a real Firebase project (opt-in with
  /// `FIRESTORE_TEST_PROJECT_ID`, see `test/util/test_backend.dart`).
  static bool get usesRealProject => TestBackend().usesRealProject;

  /// Access tokens for the real project. Created lazily and shared, so that
  /// the credentials are resolved once per test process.
  static final ApplicationDefaultTokenSource _realProjectTokens =
      ApplicationDefaultTokenSource();

  static DatabaseInfo testEnvDatabaseInfo() {
    return DatabaseInfo(
      DatabaseId.forProject(provider.projectId),
      'test-persistenceKey',
      '127.0.0.1',
      port: 8080,
      sslEnabled: false,
    );
  }

  static FirestoreSettings newTestSettings() {
    final String? emulator = emulatorHost;
    if (emulator == null) {
      return FirestoreSettings();
    }

    return _emulatorSettings(emulator);
  }

  static FirestoreSettings _emulatorSettings(String emulator) {
    final EmulatorAddress address = EmulatorAddress.parse(emulator);
    return FirestoreSettings(
        host: address.host, port: address.port, sslEnabled: false);
  }

  /// Initializes a new Firestore instance that talks to the Enterprise edition
  /// emulator. Guard the tests that use it with [enterpriseEmulatorSkipReason].
  static Future<Firestore> testEnterpriseFirestore([String? dbPath]) {
    final String? emulator = enterpriseEmulatorHost;
    if (emulator == null) {
      throw StateError(enterpriseEmulatorSkipReason!);
    }
    return testFirestoreInstance(
      enterpriseProjectId,
      InternalLogLevel.w,
      _emulatorSettings(emulator),
      dbPath ?? currentDatabasePath,
    );
  }

  /// Deletes all the documents from the Enterprise edition emulator.
  static Future<void> clearEnterpriseEmulatorData() =>
      _clearEmulatorData(enterpriseEmulatorHost, enterpriseProjectId);

  /// Deletes all the documents from the emulator for the test project.
  static Future<void> clearEmulatorData() =>
      _clearEmulatorData(emulatorHost, provider.projectId);

  static Future<void> _clearEmulatorData(
      String? emulator, String projectId) async {
    if (emulator == null) {
      return;
    }

    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest request = await client.deleteUrl(Uri.parse(
          'http://$emulator/emulator/v1/projects/$projectId/databases/(default)/documents'));
      final HttpClientResponse response = await request.close();
      await response.drain<void>();
    } finally {
      client.close();
    }
  }

  /// Initializes a new Firestore instance that uses the default project, customized with the provided settings if
  /// provided.
  static Future<Firestore> testFirestore(
      [FirestoreSettings? settings, String? dbPath]) async {
    return testFirestoreInstance(
      provider.projectId,
      InternalLogLevel.w,
      settings ?? newTestSettings(),
      dbPath ?? currentDatabasePath,
      databaseName:
          TestBackend().realDatabaseId ?? DatabaseId.defaultDatabaseId,
    );
  }

  /// Initializes a new Firestore instance that uses a non-existing default project.
  static Future<Firestore> testAlternateFirestore() async {
    return testFirestoreInstance(
      badProjectId,
      InternalLogLevel.w,
      newTestSettings(),
      'bad/projectId/path.db',
    );
  }

  static Future<Firestore> forTests(
      DatabaseId databaseId,
      String persistenceKey,
      CredentialsProvider provider,
      TaskScheduler scheduler,
      OpenDatabase openDatabase,
      FirestoreSettings settings) async {
    final DatabaseInfo databaseInfo = DatabaseInfo(
        databaseId, persistenceKey, settings.host,
        port: settings.port, sslEnabled: settings.sslEnabled);

    final BehaviorSubject<bool> onNetworkConnected =
        BehaviorSubject<bool>.seeded(true);
    final FirestoreClient client = await FirestoreClient.initialize(
      databaseInfo,
      settings,
      provider,
      openDatabase,
      onNetworkConnected,
      scheduler,
    );

    return Firestore(databaseId, null, client, scheduler);
  }

  /// Initializes a new Firestore instance that can be used in testing. It is guaranteed to not share state with other
  /// instances returned from this call.
  ///
  /// With [fixedDbName] the instance uses exactly that database file and does not delete it, so that a later instance
  /// created with the same name sees the persisted data (restart). Use [databaseName] to address a named database.
  static Future<Firestore> testFirestoreInstance(String projectId,
      InternalLogLevel logLevel, FirestoreSettings settings, String dbPath,
      {String? fixedDbName,
      String databaseName = DatabaseId.defaultDatabaseId}) async {
    // This unfortunately is a global setting that affects existing Firestore clients.
    Log.level = logLevel;

    // TODO(long1eu): Remove this once this is ready to ship.
    Persistence.indexingSupportEnabled = true;

    final DatabaseId databaseId =
        DatabaseId.forDatabase(projectId, databaseName);
    final String persistenceKey = 'db${firestoreStatus.length}';

    print('index: $dbIndex');
    // A name relative to build/test: DatabaseMock resolves it to a path itself.
    final String dbName = fixedDbName ?? '$dbPath\_${dbIndex++}.db';

    if (fixedDbName == null) {
      DatabaseMock.deleteDatabaseFiles(dbName);
    }

    final TaskScheduler scheduler = TaskScheduler('');
    // Only requests to production Firestore of an opted-in real project carry
    // a token; the emulators get none.
    final bool authenticate =
        usesRealProject && settings.host == TestBackend.productionHost;
    final MockCredentialsProvider credentialsProvider = MockCredentialsProvider(
        tokenSource: authenticate ? _realProjectTokens : null);
    final Firestore firestore = await forTests(
      databaseId,
      persistenceKey,
      credentialsProvider,
      scheduler,
      (String path,
          {int? version,
          OnConfigure? onConfigure,
          OnCreate? onCreate,
          OnVersionChange? onUpgrade,
          OnVersionChange? onDowngrade,
          OnOpen? onOpen}) async {
        final DatabaseMock db = await DatabaseMock.create(dbName,
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
    credentialsProviders[firestore] = credentialsProvider;
    return firestore;
  }

  static Future<void> tearDown() async {
    for (Firestore firestore in firestoreStatus.keys) {
      await firestore.shutdown();
    }
    firestoreStatus.clear();
    credentialsProviders.clear();
  }

  static Future<DocumentReference> testDocument() async {
    return (await testCollection('test-collection')).document();
  }

  static Future<DocumentReference> testDocumentWithData(
      Map<String, Object?> data) async {
    final DocumentReference docRef = await testDocument();
    await docRef.set(data);
    return docRef;
  }

  static Future<CollectionReference> testCollection([String? name]) async {
    return (await testFirestore())
        .collection(name == null ? autoId() : '$name${autoId()}');
  }

  static Future<CollectionReference> testCollectionWithDocs(
      Map<String, Map<String, Object?>> docs) async {
    final CollectionReference collection = await testCollection();
    final CollectionReference writer =
        (await testFirestore()).collection(collection.id);

    await writeAllDocs(writer, docs);
    return collection;
  }

  static Future<void> writeAllDocs(CollectionReference collection,
      Map<String, Map<String, Object?>> docs) async {
    for (MapEntry<String, Map<String, Object?>> doc in docs.entries) {
      await collection.document(doc.key).set(doc.value);
    }
  }

  /// Checks that the SDK's local results for [query] agree with the backend (port of the upstream
  /// `checkOnlineAndOfflineResultsMatch`). [collection] is read first to populate the cache; the order of the steps
  /// matters. When [expectedDocs] is not empty the server result must be exactly that list of ids.
  static Future<void> checkOnlineAndOfflineResultsMatch(
      Query collection, Query query, List<String> expectedDocs) async {
    // 1- Pre-populate the cache with the entire collection.
    await collection.get(Source.server);
    // 2- Query the cache with a full collection scan.
    final QuerySnapshot fromCacheFullScan = await query.get(Source.cache);
    // 3- Query the backend.
    final QuerySnapshot fromServer = await query.get(Source.server);
    // 4- Query the cache using the remote keys of the query.
    final QuerySnapshot fromCacheRemoteKeys = await query.get(Source.cache);

    expect(
        querySnapshotToIds(fromCacheFullScan), querySnapshotToIds(fromServer));
    expect(querySnapshotToIds(fromCacheRemoteKeys),
        querySnapshotToIds(fromServer));
    if (expectedDocs.isNotEmpty) {
      expect(querySnapshotToIds(fromServer), expectedDocs);
    }
  }

  /// Port of the upstream `assertSDKQueryResultsConsistentWithBackend`: the cache round trip, then a listener must
  /// first raise the cached and then the server snapshot, both with [expectedDocIds] and the data of [allData].
  static Future<void> assertSDKQueryResultsConsistentWithBackend(
      Query collection,
      Query query,
      Map<String, Map<String, Object?>> allData,
      List<String> expectedDocIds) async {
    // Check the cache round trip first so that the listener below can not return partial results of a previous call.
    await checkOnlineAndOfflineResultsMatch(collection, query, expectedDocIds);

    final List<QuerySnapshot> snapshots = <QuerySnapshot>[];
    final Completer<void> done = Completer<void>();
    final StreamSubscription<QuerySnapshot> registration =
        query.getSnapshots(MetadataChanges.include).listen(
      (QuerySnapshot snapshot) {
        snapshots.add(snapshot);
        if (snapshots.length == 2 && !done.isCompleted) {
          done.complete();
        }
      },
      onError: done.completeError,
    );
    try {
      await done.future.timeout(const Duration(seconds: 20));
    } finally {
      await registration.cancel();
    }

    void verifySnapshot(QuerySnapshot snapshot) {
      expect(querySnapshotToIds(snapshot), expectedDocIds);
      for (final DocumentSnapshot doc in snapshot) {
        expect(doc.data, allData[doc.id]);
      }
    }

    expect(snapshots[0].metadata.isFromCache, isTrue);
    verifySnapshot(snapshots[0]);
    expect(snapshots[1].metadata.isFromCache, isFalse);
    verifySnapshot(snapshots[1]);
  }

  static Future<void> waitForOnlineSnapshot(DocumentReference doc) {
    return doc
        .getSnapshots(MetadataChanges.include)
        .where((DocumentSnapshot value) => !value.metadata.isFromCache)
        .first;
  }

  static List<Map<String, Object?>> querySnapshotToValues(
      QuerySnapshot querySnapshot) {
    final List<Map<String, Object?>> res = <Map<String, Object?>>[];
    for (DocumentSnapshot doc in querySnapshot) {
      res.add(doc.data!);
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

  static Future<void> disableNetwork(Firestore firestore) async {
    if (firestoreStatus[firestore] ?? false) {
      await firestore.disableNetwork();
      firestoreStatus[firestore] = false;
    }
  }

  static Future<void> enableNetwork(Firestore firestore) async {
    if (!(firestoreStatus[firestore] ?? false)) {
      await firestore.enableNetwork();
      // Wait for the client to connect.
      await firestore.collection('unknown').document().delete();
      firestoreStatus[firestore] = true;
    }
  }

  static bool isNetworkEnabled(Firestore firestore) {
    return firestoreStatus[firestore] ?? false;
  }

  static Map<String, Object?> toDataMap(QuerySnapshot qrySnap) {
    final Map<String, Object?> result = <String, Object>{};
    for (DocumentSnapshot docSnap in qrySnap.documents) {
      result[docSnap.id] = docSnap.data;
    }
    return result;
  }
}

const double precisionErrorTolerance = 1e-10;

/// Asserts that two [double]s are equal, within some tolerated error.
///
/// {@template flutter.flutter_test.moreOrLessEquals.epsilon}
/// Two values are considered equal if the difference between them is within
/// [precisionErrorTolerance] of the larger one. This is an arbitrary value
/// which can be adjusted using the `epsilon` argument. This matcher is intended
/// to compare floating point numbers that are the result of different sequences
/// of operations, such that they may have accumulated slightly different
/// errors.
/// {@endtemplate}
///
/// See also:
///
///  * [closeTo], which is identical except that the epsilon argument is
///    required and not named.
///  * [inInclusiveRange], which matches if the argument is in a specified
///    range.
///  * [rectMoreOrLessEquals] and [offsetMoreOrLessEquals], which do something
///    similar but for [Rect]s and [Offset]s respectively.
Matcher moreOrLessEquals(double value,
    {double epsilon = precisionErrorTolerance}) {
  return _MoreOrLessEquals(value, epsilon);
}

class _MoreOrLessEquals extends Matcher {
  const _MoreOrLessEquals(this.value, this.epsilon) : assert(epsilon >= 0);

  final double value;
  final double epsilon;

  @override
  bool matches(dynamic object, Map<dynamic, dynamic> matchState) {
    if (object is! double) {
      return false;
    }
    if (object == value) {
      return true;
    }
    final double test = object;
    return (test - value).abs() <= epsilon;
  }

  @override
  Description describe(Description description) =>
      description.add('$value (±$epsilon)');

  @override
  Description describeMismatch(dynamic item, Description mismatchDescription,
      Map<dynamic, dynamic> matchState, bool verbose) {
    return super
        .describeMismatch(item, mismatchDescription, matchState, verbose)
      ..add('$item is not in the range of $value (±$epsilon).');
  }
}

/// A credentials provider that lets a test change the current user.
class MockCredentialsProvider extends CredentialsProvider {
  // ignore: close_sinks
  final BehaviorSubject<User> _onChange =
      BehaviorSubject<User>.seeded(User.unauthenticated);

  MockCredentialsProvider({this.tokenSource});

  /// Where the tokens come from, or null for unauthenticated requests (the
  /// emulators).
  final ApplicationDefaultTokenSource? tokenSource;

  @override
  Future<String?> get token =>
      tokenSource?.token ?? Future<String?>.value(null);

  @override
  void invalidateToken() => tokenSource?.invalidate();

  @override
  Stream<User> get onChange => _onChange;

  void changeUserTo(User user) => _onChange.add(user);
}
