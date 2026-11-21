// The choice of storage on the web, with fakes on the VM: the default storage, where
// setPersistence puts the session on the web and elsewhere, the storage a reloaded tab starts
// on after SESSION, and the changes of other tabs passed through FallbackStorage.

import 'dart:async';

import 'package:firebase_auth_dart_platform/src/secure_default_storage.dart';
import 'package:firebase_auth_dart_platform/src/storage.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart'
    show Persistence;
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart'
    show
        AuthStorage,
        FirebaseUserAuth,
        InMemoryAuthStorage,
        ObservableAuthStorage;
import 'package:flutter_test/flutter_test.dart';

/// A storage that only has a name, to tell the fakes apart.
class _Named extends InMemoryAuthStorage {
  _Named(this.name);

  final String name;

  @override
  String toString() => name;
}

void main() {
  group('defaultStorageFor', () {
    test('on the web: the web storage, not memory', () {
      final _Named web = _Named('best web');
      expect(defaultStorageFor(web: true, webStorage: () => web), same(web));
    });

    test('elsewhere: the secure default; the web storage is not made', () {
      int made = 0;
      final AuthStorage storage = defaultStorageFor(
        web: false,
        webStorage: () {
          made++;
          return _Named('best web');
        },
      );
      expect(storage, isA<SecureDefaultStorage>());
      expect(made, 0);
    });
  });

  group('storageForPersistence', () {
    final _Named persistent = _Named('persistent');
    final _Named memory = _Named('memory');
    final _Named session = _Named('session');

    AuthStorage mapped(Persistence persistence, {AuthStorage? session}) =>
        storageForPersistence(
          persistence,
          persistent: persistent,
          memory: memory,
          session: session,
        );

    test('with a sessionStorage (the web, no storageFor)', () {
      expect(mapped(Persistence.LOCAL, session: session), same(persistent));
      expect(
        mapped(Persistence.INDEXED_DB, session: session),
        same(persistent),
      );
      expect(mapped(Persistence.SESSION, session: session), same(session));
      expect(mapped(Persistence.NONE, session: session), same(memory));
    });

    test('without one (elsewhere, or storageFor): SESSION is memory', () {
      expect(mapped(Persistence.LOCAL), same(persistent));
      expect(mapped(Persistence.INDEXED_DB), same(persistent));
      expect(mapped(Persistence.SESSION), same(memory));
      expect(mapped(Persistence.NONE), same(memory));
    });
  });

  group('sessionStorageFor', () {
    test('on the web without storageFor: the tab storage', () async {
      final _Named tab = _Named('tab');
      final AuthStorage? session = sessionStorageFor(
        web: true,
        customStorage: false,
        sessionStorage: () => tab,
      );
      expect(session, isA<FallbackStorage>());
      await session!.write('k', 'v');
      expect(tab.read('k'), 'v');
    });

    test('elsewhere, or with storageFor: none, and nothing is made', () {
      int made = 0;
      AuthStorage tab() {
        made++;
        return _Named('tab');
      }

      expect(
        sessionStorageFor(
          web: false,
          customStorage: false,
          sessionStorage: tab,
        ),
        isNull,
      );
      expect(
        sessionStorageFor(web: true, customStorage: true, sessionStorage: tab),
        isNull,
      );
      expect(
        sessionStorageFor(web: false, customStorage: true, sessionStorage: tab),
        isNull,
      );
      expect(made, 0);
    });
  });

  group('FallbackStorage.changes', () {
    const String key = 'firebase_auth_providers_dart:key:[DEFAULT]';

    test('passes on the changes of a storage that reports them', () async {
      final _Observable app = _Observable();
      final List<void> events = <void>[];
      final ObservableAuthStorage storage =
          FallbackStorage(app) as ObservableAuthStorage;
      final StreamSubscription<void> subscription = storage
          .changes(key)
          .listen(events.add);
      app.changed(key, 'v');
      app.changed('other', 'v');
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(1));
      await subscription.cancel();
      expect(app.hasListener, isFalse);
    });

    test(
      'in front of a storage that does not report changes it is not observable',
      () {
        // So the client never reads the store before it stores an update.
        expect(
          FallbackStorage(InMemoryAuthStorage()),
          isNot(isA<ObservableAuthStorage>()),
        );
        expect(FallbackStorage(_Observable()), isA<ObservableAuthStorage>());
      },
    );

    test('once memory is in use, the changes are ignored', () async {
      final _Observable app = _Observable();
      final FallbackStorage storage = FallbackStorage(app);
      final List<void> events = <void>[];
      (storage as ObservableAuthStorage).changes(key).listen(events.add);
      app.writeFails = true;
      await storage.write(key, 'v');
      app.changed(key, 'w');
      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty);
      expect(storage.read(key), 'v');
    });

    test('the client follows a sign-out made in another tab', () async {
      final _Observable app = _Observable();
      app.write(key, '{"version":2,"uid":"u1","refreshToken":"r"}');
      final FirebaseUserAuth auth = FirebaseUserAuth(
        apiKey: 'key',
        storage: FallbackStorage(app),
        storageKey: key,
      );
      addTearDown(auth.dispose);
      await auth.restore();
      expect(auth.uid, 'u1');
      expect(app.hasListener, isTrue);

      app.changed(key, null);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(auth.currentUser, isNull);
    });
  });

  group('initialStorage', () {
    const String key = 'firebase_auth_providers_dart:key:[DEFAULT]';
    const String stored = '{"version":2,"uid":"u1","refreshToken":"r"}';

    test('the tab storage when it holds the session, else the app storage', () {
      final _Named persistent = _Named('persistent');
      final _Named tab = _Named('tab');
      expect(
        initialStorage(persistent: persistent, session: tab, key: key),
        same(persistent),
      );
      tab.write(key, stored);
      expect(
        initialStorage(persistent: persistent, session: tab, key: key),
        same(tab),
      );
      expect(
        initialStorage(persistent: persistent, session: null, key: key),
        same(persistent),
      );
    });

    test('a tab storage that throws or answers later counts as empty', () {
      final _Named persistent = _Named('persistent');
      expect(
        initialStorage(persistent: persistent, session: _Throwing(), key: key),
        same(persistent),
      );
      expect(
        initialStorage(persistent: persistent, session: _Late(), key: key),
        same(persistent),
      );
    });

    // Two loads of one tab: the first moves its session to SESSION, the second (after a reload)
    // restores it, and the usual setPersistence(SESSION) at start leaves it in the tab.
    test('SESSION survives a reload of the tab', () async {
      final InMemoryAuthStorage app = InMemoryAuthStorage();
      final InMemoryAuthStorage tab = InMemoryAuthStorage();
      app.write(key, stored);

      final _Load first = _Load(app, tab, key);
      await first.auth.restore();
      expect(first.auth.uid, 'u1');
      await first.setPersistence(Persistence.SESSION);
      expect(tab.read(key), isNotNull);
      expect(app.read(key), isNull);
      await first.auth.dispose();

      final _Load second = _Load(app, tab, key);
      await second.auth.restore();
      expect(second.auth.uid, 'u1');
      await second.setPersistence(Persistence.SESSION);
      expect(tab.read(key), isNotNull);
      expect(second.auth.uid, 'u1');
      // LOCAL moves it back out of the tab.
      await second.setPersistence(Persistence.LOCAL);
      expect(app.read(key), isNotNull);
      expect(tab.read(key), isNull);
      await second.auth.dispose();
    });
  });
}

/// A storage whose [changed] tells its listeners that another tab changed a key, and whose
/// writes can be made to fail.
class _Observable extends InMemoryAuthStorage implements ObservableAuthStorage {
  final StreamController<String> _changes = StreamController<String>.broadcast(
    sync: true,
  );
  bool writeFails = false;

  bool get hasListener => _changes.hasListener;

  /// Another tab stored [value] under [key].
  void changed(String key, String? value) {
    super.write(key, value);
    _changes.add(key);
  }

  @override
  void write(String key, String? value) {
    if (writeFails) {
      throw Exception('refused');
    }
    super.write(key, value);
  }

  @override
  Stream<void> changes(String key) =>
      _changes.stream.where((String changed) => changed == key);
}

/// One load of a tab on the web without `storageFor`, wired as `DartFirebaseAuth.forApp` and its
/// `setPersistence` wire it: [app] is the storage of the app, [tab] its `sessionStorage`.
class _Load {
  _Load(AuthStorage app, AuthStorage tab, String key)
    : _persistent = FallbackStorage(app),
      _session = sessionStorageFor(
        web: true,
        customStorage: false,
        sessionStorage: () => tab,
      ) {
    auth = FirebaseUserAuth(
      apiKey: 'key',
      storage: initialStorage(
        persistent: _persistent,
        session: _session,
        key: key,
      ),
      storageKey: key,
    );
  }

  final FallbackStorage _persistent;
  final FallbackStorage? _session;
  final InMemoryAuthStorage _memory = InMemoryAuthStorage();
  late final FirebaseUserAuth auth;

  Future<void> setPersistence(Persistence persistence) => auth.setStorage(
    storageForPersistence(
      persistence,
      persistent: _persistent,
      memory: _memory,
      session: _session,
    ),
  );
}

/// A tab storage the browser refuses.
class _Throwing extends InMemoryAuthStorage {
  @override
  String? read(String key) => throw StateError('sessionStorage refused');
}

/// A storage whose read is asynchronous.
class _Late implements AuthStorage {
  @override
  Future<String?> read(String key) async => 'later';

  @override
  Future<void> write(String key, String? value) async {}
}
