// Two clients in one isolate on one SQLite file that share their state through one
// InMemorySharedClientStateStorage (the JS SDK's multi-tab mode): the primary
// listens and writes for both, and the secondary learns the results and the
// online state from the shared state. The secondary never uses the network
// while it is secondary.

import 'dart:async';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/shared_client_state_storage.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/util.dart'
    show autoId;
import 'package:cloud_firestore_dart/src/internal_access.dart';
import 'package:firebase_app_dart/internal.dart' show InternalLogLevel;
import 'package:test/test.dart';

import '../../../unit/firebase/firestore/local/mock/database_mock.dart';
import '../../../util/integration_test_util.dart';

final String? needsEmulator = IntegrationTestUtil.emulatorHost == null
    ? 'needs the Firestore emulator (FIRESTORE_EMULATOR_HOST)'
    : null;

/// The longest a step may take: a move of the primary lease waits for the
/// next metadata refresh (every four seconds) of the other client.
const Duration stepTimeout = Duration(seconds: 20);

void main() {
  IntegrationTestUtil.currentDatabasePath = 'integration/shared_client_state';

  late String dbName;
  late String persistenceKey;
  late InMemorySharedClientStateStorage storage;

  setUp(() {
    dbName = 'shared_client_state_${autoId()}.db';
    DatabaseMock.deleteDatabaseFiles(dbName);
    persistenceKey = 'shared${autoId()}';
    storage = InMemorySharedClientStateStorage();
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await IntegrationTestUtil.tearDown();
    DatabaseMock.deleteDatabaseFiles(dbName);
  });

  /// A client of the shared cache, with a storage of its own on the bus.
  Future<FirebaseFirestore> open() => IntegrationTestUtil.testFirestoreInstance(
    IntegrationTestUtil.provider.projectId,
    InternalLogLevel.w,
    IntegrationTestUtil.newTestSettings(),
    IntegrationTestUtil.currentDatabasePath,
    fixedDbName: dbName,
    persistenceKey: persistenceKey,
    sharedClientStateStorage: storage.connect(),
  );

  /// Opens the primary and then the secondary, and waits until both know.
  Future<(FirebaseFirestore, FirebaseFirestore)> openBoth() async {
    final FirebaseFirestore primary = await open();
    final FirebaseFirestore secondary = await open();
    await _waitFor(
      'the first client is primary, the second secondary',
      () =>
          _isPrimary(primary) &&
          !secondary.client.isPrimaryClient &&
          !secondary.client.syncEngine.isPrimaryClient,
    );
    expect(primary.client.sharesClientState, isTrue);
    expect(secondary.client.sharesClientState, isTrue);
    return (primary, secondary);
  }

  test(
    'a listener of the secondary receives a change from the server',
    skip: needsEmulator,
    () async {
      final (FirebaseFirestore a, FirebaseFirestore b) = await openBoth();
      final FirebaseFirestore writer =
          await IntegrationTestUtil.testFirestore();
      final String path = 'shared_state_${autoId()}';

      final Future<QuerySnapshot<Map<String, Object?>>> seen = b
          .collection(path)
          .snapshots(includeMetadataChanges: true)
          .firstWhere(
            (QuerySnapshot<Map<String, Object?>> snapshot) =>
                !snapshot.metadata.isFromCache &&
                snapshot.docs.any(
                  (QueryDocumentSnapshot<Map<String, Object?>> doc) =>
                      doc.id == 'x' && doc.data()['v'] == 1,
                ),
          )
          .timeout(stepTimeout);
      await writer.collection(path).doc('x').set(<String, Object?>{'v': 1});
      await seen;

      // The secondary got it through the primary.
      expect(b.client.remoteStore.canUseNetwork, isFalse);
      expect(_isPrimary(a), isTrue);
    },
  );

  test(
    'a write of the secondary is sent by the primary and acknowledged',
    skip: needsEmulator,
    () async {
      final (FirebaseFirestore a, FirebaseFirestore b) = await openBoth();
      final FirebaseFirestore writer =
          await IntegrationTestUtil.testFirestore();
      final DocumentReference<Map<String, Object?>> doc = b
          .collection('shared_state_${autoId()}')
          .doc('w');

      final List<SnapshotMetadata> metadata = <SnapshotMetadata>[];
      final Future<DocumentSnapshot<Map<String, Object?>>> committed = doc
          .snapshots(includeMetadataChanges: true)
          .firstWhere((DocumentSnapshot<Map<String, Object?>> snapshot) {
            if (snapshot.exists) {
              metadata.add(snapshot.metadata);
            }
            return snapshot.exists && !snapshot.metadata.hasPendingWrites;
          })
          .timeout(stepTimeout);
      await doc.set(<String, Object?>{'by': 'b'}).timeout(stepTimeout);
      final DocumentSnapshot<Map<String, Object?>> snapshot = await committed;
      expect(snapshot.data(), <String, Object?>{'by': 'b'});
      // The listener saw the write pending first.
      expect(metadata.first.hasPendingWrites, isTrue);

      final DocumentSnapshot<Map<String, Object?>> onServer = await writer
          .doc(doc.path)
          .get(const GetOptions(source: Source.server));
      expect(onServer.data(), <String, Object?>{'by': 'b'});
      expect(b.client.remoteStore.canUseNetwork, isFalse);
      expect(_isPrimary(a), isTrue);
    },
  );

  test(
    'the online state of the primary reaches the secondary',
    skip: needsEmulator,
    () async {
      final (FirebaseFirestore a, FirebaseFirestore b) = await openBoth();
      final String path = 'shared_state_${autoId()}';
      await a.collection(path).doc('o').set(<String, Object?>{'v': 1});

      // A secondary that does not share state reports itself offline: its
      // snapshots stay `isFromCache`. Here the primary is online and says so.
      await b
          .doc('$path/o')
          .snapshots(includeMetadataChanges: true)
          .firstWhere(
            (DocumentSnapshot<Map<String, Object?>> snapshot) =>
                !snapshot.metadata.isFromCache,
          )
          .timeout(stepTimeout);
      expect(b.client.remoteStore.canUseNetwork, isFalse);

      // The primary goes offline: the secondary's snapshots are from the
      // cache again. The primary then hands the lease to the secondary,
      // whose network is enabled, and the secondary goes online itself.
      final Future<void> offline = b
          .doc('$path/o')
          .snapshots(includeMetadataChanges: true)
          .firstWhere(
            (DocumentSnapshot<Map<String, Object?>> snapshot) =>
                snapshot.metadata.isFromCache,
          )
          .timeout(stepTimeout);
      await a.disableNetwork();
      await offline;
      await _waitFor('the secondary takes the lease', () => _isPrimary(b));
      await b
          .doc('$path/o')
          .snapshots(includeMetadataChanges: true)
          .firstWhere(
            (DocumentSnapshot<Map<String, Object?>> snapshot) =>
                !snapshot.metadata.isFromCache,
          )
          .timeout(stepTimeout);
    },
  );

  test(
    'the secondary becomes primary when the primary terminates',
    skip: needsEmulator,
    () async {
      final (FirebaseFirestore a, FirebaseFirestore b) = await openBoth();
      final FirebaseFirestore writer =
          await IntegrationTestUtil.testFirestore();
      final String path = 'shared_state_${autoId()}';

      final StreamController<QuerySnapshot<Map<String, Object?>>> snapshots =
          StreamController<QuerySnapshot<Map<String, Object?>>>.broadcast();
      final StreamSubscription<QuerySnapshot<Map<String, Object?>>>
      subscription = b
          .collection(path)
          .snapshots(includeMetadataChanges: true)
          .listen(snapshots.add);
      addTearDown(subscription.cancel);

      Future<void> sees(String id, int v) => snapshots.stream
          .firstWhere(
            (QuerySnapshot<Map<String, Object?>> snapshot) =>
                !snapshot.metadata.isFromCache &&
                snapshot.docs.any(
                  (QueryDocumentSnapshot<Map<String, Object?>> doc) =>
                      doc.id == id && doc.data()['v'] == v,
                ),
          )
          .timeout(stepTimeout);

      // Through the primary first.
      Future<void> seen = sees('x', 1);
      await writer.collection(path).doc('x').set(<String, Object?>{'v': 1});
      await seen;

      await a.terminate();
      await _waitFor('the secondary takes the lease', () => _isPrimary(b));
      expect(b.client.remoteStore.canUseNetwork, isTrue);

      // Its listener goes on, now through its own watch stream.
      seen = sees('x', 2);
      await writer.collection(path).doc('x').set(<String, Object?>{'v': 2});
      await seen;

      // And it sends its own writes.
      await b
          .collection(path)
          .doc('y')
          .set(<String, Object?>{'v': 3})
          .timeout(stepTimeout);
      final DocumentSnapshot<Map<String, Object?>> onServer = await writer
          .doc('$path/y')
          .get(const GetOptions(source: Source.server));
      expect(onServer.data(), <String, Object?>{'v': 3});
    },
  );
}

/// Whether [firestore] holds the lease and acts as primary.
bool _isPrimary(FirebaseFirestore firestore) =>
    firestore.client.isPrimaryClient &&
    firestore.client.syncEngine.isPrimaryClient;

Future<void> _waitFor(String what, bool Function() condition) async {
  final Stopwatch watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed > stepTimeout) {
      throw TimeoutException(what, stepTimeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}
