@TestOn('vm')
library;

import 'dart:io';

import 'package:firebase_transport_dart/firebase_transport_dart.dart';
import 'package:test/test.dart';

void main() {
  test(
    'a variable set in the process environment is returned, with no outer blanks',
    () {
      final String? raw = Platform.environment['PATH'];
      expect(raw, isNotNull, reason: 'the test process has no PATH');
      final String? value = environmentVariable('PATH');
      expect(value, raw!.trim());
      expect(value, isNotEmpty);
      expect(value, isNot(matches(r'^\s|\s$')));
    },
  );

  test('a name that is not set gives null', () {
    const String name = 'FIREBASE_TRANSPORT_DART_TEST_SURELY_UNSET_VARIABLE';
    expect(Platform.environment.containsKey(name), isFalse);
    expect(environmentVariable(name), isNull);
  });
}
