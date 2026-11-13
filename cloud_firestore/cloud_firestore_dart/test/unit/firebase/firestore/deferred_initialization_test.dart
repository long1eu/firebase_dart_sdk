// Firestore.instanceFor returns at once; the client opens its cache and starts
// in the background, as the first task of its queue. These tests pin what that
// must keep: operations wait for the initialization, the first user is known
// before the cache is opened, a failed initialization fails the operations,
// terminate and clearPersistence still close and delete what the
// initialization opened, and a new app with the name of a deleted one waits for
// the old instance to close the file.

import 'dart:async';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/credentials_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/firestore_client.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/timer_task.dart';
import 'package:cloud_firestore_dart/src/internal_access.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:rxdart/rxdart.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../../util/integration_test_util.dart';
import 'clear_persistence_test.dart' show newApp, offlineSettings, openFixed;
import 'local/mock/database_mock.dart';

/// Records every open and close of the databases [inner] opens.
OpenDatabase recording(OpenDatabase inner, List<String> log) {
  return (
    String path, {
    int? version,
    OnConfigure? onConfigure,
    OnCreate? onCreate,
    OnVersionChange? onUpgrade,
    OnVersionChange? onDowngrade,
    OnOpen? onOpen,
  }) async {
    log.add('open');
    // Firestore passes every argument; the fallbacks only satisfy the types.
    final Database db = await inner(
      path,
      version: version ?? 1,
      onConfigure: onConfigure ?? (Database _) async {},
      onCreate: onCreate ?? (Database _, int _) async {},
      onUpgrade: onUpgrade ?? (Database _, int _, int _) async {},
      onDowngrade: onDowngrade ?? (Database _, int _, int _) async {},
      onOpen: onOpen ?? (Database _) async {},
    );
    return _Recording(db, log);
  };
}

class _Recording implements Database {
  _Recording(this._inner, this._log);

  final Database _inner;
  final List<String> _log;

  @override
  String get path => _inner.path;

  @override
  Future<void> execute(String statement, [List<Object?>? arguments]) =>
      _inner.execute(statement, arguments);

  @override
  Future<List<Map<String, dynamic>>> query(
    String statement, [
    List<Object?>? arguments,
  ]) => _inner.query(statement, arguments);

  @override
  Future<int> delete(String statement, [List<Object?>? arguments]) =>
      _inner.delete(statement, arguments);

  @override
  void close() {
    _log.add('close');
    _inner.close();
  }
}

/// A credentials provider whose first user arrives when [release] is called.
class _LateUser extends CredentialsProvider {
  final Completer<void> _released = Completer<void>();

  void release() => _released.complete();

  @override
  Future<String?> get token => Future<String?>.value(null);

  @override
  void invalidateToken() {}

  @override
  Stream<User> get onChange => Stream<User>.fromFuture(
    _released.future.then((_) => const User('late-user')),
  );
}

class _OpenFailed implements Exception {
  @override
  String toString() => 'the database could not be opened';
}

/// The error of the opener: [Firestore.initialized] fails with it as is; the operations report it as is or wrapped
/// in a [FirestoreError] that names it, as they do for any unexpected error.
final Matcher throwsOpenFailed = throwsA(
  predicate<Object>(
    (Object e) => '$e'.contains('could not be opened'),
    'the error of the opener',
  ),
);

void main() {
  int counter = 0;
  String uniqueDb() => 'deferred-init-${const Uuid().v4()}.db';
  String uniqueApp() => 'deferredInit${counter++}';

  test(
    'instanceFor returns before the cache is open; operations wait for it',
    () async {
      final FirebaseApp app = newApp(uniqueApp());
      addTearDown(app.delete);
      final String dbName = uniqueDb();
      addTearDown(() => DatabaseMock.deleteDatabaseFiles(dbName));
      final List<String> log = <String>[];

      final Firestore firestore = Firestore.instanceFor(
        app: app,
        settings: offlineSettings,
        openDatabase: recording(openFixed(dbName), log),
      );
      addTearDown(firestore.terminate);

      // Synchronous: nothing has been opened yet.
      expect(log, isEmpty);
      expect(identical(Firestore.instanceFor(app: app), firestore), isTrue);
      expect(firestore.persistentCacheIndexManager, isNotNull);

      // A write and a cache read issued right away run after the initialization.
      unawaited(firestore.doc('rooms/eros').set(<String, Object?>{'a': 1}));
      final DocumentSnapshot<Map<String, Object?>> read = await firestore
          .doc('rooms/eros')
          .get(Source.cache);
      expect(read.data, <String, Object?>{'a': 1});
      expect(log, <String>['open']);
    },
  );

  test('the cache is opened only once the first user is known', () async {
    final String dbName = uniqueDb();
    addTearDown(() => DatabaseMock.deleteDatabaseFiles(dbName));
    final List<String> log = <String>[];
    final _LateUser credentials = _LateUser();
    final BehaviorSubject<bool> network = BehaviorSubject<bool>.seeded(false);
    addTearDown(network.close);

    final FirestoreClient client = FirestoreClient.start(
      IntegrationTestUtil.testEnvDatabaseInfo(),
      FirestoreSettings(),
      credentials,
      recording(openFixed(dbName), log),
      network,
      TaskScheduler('deferred'),
    );
    addTearDown(client.shutdown);

    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(log, isEmpty, reason: 'opened before the first user was known');

    credentials.release();
    await client.initialized;
    expect(log, <String>['open']);
  });

  test('a failed initialization fails every operation with its error', () async {
    final FirebaseApp app = newApp(uniqueApp());
    addTearDown(app.delete);

    final Firestore firestore = Firestore.instanceFor(
      app: app,
      settings: offlineSettings,
      openDatabase:
          (
            String path, {
            int? version,
            OnConfigure? onConfigure,
            OnCreate? onCreate,
            OnVersionChange? onUpgrade,
            OnVersionChange? onDowngrade,
            OnOpen? onOpen,
          }) async => throw _OpenFailed(),
    );

    await expectLater(firestore.initialized, throwsOpenFailed);
    await expectLater(firestore.doc('rooms/eros').get(), throwsOpenFailed);
    await expectLater(
      firestore.doc('rooms/eros').set(<String, Object?>{}),
      throwsOpenFailed,
    );
    await expectLater(
      firestore.runTransaction<void>((Transaction transaction) async {}),
      throwsOpenFailed,
    );

    // Terminating the broken instance works, and then clearing has nothing to delete.
    await firestore.terminate();
    await firestore.clearPersistence();
  });

  test(
    'terminate right after instanceFor closes what the initialization opened',
    () async {
      final FirebaseApp app = newApp(uniqueApp());
      addTearDown(app.delete);
      final String dbName = uniqueDb();
      addTearDown(() => DatabaseMock.deleteDatabaseFiles(dbName));
      final List<String> log = <String>[];

      final Firestore firestore = Firestore.instanceFor(
        app: app,
        settings: offlineSettings,
        openDatabase: recording(openFixed(dbName), log),
      );
      await firestore.terminate();
      expect(log, <String>['open', 'close']);

      // The file the initialization opened is known, so clearPersistence deletes it.
      expect(DatabaseMock.pathForName(dbName).existsSync(), isTrue);
      await firestore.clearPersistence();
      expect(DatabaseMock.pathForName(dbName).existsSync(), isFalse);
    },
  );

  test(
    'a new app with the name of a deleted one opens the cache after it is closed',
    () async {
      final String name = uniqueApp();
      final String dbName = uniqueDb();
      addTearDown(() => DatabaseMock.deleteDatabaseFiles(dbName));
      final List<String> log = <String>[];

      final FirebaseApp first = newApp(name);
      final Firestore old = Firestore.instanceFor(
        app: first,
        settings: offlineSettings,
        openDatabase: recording(openFixed(dbName), log),
      );
      await old.initialized;

      first.delete();
      final FirebaseApp second = newApp(name);
      addTearDown(second.delete);
      final Firestore current = Firestore.instanceFor(
        app: second,
        settings: offlineSettings,
        openDatabase: recording(openFixed(dbName), log),
      );
      addTearDown(current.terminate);

      expect(identical(current, old), isFalse);
      await current.initialized;
      expect(log, <String>['open', 'close', 'open']);
    },
  );

  // Review R2-L3: instances that were still being created were kept by app name
  // only, so an app deleted and recreated in that window got the instance of the
  // old app object. instanceFor is synchronous since b1a5b833; this pins it.
  test('an app deleted while its instance is still opening does not hand that '
      'instance to the new app of the same name', () async {
    final String name = uniqueApp();
    final String dbName = uniqueDb();
    addTearDown(() => DatabaseMock.deleteDatabaseFiles(dbName));
    final List<String> log = <String>[];

    final FirebaseApp first = newApp(name);
    final Firestore old = Firestore.instanceFor(
      app: first,
      settings: offlineSettings,
      openDatabase: recording(openFixed(dbName), log),
    );
    // Not awaited: the old instance is still opening its cache.
    first.delete();
    final FirebaseApp second = newApp(name);
    addTearDown(second.delete);
    final Firestore current = Firestore.instanceFor(
      app: second,
      settings: offlineSettings,
      openDatabase: recording(openFixed(dbName), log),
    );
    addTearDown(current.terminate);

    expect(identical(current, old), isFalse);
    expect(identical(current.app, second), isTrue);
    expect(identical(Firestore.instanceFor(app: second), current), isTrue);

    // The delete event of the first app (delivered asynchronously) must not
    // shut down the instance of the second one.
    await current.initialized;
    await Future<void>.delayed(Duration.zero);
    expect(identical(Firestore.instanceFor(app: second), current), isTrue);
    // Throws if the instance was terminated.
    final QuerySnapshot<Map<String, Object?>> cached = await current
        .collection('coll')
        .get(Source.cache);
    expect(cached.docs, isEmpty);
    expect(log, <String>['open', 'close', 'open']);
  });
}
