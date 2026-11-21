// The choice of storage on the web, with fakes on the VM: the default storage, and where setPersistence puts the
// session on the web and elsewhere.

import 'package:firebase_auth_dart_platform/src/secure_default_storage.dart';
import 'package:firebase_auth_dart_platform/src/storage.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart'
    show Persistence;
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart'
    show AuthStorage, InMemoryAuthStorage;
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

    AuthStorage mapped(
      Persistence persistence, {
      required bool web,
      void Function()? onSession,
    }) => storageForPersistence(
      persistence,
      web: web,
      persistent: persistent,
      memory: memory,
      session: () {
        onSession?.call();
        return session;
      },
    );

    test('on the web', () {
      expect(mapped(Persistence.LOCAL, web: true), same(persistent));
      expect(mapped(Persistence.INDEXED_DB, web: true), same(persistent));
      expect(mapped(Persistence.SESSION, web: true), same(session));
      expect(mapped(Persistence.NONE, web: true), same(memory));
    });

    test('elsewhere, as before: SESSION is memory', () {
      int sessions = 0;
      void count() => sessions++;
      expect(
        mapped(Persistence.LOCAL, web: false, onSession: count),
        same(persistent),
      );
      expect(
        mapped(Persistence.INDEXED_DB, web: false, onSession: count),
        same(persistent),
      );
      expect(
        mapped(Persistence.SESSION, web: false, onSession: count),
        same(memory),
      );
      expect(
        mapped(Persistence.NONE, web: false, onSession: count),
        same(memory),
      );
      // sessionStorage is never touched outside a browser.
      expect(sessions, 0);
    });
  });
}
