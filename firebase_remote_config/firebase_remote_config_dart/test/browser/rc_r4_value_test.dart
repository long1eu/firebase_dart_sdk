@TestOn('browser')
@Tags(<String>['browser'])
library;

import 'package:firebase_remote_config_dart/firebase_remote_config_dart.dart';
import 'package:test/test.dart';

/// [text] as a remote value.
RemoteConfigValue _remote(String text) =>
    RemoteConfigValue(text, ValueSource.valueRemote);

void main() {
  // A28: web detection uses dart.library.js_interop, so dart2wasm (64-bit ints) answers like dart2js.
  group('5.11 / A28 asInt on the web (dart2js and dart2wasm)', () {
    test('A28 "9007199254740992".asInt() is null', () {
      expect(_remote('9007199254740992').asInt(), isNull);
    });

    test('A28 "-9007199254740992".asInt() is null', () {
      expect(_remote('-9007199254740992').asInt(), isNull);
    });

    test('A28 "9007199254740991".asInt() is 9007199254740991', () {
      expect(_remote('9007199254740991').asInt(), 9007199254740991);
    });

    test('A28 "-9007199254740991".asInt() is -9007199254740991', () {
      expect(_remote('-9007199254740991').asInt(), -9007199254740991);
    });
  });
}
