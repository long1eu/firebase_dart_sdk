import 'dart:convert';

import 'package:firebase_core_vm/firebase_core_vm.dart';
import 'package:test/test.dart';

void main() {
  tearDown(FirebaseApp.clearInstancesForTest);

  group('FirebaseOptions', () {
    test('== agrees with hashCode, including dataCollectionEnabled', () {
      const FirebaseOptions a =
          FirebaseOptions(apiKey: 'k', applicationId: 'a');
      const FirebaseOptions b = FirebaseOptions(
          apiKey: 'k', applicationId: 'a', dataCollectionEnabled: false);
      const FirebaseOptions c =
          FirebaseOptions(apiKey: 'k', applicationId: 'a');
      expect(a == c, isTrue);
      expect(a.hashCode, c.hashCode);
      expect(a == b, isFalse);
    });

    test('fromJson accepts a decoded JSON map', () {
      const FirebaseOptions options = FirebaseOptions(
          apiKey: 'k', applicationId: 'a', projectId: 'p', storageBucket: 's');
      final Map<String, dynamic> decoded =
          jsonDecode(jsonEncode(options.toJson())) as Map<String, dynamic>;
      expect(FirebaseOptions.fromJson(decoded), options);
    });

    test('fromJson requires api key and app id', () {
      expect(() => FirebaseOptions.fromJson(<String, dynamic>{}),
          throwsArgumentError);
    });
  });

  group('FirebaseApp defaults', () {
    test('background and network subjects are stable', () {
      final FirebaseApp app = FirebaseApp.withOptions(
          const FirebaseOptions(apiKey: 'k', applicationId: 'a'));
      expect(
          identical(app.onBackgroundChanged, app.onBackgroundChanged), isTrue);
      expect(identical(app.onNetworkConnected, app.onNetworkConnected), isTrue);
      app.setAutomaticResourceManagementEnabled(enabled: true);
      app.onBackgroundChanged.add(true);
      expect(app.onBackgroundChanged.value, isTrue);
    });

    test('persistence key is URL safe', () {
      final String key =
          FirebaseApp.getPersistenceKeyFor('[DEFAULT]', '>>>???');
      expect(key, isNot(contains('/')));
      expect(key, isNot(contains('=')));
      expect(key.split('+').first, isNot(contains('+')));
    });
  });
}
