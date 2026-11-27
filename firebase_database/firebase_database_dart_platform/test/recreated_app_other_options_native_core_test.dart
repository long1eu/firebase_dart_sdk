// An app deleted and created again under the same name, on a core like MethodChannelFirebase (macOS, Windows, Android, iOS), which
// knows nothing of the firebase_app_dart app, so that app survives the delete. One core per file: firebase_core keeps the
// core it reads first.

import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';
import 'recreated_app_delete_window_cases.dart';
import 'recreated_app_invariant.dart';
import 'recreated_app_other_options_cases.dart';
import 'recreated_app_pinned_support.dart';

void main() {
  registerForTests();
  checkClientsAfterEveryTest();

  late FirebasePlatform dartCore;
  setUpAll(() {
    dartCore = FirebasePlatform.instance;
    FirebasePlatform.instance = NativeLikeCore();
  });
  tearDownAll(() => FirebasePlatform.instance = dartCore);

  test('the native-like core is in place', () {
    expect(FirebasePlatform.instance, isA<NativeLikeCore>());
  });

  defineRecreatedAppTests();
  defineDeleteWindowTests(dartCore: false);
}
