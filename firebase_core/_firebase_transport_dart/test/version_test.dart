@TestOn('vm')
library;

import 'dart:io';

import 'package:_firebase_transport_dart/src/version.dart';
import 'package:test/test.dart';

void main() {
  test('packageVersion equals the version in pubspec.yaml', () {
    final String pubspec = File('pubspec.yaml').readAsStringSync();
    final RegExpMatch? match = RegExp(
      r'^version:\s*(\S+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(match, isNotNull, reason: 'pubspec.yaml has no version line');
    expect(packageVersion, match!.group(1));
  });
}
