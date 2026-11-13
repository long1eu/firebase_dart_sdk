// The version in X-Client-Version is the version of the package.

@TestOn('vm')
library;

import 'dart:io';

import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:test/test.dart';

void main() {
  test('X-Client-Version names the version of the pubspec', () {
    final RegExpMatch? version = RegExp(
      r'^version: (\S+)$',
      multiLine: true,
    ).firstMatch(File('pubspec.yaml').readAsStringSync());
    expect(version, isNotNull);
    expect(
      FirebaseUserAuth.clientVersion,
      'Dart/DartCore/${version!.group(1)}/FirebaseCore-dart',
    );
  });
}
