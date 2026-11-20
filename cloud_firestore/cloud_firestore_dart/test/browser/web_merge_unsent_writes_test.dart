// `mergeUnsentWrites` on the IndexedDB engine (IndexedDbCacheSettings) in a browser against the emulator, a smoke
// test: offline edits of one document become one pending write and reach the backend as the edits would; a queue
// written with the setting off is merged when the next client on the same database starts with it on. The rules
// themselves are tested on the VM (test/unit/firebase/firestore/local/merge_unsent_writes_*_test.dart and
// test/integration/firebase/firestore/merge_unsent_writes_*_test.dart).
//
//   dart test -j 1 -p chrome -c dart2wasm test/browser/web_merge_unsent_writes_test.dart

@TestOn('browser')
library;

import 'dart:async';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/indexeddb_cache.dart';
import 'package:cloud_firestore_dart/src/internal_access.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:test/test.dart';

import 'browser_test_util.dart'
    show emulatorHost, emulatorPort, loadEmulatorPort, newCollectionName;

int _names = 0;

final Map<FirebaseFirestore, FirebaseApp> _apps =
    <FirebaseFirestore, FirebaseApp>{};

Future<void> _shutDown(FirebaseFirestore firestore) async {
  await firestore.terminate();
  await _apps.remove(firestore)?.delete();
}

/// A client on the IndexedDB engine; the same [appName] opens the same database.
Future<FirebaseFirestore> _client(String appName, {required bool merge}) async {
  await loadEmulatorPort();
  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: 'demo-key',
      appId: '1:1234567890:dart:browser',
      projectId: 'demo-test',
    ),
    name: appName,
  );
  final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
    app: app,
    settings: Settings(
      cacheSettings: indexedDbCacheSettings(mergeUnsentWrites: merge),
    ).withEmulator(emulatorHost, emulatorPort),
  );
  _apps[firestore] = app;
  addTearDown(() => _shutDown(firestore));
  await firestore.initialized;
  return firestore;
}

String _appName() =>
    'merge-${DateTime.now().microsecondsSinceEpoch}-${_names++}';

const GetOptions _cache = GetOptions(source: Source.cache);
const GetOptions _server = GetOptions(source: Source.server);

void main() {
  test('offline edits of one document are one pending write', () async {
    final FirebaseFirestore firestore = await _client(_appName(), merge: true);
    final CollectionReference<Map<String, Object?>> collection = firestore
        .collection(newCollectionName());
    final DocumentReference<Map<String, Object?>> a = collection.doc('a');
    await firestore.disableNetwork();

    final List<Future<void>> writes = <Future<void>>[
      a.set(<String, Object?>{'n': 0}),
      for (int i = 1; i <= 5; i++)
        a.update(<String, Object?>{
          'n': FieldValue.increment(1),
          'at': FieldValue.serverTimestamp(),
        }),
      collection.doc('b').set(<String, Object?>{'x': 1}),
      a.update(<String, Object?>{'last': true}),
    ];
    final DocumentSnapshot<Map<String, Object?>> offline = await a.get(_cache);
    expect(offline.metadata.hasPendingWrites, isTrue);
    expect(offline.data(), <String, Object?>{'n': 5, 'at': null, 'last': true});
    // The set and the updates of a in one write, and b.
    expect(await firestore.getPendingWriteCount(), 2);

    await firestore.enableNetwork();
    await Future.wait(writes);
    final Map<String, Object?> server = (await a.get(_server)).data()!;
    expect(server['at'], isA<Timestamp>());
    expect(server..remove('at'), <String, Object?>{'n': 5, 'last': true});
    expect((await collection.doc('b').get(_server)).data(), <String, Object?>{
      'x': 1,
    });
  });

  test(
    'a queue written with the setting off is merged by the next client on the database',
    () async {
      final String appName = _appName();
      final String name = newCollectionName();
      FirebaseFirestore firestore = await _client(appName, merge: false);
      DocumentReference<Map<String, Object?>> a = firestore
          .collection(name)
          .doc('a');
      await firestore.disableNetwork();
      for (int i = 0; i < 20; i++) {
        unawaited(
          a
              .set(<String, Object?>{'i': i}, SetOptions(merge: true))
              .catchError((Object _) {}),
        );
      }
      expect(await firestore.getPendingWriteCount(), 20);
      await _shutDown(firestore);

      firestore = await _client(appName, merge: true);
      a = firestore.collection(name).doc('a');
      await firestore.disableNetwork();
      // The merge at start runs as operations of the client; a read waits for the first part of it.
      expect((await a.get(_cache)).data(), <String, Object?>{'i': 19});
      expect(await firestore.getPendingWriteCount(), 1);

      await firestore.enableNetwork();
      await firestore.waitForPendingWrites();
      expect((await a.get(_server)).data(), <String, Object?>{'i': 19});
    },
  );
}
