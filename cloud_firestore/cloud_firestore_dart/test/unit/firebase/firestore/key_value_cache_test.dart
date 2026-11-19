// The key-value cache (keyValueCacheSettings) through the public API: writes made offline survive a restart, the cache
// can be cleared, a store is the cache of one instance at a time, and the features it lacks fail loudly.

import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore_dart/cache_store.dart';
import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:test/test.dart';

import '../../../../example/cache_store/memory_log/memory_log_store.dart';

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('key_value_cache_test_');
  });

  tearDown(() {
    directory.deleteSync(recursive: true);
  });

  FirebaseApp newApp(String name) => FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: 'key',
      appId: 'appId',
      projectId: 'projectId',
    ),
    name: name,
  );

  // Nothing listens on port 1: writes are applied locally and stay pending.
  Settings offline(CacheStore store) => Settings()
      .withEmulator('127.0.0.1', 1)
      .copyWith(cacheSettings: keyValueCacheSettings(store: store));

  test(
    'writes made offline survive a restart, and clearPersistence removes them',
    () async {
      final FirebaseApp app = newApp('keyValueRestart');
      addTearDown(app.delete);
      final String path = '${directory.path}/cache.log';

      FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
        app: app,
        settings: offline(MemoryLogStore(path)),
      );
      unawaited(
        firestore.doc('notes/a').set(<String, Object?>{'text': 'first'}),
      );
      unawaited(
        firestore.doc('notes/b').set(<String, Object?>{'text': 'second'}),
      );
      unawaited(
        firestore.doc('notes/a').update(<String, Object?>{'done': true}),
      );
      expect(await firestore.getPendingWriteCount(), 3);
      await firestore.terminate();

      // A new store object over the same file: everything comes from the log.
      firestore = FirebaseFirestore.instanceFor(
        app: app,
        settings: offline(MemoryLogStore(path)),
      );
      expect(await firestore.getPendingWriteCount(), 3);
      final QuerySnapshot<Map<String, Object?>> notes = await firestore
          .collection('notes')
          .get(GetOptions(source: Source.cache));
      expect(
        <String, Map<String, Object?>>{
          for (final QueryDocumentSnapshot<Map<String, Object?>> note
              in notes.docs)
            note.id: note.data(),
        },
        <String, Map<String, Object?>>{
          'a': <String, Object?>{'text': 'first', 'done': true},
          'b': <String, Object?>{'text': 'second'},
        },
      );
      expect(notes.metadata.hasPendingWrites, isTrue);
      expect(firestore.persistentCacheIndexManager, isNull);
      // ignore: deprecated_member_use_from_same_package
      expect(
        () => firestore.setIndexConfigurationFromJSON('{"indexes": []}'),
        throwsStateError,
      );

      await firestore.terminate();
      await firestore.clearPersistence();

      firestore = FirebaseFirestore.instanceFor(
        app: app,
        settings: offline(MemoryLogStore(path)),
      );
      expect(await firestore.getPendingWriteCount(), 0);
      expect(
        (await firestore
                .collection('notes')
                .get(GetOptions(source: Source.cache)))
            .docs,
        isEmpty,
      );
      await firestore.terminate();
    },
  );

  test('a store is the cache of one running instance at a time', () async {
    final FirebaseApp first = newApp('keyValueFirst');
    final FirebaseApp second = newApp('keyValueSecond');
    addTearDown(first.delete);
    addTearDown(second.delete);
    final MemoryLogStore store = MemoryLogStore();

    final FirebaseFirestore one = FirebaseFirestore.instanceFor(
      app: first,
      settings: offline(store),
    );
    await one.getPendingWriteCount();
    final FirebaseFirestore two = FirebaseFirestore.instanceFor(
      app: second,
      settings: offline(store),
    );
    await expectLater(
      two.getPendingWriteCount(),
      throwsA(
        isA<FirestoreException>().having(
          (FirestoreException e) => e.code,
          'code',
          FirestoreErrorCode.failedPrecondition.code,
        ),
      ),
    );
    await two.terminate();
    await one.terminate();
  });

  test('a store with the cache of another database is refused', () async {
    final FirebaseApp app = newApp('keyValueOtherDatabase');
    addTearDown(app.delete);
    final MemoryLogStore store = MemoryLogStore();

    final FirebaseFirestore one = FirebaseFirestore.instanceFor(
      app: app,
      settings: offline(store),
    );
    await one.getPendingWriteCount();
    await one.terminate();

    final FirebaseFirestore other = FirebaseFirestore.instanceFor(
      app: app,
      databaseId: 'other',
      settings: offline(store),
    );
    await expectLater(
      other.getPendingWriteCount(),
      throwsA(isA<FirestoreException>()),
    );
    await other.terminate();
  });
}
