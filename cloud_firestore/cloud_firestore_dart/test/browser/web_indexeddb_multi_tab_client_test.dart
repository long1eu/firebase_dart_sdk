// Two FirebaseFirestore instances in one page on one IndexedDB cache in multi-tab mode (IndexedDbCacheSettings.multiTab),
// against the emulator: the primary listens and writes for both, the secondary gets the results through LocalStorage
// and takes over when the primary goes. A `storage` event is not delivered to the window that wrote, so the second
// instance uses the LocalStorage of an `about:blank` frame (same origin) through the internal storage hook.
//
//   dart test -j 1 -p chrome -c dart2wasm test/browser/web_indexeddb_multi_tab_client_test.dart

@TestOn('browser')
library;

import 'dart:async';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/indexeddb_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/empty_credentials_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/database_info.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/firestore_client.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/web_storage_shared_client_state_storage.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/timer_task.dart';
import 'package:cloud_firestore_dart/src/internal_access.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:rxdart/subjects.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

import 'browser_test_util.dart';

int _names = 0;

const Duration stepTimeout = Duration(seconds: 20);

void main() {
  late web.HTMLIFrameElement frame;
  final List<FirebaseFirestore> instances = <FirebaseFirestore>[];
  final List<FirebaseApp> apps = <FirebaseApp>[];

  setUp(() async {
    await loadEmulatorPort();
    frame = web.document.createElement('iframe') as web.HTMLIFrameElement;
    web.document.body!.append(frame);
  });

  tearDown(() async {
    for (final FirebaseFirestore firestore in instances.reversed) {
      await firestore.terminate();
    }
    instances.clear();
    for (final FirebaseApp app in apps) {
      await app.delete();
    }
    apps.clear();
    frame.remove();
  });

  String newAppName() =>
      'multi-tab-${DateTime.now().microsecondsSinceEpoch}-${_names++}';

  /// An instance made through the public API: its app name is the name of its cache.
  Future<FirebaseFirestore> publicInstance(
    String appName, {
    bool multiTab = true,
  }) async {
    final FirebaseApp app = FirebaseApp.withOptions(
      const FirebaseOptions(
        apiKey: 'demo-key',
        appId: '1:1234567890:dart:browser',
        projectId: projectId,
      ),
      name: appName,
    );
    apps.add(app);
    final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
      app: app,
      settings: Settings(
        cacheSettings: indexedDbCacheSettings(multiTab: multiTab),
      ).withEmulator(emulatorHost, emulatorPort),
    );
    instances.add(firestore);
    await firestore.initialized;
    return firestore;
  }

  /// A second instance on the cache of [appName]. In multi-tab mode it shares its state through the LocalStorage of
  /// the frame, as another tab would.
  Future<FirebaseFirestore> frameInstance(
    String appName, {
    bool multiTab = true,
  }) async {
    final Settings settings = Settings(
      cacheSettings: indexedDbCacheSettings(multiTab: multiTab),
    ).withEmulator(emulatorHost, emulatorPort);
    final DatabaseId databaseId = DatabaseId.forProject(projectId);
    final TaskScheduler scheduler = TaskScheduler('$appName-frame');
    final FirestoreClient client = await FirestoreClient.initialize(
      DatabaseInfo(
        databaseId,
        appName,
        settings.host,
        sslEnabled: settings.sslEnabled,
        port: settings.port,
        apiKey: 'demo-key',
      ),
      settings,
      EmptyCredentialsProvider(),
      null,
      BehaviorSubject<bool>.seeded(true),
      scheduler,
      sharedClientStateStorage: multiTab
          ? WebStorageSharedClientStateStorage(frame.contentWindow)
          : null,
    );
    final FirebaseFirestore firestore = FirestoreInternal.create(
      databaseId,
      null,
      client,
      scheduler,
    );
    instances.add(firestore);
    return firestore;
  }

  Future<void> waitFor(String what, bool Function() condition) async {
    final Stopwatch watch = Stopwatch()..start();
    while (!condition()) {
      if (watch.elapsed > stepTimeout) {
        fail('Timed out waiting until $what');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  /// Opens the primary (public API) and the secondary (frame storage) on one cache.
  Future<(FirebaseFirestore, FirebaseFirestore)> openBoth() async {
    final String appName = newAppName();
    final FirebaseFirestore primary = await publicInstance(appName);
    final FirebaseFirestore secondary = await frameInstance(appName);
    await waitFor(
      'the first instance is primary and the second secondary',
      () =>
          primary.client.isPrimaryClient &&
          primary.client.syncEngine.isPrimaryClient &&
          !secondary.client.isPrimaryClient,
    );
    expect(primary.client.sharesClientState, isTrue);
    expect(secondary.client.sharesClientState, isTrue);
    return (primary, secondary);
  }

  test('a listener of the secondary gets a change from the server', () async {
    final (_, FirebaseFirestore secondary) = await openBoth();
    final FirebaseFirestore writer = await newClient();
    final String path = '${newCollectionName()}/doc';

    final EventLog<DocumentSnapshot<Map<String, Object?>>> log =
        EventLog<DocumentSnapshot<Map<String, Object?>>>(
          secondary.doc(path).snapshots(includeMetadataChanges: true),
        );
    await writer.doc(path).set(<String, Object?>{'value': 1});

    final DocumentSnapshot<Map<String, Object?>> snapshot = await log.waitFor(
      (DocumentSnapshot<Map<String, Object?>> s) =>
          s.exists && s.data()!['value'] == 1 && !s.metadata.isFromCache,
    );
    expect(snapshot.metadata.hasPendingWrites, isFalse);
    expect(secondary.client.isPrimaryClient, isFalse);
  });

  test('a write of the secondary is acknowledged', () async {
    final (_, FirebaseFirestore secondary) = await openBoth();
    final String path = '${newCollectionName()}/doc';

    final EventLog<DocumentSnapshot<Map<String, Object?>>> log =
        EventLog<DocumentSnapshot<Map<String, Object?>>>(
          secondary.doc(path).snapshots(includeMetadataChanges: true),
        );
    await secondary.doc(path).set(<String, Object?>{'value': 'from b'});
    await log.waitFor(
      (DocumentSnapshot<Map<String, Object?>> s) =>
          s.exists && s.metadata.hasPendingWrites,
    );
    await log.waitFor(
      (DocumentSnapshot<Map<String, Object?>> s) =>
          s.exists &&
          s.data()!['value'] == 'from b' &&
          !s.metadata.hasPendingWrites,
    );

    // The server has it.
    final FirebaseFirestore reader = await newClient();
    final DocumentSnapshot<Map<String, Object?>> server = await reader
        .doc(path)
        .get(const GetOptions(source: Source.server));
    expect(server.data(), <String, Object?>{'value': 'from b'});
  });

  test(
    'the secondary takes over when the primary terminates, and keeps its listener',
    () async {
      final (FirebaseFirestore primary, FirebaseFirestore secondary) =
          await openBoth();
      final FirebaseFirestore writer = await newClient();
      final String path = '${newCollectionName()}/doc';
      await writer.doc(path).set(<String, Object?>{'value': 1});

      final EventLog<DocumentSnapshot<Map<String, Object?>>> log =
          EventLog<DocumentSnapshot<Map<String, Object?>>>(
            secondary.doc(path).snapshots(includeMetadataChanges: true),
          );
      await log.waitFor(
        (DocumentSnapshot<Map<String, Object?>> s) =>
            s.exists && s.data()!['value'] == 1 && !s.metadata.isFromCache,
      );

      final Stopwatch watch = Stopwatch()..start();
      await primary.terminate();
      await waitFor(
        'the secondary is primary',
        () =>
            secondary.client.isPrimaryClient &&
            secondary.client.syncEngine.isPrimaryClient,
      );
      print(
        'The secondary took over ${watch.elapsedMilliseconds} ms after the primary terminated.',
      );
      // At once: it does not wait for its next lease refresh (every 4 s).
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));

      await writer.doc(path).set(<String, Object?>{'value': 2});
      await log.waitFor(
        (DocumentSnapshot<Map<String, Object?>> s) =>
            s.exists && s.data()!['value'] == 2 && !s.metadata.isFromCache,
      );
      expect(log.errors, isEmpty);
    },
  );

  Matcher refusal() => isA<FirestoreException>()
      .having(
        (FirestoreException e) => e.errorCode,
        'errorCode',
        FirestoreErrorCode.failedPrecondition,
      )
      .having(
        (FirestoreException e) => e.message,
        'message',
        contains('only one tab at a time may use it'),
      );

  test('a one-tab instance is refused by a multi-tab one', () async {
    final String appName = newAppName();
    await publicInstance(appName);
    await expectLater(
      frameInstance(appName, multiTab: false),
      throwsA(refusal()),
    );
  });

  test('a multi-tab instance is refused by a one-tab one', () async {
    final String appName = newAppName();
    await publicInstance(appName, multiTab: false);
    await expectLater(frameInstance(appName), throwsA(refusal()));
  });
}
