// WebAuthStorage in a browser (sessionStorage and localStorage), the device language from navigator, and that
// FileAuthStorage is refused there.
//
//     dart test -p chrome test/browser                  # dart2js
//     dart test -p chrome -c dart2wasm test/browser     # dart2wasm

@TestOn('browser')
library;

import 'dart:js_interop';

import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

void main() {
  tearDown(() {
    web.window.sessionStorage.clear();
    web.window.localStorage.clear();
  });

  for (final (
        String name,
        WebAuthStorage Function({String prefix}) create,
        web.Storage Function() storage,
      )
      in <
        (
          String,
          WebAuthStorage Function({String prefix}),
          web.Storage Function(),
        )
      >[
        (
          'session',
          ({String prefix = ''}) => WebAuthStorage.session(prefix: prefix),
          () => web.window.sessionStorage,
        ),
        (
          'local',
          ({String prefix = ''}) => WebAuthStorage.local(prefix: prefix),
          () => web.window.localStorage,
        ),
      ]) {
    test('$name: stores, reads and removes, under the prefix', () {
      final WebAuthStorage auth = create(prefix: 'app:');
      expect(auth.read('k'), isNull);
      auth.write('k', 'v');
      expect(auth.read('k'), 'v');
      expect(storage().getItem('app:k'), 'v');
      expect(create(prefix: 'app:').read('k'), 'v');
      expect(create().read('k'), isNull);
      auth.write('k', null);
      expect(storage().getItem('app:k'), isNull);
    });
  }

  test('a FirebaseUserAuth keeps its session in sessionStorage', () async {
    final InMemoryAuthStorage unused = InMemoryAuthStorage();
    expect(unused.read('x'), isNull);
    final WebAuthStorage storage = WebAuthStorage.session();
    final FirebaseUserAuth auth = FirebaseUserAuth(
      apiKey: 'key',
      storage: storage,
    );
    await auth.restore();
    expect(auth.currentUser, isNull);
    storage.write(
      'firebase_auth_providers_dart:key',
      '{"version":2,"uid":"u1","refreshToken":"r"}',
    );
    await auth.restore();
    expect(auth.uid, 'u1');
    await auth.signOut();
    expect(storage.read('firebase_auth_providers_dart:key'), isNull);
    await auth.dispose();
  });

  test('the device language is the browser language', () {
    final FirebaseUserAuth auth = FirebaseUserAuth(apiKey: 'key');
    auth.useDeviceLanguage();
    final List<JSString> languages = web.window.navigator.languages.toDart;
    final String expected = languages.isNotEmpty
        ? languages.first.toDart
        : web.window.navigator.language;
    expect(auth.languageCode, expected);
    expect(auth.languageCode, isNotEmpty);
  });

  test('FileAuthStorage needs dart:io', () {
    expect(() => FileAuthStorage('x'), throwsUnsupportedError);
  });
}
