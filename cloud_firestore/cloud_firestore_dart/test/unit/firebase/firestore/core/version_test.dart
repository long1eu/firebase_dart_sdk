// The versions sent in the `x-goog-api-client` header must follow the
// package: Dart has no way to read pubspec.yaml at run time, so the constants
// are written by hand and this test fails when they are forgotten. Tests run
// in the package root.

import 'dart:io';

import 'package:cloud_firestore_dart/src/firebase/firestore/core/version.dart';
import 'package:test/test.dart';

void main() {
  test('Version.sdkVersion is the version of pubspec.yaml', () {
    final RegExpMatch? match = RegExp(
      r'^version:\s*(\S+)\s*$',
      multiLine: true,
    ).firstMatch(File('pubspec.yaml').readAsStringSync());
    expect(match, isNotNull, reason: 'pubspec.yaml has no version');
    expect(Version.sdkVersion, match!.group(1));
  });

  test('Version.grpcVersion is the grpc version of pubspec.lock', () {
    final RegExpMatch? match = RegExp(
      r'^  grpc:\n(?:    .*\n)*?    version: "([^"]+)"',
      multiLine: true,
    ).firstMatch(File('pubspec.lock').readAsStringSync());
    expect(match, isNotNull, reason: 'pubspec.lock has no grpc entry');
    expect(Version.grpcVersion, match!.group(1));
  });
}
