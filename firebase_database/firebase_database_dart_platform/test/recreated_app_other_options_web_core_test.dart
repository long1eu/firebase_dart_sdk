// An app deleted and created again under the same name, on a core like firebase_core_web, which builds a new app object on every
// read and knows nothing of the firebase_app_dart app, so that app survives the
// delete. One core per file: firebase_core keeps the
// core it reads first.

import 'package:firebase_core/firebase_core.dart';
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
    FirebasePlatform.instance = WebLikeCore();
  });
  tearDownAll(() => FirebasePlatform.instance = dartCore);

  test('the web-like core is in place', () {
    expect(FirebasePlatform.instance, isA<WebLikeCore>());
  });

  test('the web-like core gives a new app object on every read', () async {
    await Firebase.initializeApp(name: 'reads', options: options);
    final FirebasePlatform core = FirebasePlatform.instance;
    expect(identical(core.app('reads'), core.app('reads')), isFalse);
    expect(identical(core.apps.single, core.apps.single), isFalse);
    expect(identical(Firebase.app('reads'), Firebase.app('reads')), isFalse);
  });

  defineRecreatedAppTests();
  defineDeleteWindowTests(dartCore: false);
}
