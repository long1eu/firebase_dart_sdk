// Helpers of the chaos tests: a client that reaches the emulator through a [ChaosProxy], and an untouched client
// (the oracle) that talks to the emulator directly.

import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/connectivity_change_detector.dart';
import 'package:firebase_app_dart/internal.dart' show InternalLogLevel;
import 'package:test/test.dart';

import '../../../../unit/firebase/firestore/local/mock/database_mock.dart';
import '../../../../util/chaos_proxy.dart';
import '../../../../util/integration_test_util.dart';
import '../../../../util/test_backend.dart';

/// Why the chaos tests cannot run, or null: they only ever run against the emulator.
String? get chaosSkipReason {
  if (IntegrationTestUtil.emulatorHost == null) {
    return 'FIRESTORE_EMULATOR_HOST is not set: the chaos tests only run against the emulator';
  }
  return null;
}

/// Whether the clients of this run use the web transport (REST and WebChannel) instead of gRPC.
bool get usesWebTransport =>
    (Platform.environment['FIRESTORE_TEST_TRANSPORT'] ?? '')
        .startsWith('webchannel');

/// The skip reason of a scenario that cannot hold on the web transport, or null on gRPC.
String? webTransportSkipReason(String why) =>
    usesWebTransport ? 'Not on the web transport: $why' : null;

int _names = 0;

/// A name that no other test (or run) uses.
String uniqueName(String prefix) =>
    '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_names++}';

class ChaosEnv {
  ChaosEnv._(this.proxy, this.oracle);

  /// Starts a proxy in front of the emulator and creates the oracle.
  static Future<ChaosEnv> start() async {
    final EmulatorAddress emulator =
        EmulatorAddress.parse(IntegrationTestUtil.emulatorHost!);
    final ChaosProxy proxy =
        await ChaosProxy.start(emulator.host, emulator.port);
    final Firestore oracle = await IntegrationTestUtil.testFirestore();
    return ChaosEnv._(proxy, oracle);
  }

  final ChaosProxy proxy;

  /// A client that talks to the emulator directly and is never disturbed.
  final Firestore oracle;

  final List<ChaosProxy> _extraProxies = <ChaosProxy>[];

  FirestoreSettings _settings(ChaosProxy proxy) =>
      FirestoreSettings(host: proxy.host, port: proxy.port, sslEnabled: false);

  /// A client that reaches the emulator through [proxy] (the proxy of this environment by default).
  ///
  /// With [fixedDbName] the client uses that SQLite file and keeps it, so that a later client created with the same
  /// name starts from the persisted state (a restart).
  ///
  /// The clients of the tests have no connectivity detector unless [connectivityDetector] is given.
  Future<Firestore> newClient(
      {ChaosProxy? proxy,
      String? fixedDbName,
      ConnectivityChangeDetector? connectivityDetector}) {
    return IntegrationTestUtil.testFirestoreInstance(
      IntegrationTestUtil.provider.projectId,
      InternalLogLevel.w,
      _settings(proxy ?? this.proxy),
      IntegrationTestUtil.currentDatabasePath,
      fixedDbName: fixedDbName,
      connectivityDetector: connectivityDetector,
    );
  }

  /// A second proxy, for a client whose network fails independently.
  Future<ChaosProxy> newProxy() async {
    final EmulatorAddress emulator =
        EmulatorAddress.parse(IntegrationTestUtil.emulatorHost!);
    final ChaosProxy proxy =
        await ChaosProxy.start(emulator.host, emulator.port);
    _extraProxies.add(proxy);
    return proxy;
  }

  /// A fresh SQLite file name for a client that is restarted.
  String newDatabaseName() {
    final String name = 'integration/chaos/${uniqueName('restart')}.db';
    DatabaseMock.deleteDatabaseFiles(name);
    return name;
  }

  /// The documents of [collectionPath] on the backend, by id, as the oracle reads them.
  Future<Map<String, Map<String, Object?>>> serverDocs(
      String collectionPath) async {
    final QuerySnapshot<Map<String, Object?>> snapshot =
        await oracle.collection(collectionPath).get(Source.server);
    return docsById(snapshot);
  }

  Future<void> close() async {
    // Let the clients shut down against a working network.
    proxy.restore();
    for (final ChaosProxy extra in _extraProxies) {
      extra.restore();
    }
    await IntegrationTestUtil.tearDown();
    await proxy.close();
    for (final ChaosProxy extra in _extraProxies) {
      await extra.close();
    }
  }
}

Map<String, Map<String, Object?>> docsById(
    QuerySnapshot<Map<String, Object?>> snapshot) {
  return <String, Map<String, Object?>>{
    for (final QueryDocumentSnapshot<Map<String, Object?>> doc in snapshot.docs)
      doc.id: doc.data,
  };
}

/// Waits until [condition] holds, checking every 25 ms. Fails with [reason] (and what [describe] returns) after
/// [timeout].
Future<void> eventually(
  FutureOr<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 15),
  String reason = 'condition',
  Object? Function()? describe,
}) async {
  final Stopwatch watch = Stopwatch()..start();
  while (true) {
    if (await condition()) {
      return;
    }
    if (watch.elapsed > timeout) {
      fail('Timed out after $timeout waiting for: $reason'
          '${describe == null ? '' : '\n${describe()}'}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

Future<void> pause(int milliseconds) =>
    Future<void>.delayed(Duration(milliseconds: milliseconds));

/// Listens to a query with metadata changes, keeps every snapshot, and checks each of them as it arrives: no
/// duplicate documents, and the document changes lead from the previous snapshot to this one.
class RecordingListener {
  RecordingListener(this.query) {
    _subscription = query
        .getSnapshotsWithOptions(const SnapshotListenOptions(
            metadataChanges: MetadataChanges.include))
        .listen(_onSnapshot, onError: errors.add);
  }

  final Query<Map<String, Object?>> query;
  final List<QuerySnapshot<Map<String, Object?>>> events =
      <QuerySnapshot<Map<String, Object?>>>[];
  final List<Object> errors = <Object>[];
  final List<String> violations = <String>[];
  late final StreamSubscription<QuerySnapshot<Map<String, Object?>>>
      _subscription;
  List<String> _replayed = <String>[];

  QuerySnapshot<Map<String, Object?>> get last => events.last;

  static List<String> idsOf(QuerySnapshot<Map<String, Object?>> snapshot) =>
      snapshot.docs
          .map((QueryDocumentSnapshot<Map<String, Object?>> d) => d.id)
          .toList();

  void _onSnapshot(QuerySnapshot<Map<String, Object?>> snapshot) {
    final int index = events.length;
    events.add(snapshot);
    final List<String> ids = idsOf(snapshot);
    if (ids.toSet().length != ids.length) {
      violations.add('event $index has duplicate documents: $ids');
    }
    // Replay the changes on the previous list of documents.
    final List<String> replayed = List<String>.of(_replayed);
    try {
      for (final DocumentChange<Map<String, Object?>> change
          in snapshot.getDocumentChanges(MetadataChanges.include)) {
        if (change.type != DocumentChangeType.added) {
          if (replayed[change.oldIndex] != change.document.id) {
            violations.add('event $index: change of ${change.document.id} has '
                'oldIndex ${change.oldIndex}, which is ${replayed[change.oldIndex]}');
          }
          replayed.removeAt(change.oldIndex);
        }
        if (change.type != DocumentChangeType.removed) {
          replayed.insert(change.newIndex, change.document.id);
        }
      }
    } on RangeError catch (e) {
      violations.add('event $index: a document change is out of range: $e');
    }
    if (replayed.join(',') != ids.join(',')) {
      violations.add('event $index: the document changes lead to $replayed, '
          'but the snapshot has $ids');
    }
    _replayed = ids;
    if (snapshot.metadata.hasPendingWrites !=
        snapshot.docs.any((QueryDocumentSnapshot<Map<String, Object?>> d) =>
            d.metadata.hasPendingWrites)) {
      violations.add('event $index: hasPendingWrites of the snapshot is '
          '${snapshot.metadata.hasPendingWrites}, but not of its documents');
    }
  }

  String describe() {
    final StringBuffer buffer = StringBuffer();
    final int from = events.length > 6 ? events.length - 6 : 0;
    for (int i = from; i < events.length; i++) {
      buffer.writeln('event $i: fromCache=${events[i].metadata.isFromCache} '
          'pending=${events[i].metadata.hasPendingWrites} ${idsOf(events[i])}');
    }
    buffer
      ..writeln('errors: $errors')
      ..writeln('violations: $violations');
    return buffer.toString();
  }

  /// Waits for a snapshot that is in sync with the backend.
  Future<void> synced() =>
      eventually(() => events.isNotEmpty && !last.metadata.isFromCache,
          reason: 'a snapshot in sync with the backend', describe: describe);

  /// Waits until the last snapshot is in sync, without pending writes, and holds [ids] in that order with the data
  /// of [server]; then checks that nothing was wrong with any snapshot on the way and that it stays that way.
  Future<void> settlesOn(
      List<String> ids, Map<String, Map<String, Object?>> server) async {
    bool settled() =>
        events.isNotEmpty &&
        !last.metadata.isFromCache &&
        !last.metadata.hasPendingWrites &&
        idsOf(last).join(',') == ids.join(',');
    await eventually(settled,
        timeout: const Duration(seconds: 20),
        reason: 'the listener to settle on $ids',
        describe: describe);
    // Nothing comes after it that disagrees.
    await pause(300);
    expect(settled(), isTrue,
        reason: 'the listener moved away:\n${describe()}');
    for (final QueryDocumentSnapshot<Map<String, Object?>> doc in last.docs) {
      expect(doc.data, server[doc.id], reason: doc.id);
    }
    expect(errors, isEmpty);
    expect(violations, isEmpty);
  }

  Future<void> cancel() => _subscription.cancel();
}
