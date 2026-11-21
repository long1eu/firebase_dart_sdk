// The default storage before any binding exists (an app that uses Firebase
// before WidgetsFlutterBinding.ensureInitialized()): no plugin can be called,
// so the secure store counts as unavailable. Its own file, because the other
// tests need a binding and a binding cannot be removed.

import 'package:firebase_auth_dart_platform/src/secure_default_storage.dart';
import 'package:firebase_auth_dart_platform/src/storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'without a binding the sessions go to the fallback, with one line',
    () async {
      final List<String> printed = <String>[];
      final DebugPrintCallback saved = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) =>
          printed.add('$message');
      addTearDown(() => debugPrint = saved);

      final SecureDefaultStorage storage = secureDefaultStorage(null);
      expect(await storage.read('key'), isNull);
      await storage.write('key', 'session');
      expect(await storage.read('key'), 'session');
      expect(storage.usesFallback, isTrue);
      expect(
        printed.single,
        contains('WidgetsFlutterBinding.ensureInitialized()'),
      );
      expect(printed.single, contains('in memory until the program ends'));
    },
  );
}
