// An app deleted and created again under the same name, on the Dart core of
// this package (the core of Linux), which deletes the firebase_app_dart app
// with the FlutterFire app. One core per file: firebase_core keeps the core
// it reads first.

import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:firebase_database_dart_platform/src/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';
import 'recreated_app_other_options_cases.dart';

void main() {
  registerForTests();

  test('the Dart core is in place', () {
    expect(FirebasePlatform.instance, isA<LinuxFirebaseCore>());
  });

  defineRecreatedAppTests();
}
