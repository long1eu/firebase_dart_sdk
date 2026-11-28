import 'dart:io';

import 'package:firebase_analytics_dart/src/version.dart';
import 'package:test/test.dart';

void main() {
  test('packageVersion is the version of pubspec.yaml', () {
    final String pubspec = File('pubspec.yaml').readAsStringSync();
    final String version = RegExp(
      r'^version: (\S+)$',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1)!;
    expect(packageVersion, version);
  });
}
