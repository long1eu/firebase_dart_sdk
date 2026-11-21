// Cross-tab sync in a browser: two FirebaseUserAuth instances on one IndexedDB database (two
// storage objects, as two tabs would have) or on localStorage (with the `storage` event another
// tab would send), against a fake backend. Sign-out, another user, a rotated refresh token, no
// write back, the life of the polls, and the fallback marker of BestWebAuthStorage. No emulator.
//
//     dart test -p chrome test/browser/cross_tab_sync_test.dart               # dart2js
//     dart test -p chrome -c dart2wasm test/browser/cross_tab_sync_test.dart  # dart2wasm

@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

import '../fakes.dart';
import '../harness.dart';

const String _key = 'firebase_auth_providers_dart:$apiKey';
const Duration _poll = Duration(milliseconds: 40);

int _databases = 0;
final List<String> _used = <String>[];

String _newDatabase() {
  final String name =
      'cross_tab_test_${DateTime.now().microsecondsSinceEpoch}_${_databases++}';
  _used.add(name);
  return name;
}

Future<void> _deleteDatabase(String name) {
  final Completer<void> done = Completer<void>();
  final web.IDBOpenDBRequest request = web.window.indexedDB.deleteDatabase(
    name,
  );
  request.onsuccess = ((web.Event _) => done.complete()).toJS;
  request.onerror = ((web.Event _) => done.completeError(
    StateError('deleteDatabase($name) failed'),
  )).toJS;
  return done.future;
}

/// An IndexedDB storage that counts its writes.
class _CountingIndexedDb extends IndexedDbAuthStorage {
  _CountingIndexedDb(String databaseName)
    : super(databaseName: databaseName, pollInterval: _poll);

  int writes = 0;

  @override
  Future<void> write(String key, String? value) {
    writes++;
    return super.write(key, value);
  }
}

/// A localStorage storage that counts its writes.
class _CountingLocal extends WebAuthStorage {
  _CountingLocal() : super.local(prefix: 'xtab:');

  int writes = 0;

  @override
  void write(String key, String? value) {
    writes++;
    super.write(key, value);
  }
}

/// Waits until [condition] holds, polling every few milliseconds, for at most two seconds.
Future<void> _until(bool Function() condition, String what) async {
  final DateTime end = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(end)) {
      fail('timed out waiting for $what');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// Lets several polls run.
Future<void> _severalPolls() => Future<void>.delayed(_poll * 5);

/// Sends the `storage` event another tab's change of [fullKey] in localStorage would send here.
void _storageEventFromAnotherTab(String? fullKey, {web.Storage? area}) {
  web.window.dispatchEvent(
    web.StorageEvent(
      'storage',
      web.StorageEventInit(
        key: fullKey,
        storageArea: area ?? web.window.localStorage,
      ),
    ),
  );
}

void main() {
  late FakeBackend backend;
  final List<FirebaseUserAuth> clients = <FirebaseUserAuth>[];
  final List<IndexedDbAuthStorage> storages = <IndexedDbAuthStorage>[];

  FirebaseUserAuth client(AuthStorage storage) {
    final FirebaseUserAuth auth = backend.create(storage: storage);
    clients.add(auth);
    return auth;
  }

  _CountingIndexedDb indexedDb(String name) {
    final _CountingIndexedDb storage = _CountingIndexedDb(name);
    storages.add(storage);
    return storage;
  }

  setUp(() => backend = FakeBackend());

  tearDown(() async {
    for (final FirebaseUserAuth auth in clients) {
      await auth.dispose();
    }
    clients.clear();
    for (final IndexedDbAuthStorage storage in storages) {
      await storage.close();
    }
    storages.clear();
    for (final String name in _used) {
      await _deleteDatabase(name);
    }
    _used.clear();
    web.window.localStorage.clear();
  });

  group('IndexedDB', () {
    late _CountingIndexedDb storageA;
    late _CountingIndexedDb storageB;
    late FirebaseUserAuth tabA;
    late FirebaseUserAuth tabB;

    setUp(() async {
      final String name = _newDatabase();
      storageA = indexedDb(name);
      storageB = indexedDb(name);
      tabA = client(storageA);
      tabB = client(storageB);
      await tabA.restore();
      await tabB.restore();
    });

    Future<void> signInBoth(String email) async {
      await tabA.signInWithEmailAndPassword(email: email, password: 'pw');
      await _until(() => tabB.uid == 'uid-of-$email', 'tab B to take over');
    }

    test(
      'a sign-out in one tab signs the other out, without a write',
      () async {
        await signInBoth('a@x.com');
        final List<AuthUser?> states = <AuthUser?>[];
        tabB.authStateChanges().skip(1).listen(states.add);
        final int writes = storageB.writes;

        await tabA.signOut();
        await _until(() => tabB.currentUser == null, 'tab B to sign out');

        expect(states, <AuthUser?>[null]);
        expect(storageB.writes, writes);
        await _severalPolls();
        expect(await storageA.read(_key), isNull);
        expect(tabA.currentUser, isNull);
      },
    );

    test('a sign-in of another user switches the other tab', () async {
      await signInBoth('a@x.com');
      final List<String?> states = <String?>[];
      tabB
          .authStateChanges()
          .skip(1)
          .listen((AuthUser? u) => states.add(u?.uid));

      await tabA.signInWithEmailAndPassword(email: 'b@x.com', password: 'pw');
      await _until(() => tabB.uid == 'uid-of-b@x.com', 'tab B to switch');

      expect(states, <String?>['uid-of-b@x.com']);
      expect(tabB.refreshToken, 'refresh:uid-of-b@x.com');
      expect(storageB.writes, 0);
    });

    test('a rotated refresh token reaches the other tab', () async {
      await signInBoth('a@x.com');
      backend.on(
        'token',
        (Map<String, Object?> body) => jsonResponse(<String, Object?>{
          'id_token': idToken(
            'uid-of-a@x.com',
            expires: backend.clock.now.add(const Duration(hours: 1)),
            tag: 'rotation',
          ),
          'refresh_token': 'refresh:uid-of-a@x.com:rotated',
          'expires_in': '3600',
        }),
      );

      await tabA.getAccessToken(forceRefresh: true);
      await _until(
        () => tabB.refreshToken == 'refresh:uid-of-a@x.com:rotated',
        'tab B to take the new refresh token',
      );

      expect(tabB.uid, 'uid-of-a@x.com');
      expect(storageB.writes, 0);
    });

    test('nothing is written back and forth', () async {
      await signInBoth('a@x.com');
      await tabA.signOut();
      await _until(() => tabB.currentUser == null, 'tab B to sign out');
      await tabA.signInAnonymously();
      await _until(() => tabB.uid == 'anon-user', 'tab B to sign in');
      final int writesA = storageA.writes;

      await _severalPolls();

      expect(storageB.writes, 0);
      expect(storageA.writes, writesA);
      expect(writesA, 3);
      expect(tabA.uid, 'anon-user');
    });

    test('the polls stop at dispose and at close', () async {
      expect(storageA.isPolling, isTrue);
      await tabA.dispose();
      expect(storageA.isPolling, isFalse);
      final int polls = storageA.pollCount;
      await _severalPolls();
      expect(storageA.pollCount, polls);

      expect(storageB.isPolling, isTrue);
      await storageB.close();
      expect(storageB.isPolling, isFalse);
      final int pollsB = storageB.pollCount;
      await _severalPolls();
      expect(storageB.pollCount, pollsB);
    });
  });

  group('IndexedDbAuthStorage.changes', () {
    test('no poll without a listener', () async {
      final _CountingIndexedDb storage = indexedDb(_newDatabase());
      await storage.write('k', 'v');
      await _severalPolls();
      expect(storage.pollCount, 0);
      expect(storage.isPolling, isFalse);
    });

    test(
      'polls while listened to, and stops when the last listener goes',
      () async {
        final String name = _newDatabase();
        final _CountingIndexedDb storage = indexedDb(name);
        final _CountingIndexedDb other = indexedDb(name);
        int events = 0;
        final StreamSubscription<void> first = storage
            .changes('k')
            .listen((_) => events++);
        final StreamSubscription<void> second = storage
            .changes('k')
            .listen((_) {});
        await storage.read('k');

        await other.write('k', 'v1');
        await _until(() => events == 1, 'the change of the other object');
        // The writes of the object itself never emit.
        await storage.write('k', 'v2');
        await _severalPolls();
        expect(events, 1);

        await first.cancel();
        expect(storage.isPolling, isTrue);
        await second.cancel();
        expect(storage.isPolling, isFalse);
        final int polls = storage.pollCount;
        await _severalPolls();
        expect(storage.pollCount, polls);
      },
    );

    test('close ends the streams; a new listener polls again', () async {
      final _CountingIndexedDb storage = indexedDb(_newDatabase());
      final Completer<void> done = Completer<void>();
      storage.changes('k').listen((_) {}, onDone: done.complete);
      await storage.close();
      await done.future;
      expect(storage.isPolling, isFalse);
      final StreamSubscription<void> again = storage
          .changes('k')
          .listen((_) {});
      expect(storage.isPolling, isTrue);
      await again.cancel();
    });

    test('a poll interval that is not positive is refused', () {
      expect(
        () => IndexedDbAuthStorage(pollInterval: Duration.zero),
        throwsArgumentError,
      );
    });
  });

  group('BestWebAuthStorage', () {
    test('close stops the polls of its IndexedDB storage', () async {
      final _CountingIndexedDb inner = indexedDb(_newDatabase());
      final BestWebAuthStorage best = BestWebAuthStorage.forTesting(
        indexedDb: inner,
        indexedDbAvailable: () async => true,
      );
      final FirebaseUserAuth auth = client(best);
      await auth.restore();
      await _until(() => inner.isPolling, 'the polls to start');
      await best.close();
      expect(inner.isPolling, isFalse);
    });

    // A tab without IndexedDB marks the key in localStorage and deletes it from IndexedDB. The tab
    // on IndexedDB hears the deletion; its read goes through the marker, so the state it takes is
    // the one in localStorage, not "deleted".
    for (final (String what, String? written, String? expectedUid)
        in <(String, String?, String?)>[
          ('a sign-out', null, null),
          ('a sign-in', '{"version":2,"uid":"u2","refreshToken":"r2"}', 'u2'),
        ]) {
      test(
        '$what in a tab without IndexedDB is followed through the marker',
        () async {
          final String name = _newDatabase();
          final BestWebAuthStorage withIndexedDb =
              BestWebAuthStorage.forTesting(
                indexedDb: indexedDb(name),
                indexedDbAvailable: () async => true,
              );
          final FirebaseUserAuth tabB = client(withIndexedDb);
          await tabB.restore();
          await tabB.signInAnonymously();
          expect(await withIndexedDb.kind, WebAuthStorageKind.indexedDb);

          final BestWebAuthStorage fallback = BestWebAuthStorage.forTesting(
            databaseName: name,
            indexedDbAvailable: () async => false,
          );
          await fallback.write(_key, written);
          // Waits for its deletion in IndexedDB.
          await fallback.close();

          await _until(() => tabB.uid == expectedUid, 'tab B to follow $what');
          await _severalPolls();
          expect(tabB.uid, expectedUid);
          // The marked state moved to IndexedDB; neither the copy nor the marker stays.
          expect(await indexedDb(name).read(_key), written);
          expect(web.window.localStorage.length, 0);
        },
      );
    }
  });

  group('localStorage', () {
    late _CountingLocal storage;
    late FirebaseUserAuth tab;

    setUp(() async {
      storage = _CountingLocal();
      tab = client(storage);
      await tab.restore();
    });

    test('a sign-out in another tab signs out here, without a write', () async {
      await tab.signInAnonymously();
      final int writes = storage.writes;
      final List<AuthUser?> states = <AuthUser?>[];
      tab.authStateChanges().skip(1).listen(states.add);

      web.window.localStorage.removeItem('xtab:$_key');
      _storageEventFromAnotherTab('xtab:$_key');
      await _until(() => tab.currentUser == null, 'the sign-out');

      expect(states, <AuthUser?>[null]);
      expect(storage.writes, writes);
      expect(web.window.localStorage.getItem('xtab:$_key'), isNull);
    });

    test('another user signed in there becomes the user here', () async {
      await tab.signInAnonymously();
      final int writes = storage.writes;

      web.window.localStorage.setItem(
        'xtab:$_key',
        '{"version":2,"uid":"u2","refreshToken":"refresh:u2"}',
      );
      _storageEventFromAnotherTab('xtab:$_key');
      await _until(() => tab.uid == 'u2', 'the switch');

      expect(storage.writes, writes);
    });

    test('a clear of the storage in another tab signs out here', () async {
      await tab.signInAnonymously();
      web.window.localStorage.clear();
      _storageEventFromAnotherTab(null);
      await _until(() => tab.currentUser == null, 'the sign-out');
    });

    test('events of another key or of sessionStorage are ignored', () async {
      await tab.signInAnonymously();
      web.window.localStorage.removeItem('xtab:$_key');
      _storageEventFromAnotherTab('xtab:other');
      _storageEventFromAnotherTab(
        'xtab:$_key',
        area: web.window.sessionStorage,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(tab.uid, 'anon-user');
    });

    test('the listener is removed when the stream is cancelled', () async {
      final WebAuthStorage local = WebAuthStorage.local();
      int events = 0;
      final StreamSubscription<void> subscription = local
          .changes('k')
          .listen((_) => events++);
      _storageEventFromAnotherTab('k');
      await _until(() => events == 1, 'the event');
      await subscription.cancel();
      _storageEventFromAnotherTab('k');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(events, 1);
    });
  });
}
