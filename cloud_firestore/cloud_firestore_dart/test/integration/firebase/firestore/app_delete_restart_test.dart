// FirebaseApp.delete() terminates the Firestore instances of the app. A new
// app with the same name must then get a working instance on the same SQLite
// file: the old connection is closed before the new one is opened, the
// in-process lock of the database is released, and the cache is still there.
//
// Uses the opener of example/sqlite_database.dart, the one users are told to
// copy.

import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/src/internal_access.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:test/test.dart';

import '../../../../example/sqlite_database.dart';
import '../../../util/integration_test_util.dart';

/// Wraps [inner] to record when connections are opened and closed.
OpenDatabase recording(OpenDatabase inner, List<String> log) {
  return (
    String name, {
    int? version,
    OnConfigure? onConfigure,
    OnCreate? onCreate,
    OnVersionChange? onUpgrade,
    OnVersionChange? onDowngrade,
    OnOpen? onOpen,
  }) async {
    // Firestore passes every argument; the fallbacks only satisfy the types.
    final Database db = await inner(name,
        version: version ?? 1,
        onConfigure: onConfigure ?? (Database _) async {},
        onCreate: onCreate ?? (Database _, int __) async {},
        onUpgrade: onUpgrade ?? (Database _, int __, int ___) async {},
        onDowngrade: onDowngrade ?? (Database _, int __, int ___) async {},
        onOpen: onOpen ?? (Database _) async {});
    log.add('open');
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
  Future<List<Map<String, dynamic>>> query(String statement,
          [List<Object?>? arguments]) =>
      _inner.query(statement, arguments);

  @override
  Future<int> delete(String statement, [List<Object?>? arguments]) =>
      _inner.delete(statement, arguments);

  @override
  void close() {
    _log.add('close');
    _inner.close();
  }
}

void main() {
  final String? skip = IntegrationTestUtil.emulatorHost == null
      ? 'Needs the Firestore emulator: set FIRESTORE_EMULATOR_HOST.'
      : null;

  late Directory directory;
  late List<String> log;
  late String appName;
  final List<Firestore> opened = <Firestore>[];

  setUp(() {
    directory = Directory.systemTemp.createTempSync('firestore_app_delete_');
    log = <String>[];
    appName = 'app-delete-${DateTime.now().microsecondsSinceEpoch}';
  });

  tearDown(() async {
    for (final Firestore firestore in opened) {
      await firestore.terminate();
    }
    opened.clear();
    for (final FirebaseApp app in FirebaseApp.apps) {
      if (app.name == appName) {
        app.delete();
      }
    }
    directory.deleteSync(recursive: true);
  });

  FirebaseApp newApp() {
    return FirebaseApp.withOptions(
      FirebaseOptions(
        apiKey: 'key',
        applicationId: 'appId',
        projectId: IntegrationTestUtil.provider.projectId,
      ),
      name: appName,
    );
  }

  Future<Firestore> open(FirebaseApp app) async {
    final FirestoreSettings base = IntegrationTestUtil.newTestSettings();
    final Firestore firestore = Firestore.instanceFor(
      app: app,
      openDatabase: recording(sqliteOpener(directory), log),
      settings: FirestoreSettings(cacheSettings: PersistentCacheSettings())
          .withEmulator(base.host, base.port),
    );
    opened.add(firestore);
    // instanceFor returns at once; the log below is about when the cache is opened.
    await firestore.initialized;
    return firestore;
  }

  List<String> databaseFiles() => <String>[
        for (final FileSystemEntity file in directory.listSync())
          if (file.path.endsWith('.db')) file.uri.pathSegments.last,
      ];

  bool isTerminated(Object? e) =>
      e is FirestoreError &&
      e.code == FirestoreErrorCode.failedPrecondition &&
      e.message == 'The client has already been terminated.';

  test('a new app with the same name reopens the cache of a deleted app',
      () async {
    final FirebaseApp app = newApp();
    final Firestore first = await open(app);
    final String path = 'app-delete/$appName';
    await first.doc(path).set(<String, Object?>{'generation': 1});
    expect(databaseFiles(), hasLength(1));

    // delete() is synchronous; the instance is terminated in the background.
    // The new app is created right away, without waiting for anything.
    app.delete();
    final FirebaseApp sameName = newApp();
    final Firestore second = await open(sameName);

    expect(identical(first, second), isFalse);
    // The first connection was closed before the second one was opened, on
    // the same file.
    expect(log, <String>['open', 'close', 'open']);
    expect(databaseFiles(), hasLength(1));

    // The old instance is unusable, the new one has the cache and works.
    await expectLater(first.doc(path).get(), throwsA(predicate(isTerminated)));
    final DocumentSnapshot<Map<String, Object?>> cached =
        await second.doc(path).get(Source.cache);
    expect(cached.data, <String, Object?>{'generation': 1});

    await second.doc(path).set(<String, Object?>{'generation': 2});
    expect((await second.doc(path).get(Source.server)).data,
        <String, Object?>{'generation': 2});
  }, skip: skip);

  test('deleting the app with a listener and a pending write', () async {
    final FirebaseApp app = newApp();
    final Firestore first = await open(app);
    final String path = 'app-delete/$appName-pending';
    await first.doc(path).set(<String, Object?>{'value': 'acknowledged'});

    final List<Object> listenerErrors = <Object>[];
    final StreamSubscription<DocumentSnapshot<Map<String, Object?>>>
        subscription =
        first.doc(path).snapshots.listen((_) {}, onError: listenerErrors.add);

    // A write that cannot reach the backend stays in the mutation queue.
    await first.disableNetwork();
    unawaited(first.doc(path).update(
        <String, Object?>{'value': 'pending'}).catchError((Object _) {}));
    await first.doc(path).get(Source.cache);

    app.delete();
    final Firestore second = await open(newApp());
    expect(log, <String>['open', 'close', 'open']);

    // The pending write was persisted and is sent by the new instance.
    final DocumentSnapshot<Map<String, Object?>> local =
        await second.doc(path).get(Source.cache);
    expect(local.data, <String, Object?>{'value': 'pending'});
    await second.waitForPendingWrites();
    expect((await second.doc(path).get(Source.server)).data,
        <String, Object?>{'value': 'pending'});

    await subscription.cancel();
  }, skip: skip);

  test('the cycle can be repeated and the cache cleared at the end', () async {
    final String path = 'app-delete/$appName-cycle';
    FirebaseApp app = newApp();
    Firestore firestore = await open(app);
    for (int generation = 1; generation <= 3; generation++) {
      await firestore
          .doc(path)
          .set(<String, Object?>{'generation': generation});
      app.delete();
      app = newApp();
      firestore = await open(app);
      expect((await firestore.doc(path).get(Source.cache)).data,
          <String, Object?>{'generation': generation});
    }
    expect(log, <String>[
      'open', 'close', 'open', 'close', 'open', 'close', 'open' //
    ]);

    // The file can be deleted once the last instance is terminated: nothing
    // holds it open.
    await firestore.terminate();
    await firestore.clearPersistence();
    expect(log.last, 'close');
    expect(databaseFiles(), isEmpty);
  }, skip: skip);
}
