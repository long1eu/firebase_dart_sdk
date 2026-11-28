// Pins the as-built rows A22 and A23 of remote_config.v4-asbuilt.md that no other test pins. In a file of
// its own: `use` can be called once before the first client is created, and this file calls it in A23.

@TestOn('vm')
library;

import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:firebase_remote_config_dart_platform/firebase_remote_config_dart_platform.dart';
import 'package:firebase_remote_config_dart_platform/src/default_store_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'fake_backend.dart';
import 'harness.dart' show options;

/// A path_provider whose first [failures] lookups of the application support directory throw.
class FlakyPathProvider extends PathProviderPlatform {
  FlakyPathProvider(this.supportPath, {required this.failures});

  final String supportPath;
  int failures;

  /// The number of `getApplicationSupportPath` calls.
  int calls = 0;

  @override
  Future<String?> getApplicationSupportPath() async {
    calls++;
    if (failures > 0) {
      failures--;
      throw FileSystemException('the lookup failed (fake)', supportPath);
    }
    return supportPath;
  }
}

void main() {
  group('A22 default store lookup', () {
    late Directory support;

    setUp(() {
      support = Directory.systemTemp.createTempSync('rc_gap_support_');
      addTearDown(() => support.deleteSync(recursive: true));
    });

    test('A22 a failed directory lookup is thrown to the call that waited '
        'for it and retried on the next call', () async {
      final FlakyPathProvider paths = FlakyPathProvider(
        support.path,
        failures: 1,
      );
      PathProviderPlatform.instance = paths;
      final ApplicationSupportStore store = ApplicationSupportStore();
      addTearDown(store.close);

      await expectLater(store.read('k'), throwsA(isA<FileSystemException>()));
      expect(paths.calls, 1);

      await store.write('k', 'v');
      expect(paths.calls, 2, reason: 'the next call looks the directory up');
      expect(await store.read('k'), 'v');
      expect(
        Directory(
          '${support.path}${Platform.pathSeparator}firebase_dart',
        ).existsSync(),
        isTrue,
      );
    });

    test('A22 every failed lookup is retried, not only the first; a lookup '
        'that worked is not repeated', () async {
      final FlakyPathProvider paths = FlakyPathProvider(
        support.path,
        failures: 2,
      );
      PathProviderPlatform.instance = paths;
      final ApplicationSupportStore store = ApplicationSupportStore();
      addTearDown(store.close);

      await expectLater(store.read('k'), throwsA(isA<FileSystemException>()));
      await expectLater(
        store.write('k', 'v'),
        throwsA(isA<FileSystemException>()),
      );
      expect(paths.calls, 2);

      await store.write('k', 'v');
      expect(await store.read('k'), 'v');
      expect(await store.update('k', (String? c) => '${c}2'), 'v2');
      expect(paths.calls, 3, reason: 'looked up once after the failures');
    });

    test('A22 calls made together while the lookup fails all see the '
        'failure, and a call after them retries', () async {
      final FlakyPathProvider paths = FlakyPathProvider(
        support.path,
        failures: 1,
      );
      PathProviderPlatform.instance = paths;
      final ApplicationSupportStore store = ApplicationSupportStore();
      addTearDown(store.close);

      final Future<String?> first = store.read('a');
      final Future<String?> second = store.read('b');
      await expectLater(first, throwsA(isA<FileSystemException>()));
      await expectLater(second, throwsA(isA<FileSystemException>()));
      expect(paths.calls, 1, reason: 'one lookup served both waiting calls');

      expect(await store.read('a'), isNull);
      expect(paths.calls, 2);
    });

    test('A22 after close every call throws a StateError and no lookup is '
        'made again', () async {
      final FlakyPathProvider paths = FlakyPathProvider(
        support.path,
        failures: 1,
      );
      PathProviderPlatform.instance = paths;
      final ApplicationSupportStore store = ApplicationSupportStore();
      await expectLater(store.read('k'), throwsA(isA<FileSystemException>()));

      await store.close();

      await expectLater(store.read('k'), throwsStateError);
      expect(paths.calls, 1);
    });
  });

  group('A23 use(httpClient:)', () {
    test('A23 the client passed to use serves the Installations requests and '
        'the Remote Config fetch', () async {
      final Directory support = Directory.systemTemp.createTempSync(
        'rc_gap_support_',
      );
      addTearDown(() => support.deleteSync(recursive: true));
      PathProviderPlatform.instance = FlakyPathProvider(
        support.path,
        failures: 0,
      );
      final FakeBackend backend = FakeBackend()
        ..entries = <String, String>{'greeting': 'hello'};
      FirebaseRemoteConfigDart.use(
        store: MemoryKeyValueStore(),
        httpClient: backend.client,
        languageCode: 'en-US',
        useDartCore: true,
      );

      final FirebaseApp app = await Firebase.initializeApp(
        name: 'gap-a23',
        options: options,
      );
      final FirebaseRemoteConfig remoteConfig =
          FirebaseRemoteConfig.instanceFor(app: app);

      expect(await remoteConfig.fetchAndActivate(), isTrue);

      expect(remoteConfig.getString('greeting'), 'hello');
      expect(
        backend.to(installationsHost),
        isNotEmpty,
        reason: 'the Installations create request went through the client',
      );
      expect(
        backend.fetches,
        isNotEmpty,
        reason: 'the fetch went through the client',
      );
      expect(
        backend.requests.map((RecordedRequest r) => r.host).toSet(),
        <String>{installationsHost, fetchHost},
      );
      expect(
        Directory(
          '${support.path}${Platform.pathSeparator}firebase_dart',
        ).existsSync(),
        isFalse,
        reason: 'use(store:) replaced the default store',
      );
    });
  });
}
