// File created by
// Lung Razvan <long1eu>
// on 17/09/2018
import 'dart:io';

import 'package:firebase_common/src/auth/get_token_result.dart';
import 'package:firebase_common/src/errors/firebase_api_not_available_error.dart';
import 'package:firebase_common/src/firebase_app.dart';
import 'package:firebase_common/src/firebase_options.dart';
import 'package:firebase_common/src/util/prefs.dart';
import 'package:test/test.dart';

import 'mock/internal_token_provider_mock.dart';
import 'mock/lifecycle_handler_mock.dart';

void main() {
  File file;
  FirebaseApp firebaseApp;

  setUp(() {
    file =
        File('${Directory.current.path}/${FirebaseApp.firebaseAppPrefs}.json');

    file.writeAsStringSync('{}');

    firebaseApp = FirebaseApp.withOptions(
      FirebaseOptions(applicationId: 'id', apiKey: ''),
      (_) {},
      Prefs(file),
      FirebaseApp.defaultAppName,
      LifecycleHandlerMock.instance,
    );
  });

  tearDown(() {
    file.deleteSync();
    FirebaseApp.clearInstancesForTest();
  });

  test('getToken_whenNoProviderIsSet_shouldThrow', () {
    expect(firebaseApp.getToken(true),
        throwsA(const TypeMatcher<FirebaseApiNotAvailableError>()));
  });

  test('getUid_whenNoProviderIsSet_shouldThrow', () {
    expect(() => firebaseApp.uid,
        throwsA(const TypeMatcher<FirebaseApiNotAvailableError>()));
  });

  test('getToken_whenProviderIsSet_shouldDelegateToIt', () async {
    firebaseApp.tokenProvider = InternalTokenProviderMock.instance;
    final GetTokenResult result = await firebaseApp.getToken(true);
    expect(result, InternalTokenProviderMock.accessTokenResult);
  });

  test('getUid_whenProviderIsSet_shouldDelegateToIt', () async {
    firebaseApp.tokenProvider = InternalTokenProviderMock.instance;
    expect(firebaseApp.uid, InternalTokenProviderMock.uidResult);
  });
}
