// Copyright 2023 Google LLC (ported from the upstream FirebaseFirestoreSettingsTest, 24197b5)
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:test/test.dart';

void main() {
  test('default settings', () {
    final Settings settings = Settings();
    expect(settings.host, 'firestore.googleapis.com');
    expect(settings.sslEnabled, isTrue);
    expect(settings.persistenceEnabled, isTrue);
    expect(settings.cacheSizeBytes, 104857600);
    expect(settings.cacheSettings, isNull);
  });

  test('persistent cache settings customize the legacy getters', () {
    final Settings settings = Settings(
      host: 'a.b.c',
      sslEnabled: false,
      cacheSettings: PersistentCacheSettings(sizeBytes: 2000000),
    );
    expect(settings.host, 'a.b.c');
    expect(settings.sslEnabled, isFalse);
    expect(settings.persistenceEnabled, isTrue);
    expect(settings.cacheSizeBytes, 2000000);
  });

  test('memory cache settings map onto the legacy getters', () {
    final Settings settings = Settings(
      host: 'a.b.c',
      sslEnabled: false,
      cacheSettings: const MemoryCacheSettings(),
    );
    expect(settings.persistenceEnabled, isFalse);
    expect(settings.cacheSizeBytes, Settings.cacheSizeUnlimited);
    expect((settings.cacheSettings! as MemoryCacheSettings).gcSettings,
        const MemoryEagerGcSettings());
  });

  test('copyWith keeps the cache settings and the derived values', () {
    final Settings settings1 = Settings(
      host: 'a.b.c',
      sslEnabled: false,
      cacheSettings: const MemoryCacheSettings(),
    );
    final Settings settings2 = settings1.copyWith(port: 1234);
    expect(settings2.host, 'a.b.c');
    expect(settings2.port, 1234);
    expect(settings2.sslEnabled, isFalse);
    expect(settings2.persistenceEnabled, isFalse);
    expect(settings2.cacheSizeBytes, Settings.cacheSizeUnlimited);
    expect(settings2.cacheSettings, settings1.cacheSettings);
  });

  test('copyWith can replace the cache settings', () {
    final Settings settings = Settings(
      cacheSettings: const MemoryCacheSettings(),
    ).copyWith(cacheSettings: PersistentCacheSettings(sizeBytes: 5000000));
    expect(settings.persistenceEnabled, isTrue);
    expect(settings.cacheSizeBytes, 5000000);
  });

  test('cannot mix the legacy and the new cache config', () {
    expect(
        () => Settings(
              persistenceEnabled: false,
              cacheSettings: const MemoryCacheSettings(),
            ),
        throwsStateError);
    expect(
        () => Settings(
              cacheSizeBytes: 2000000,
              cacheSettings: PersistentCacheSettings(),
            ),
        throwsStateError);
    expect(
        () => Settings(cacheSettings: const MemoryCacheSettings())
            .copyWith(persistenceEnabled: false),
        throwsStateError);
  });

  test('legacy settings keep working', () {
    final Settings settings =
        Settings(persistenceEnabled: false);
    expect(settings.persistenceEnabled, isFalse);
    expect(settings.cacheSettings, isNull);
    final Settings sized = Settings(cacheSizeBytes: 2000000);
    expect(sized.cacheSizeBytes, 2000000);
  });

  test('validates the cache sizes', () {
    expect(() => PersistentCacheSettings(sizeBytes: 100), throwsArgumentError);
    expect(() => MemoryLruGcSettings(sizeBytes: 100), throwsArgumentError);
    expect(
        PersistentCacheSettings(sizeBytes: Settings.cacheSizeUnlimited)
            .sizeBytes,
        -1);
    expect(MemoryLruGcSettings().sizeBytes,
        Settings.defaultCacheSizeBytes);
  });

  test('cache settings have value semantics', () {
    expect(PersistentCacheSettings(sizeBytes: 2000000),
        PersistentCacheSettings(sizeBytes: 2000000));
    expect(PersistentCacheSettings(sizeBytes: 2000000),
        isNot(PersistentCacheSettings(sizeBytes: 3000000)));
    expect(const MemoryCacheSettings(), const MemoryCacheSettings());
    expect(const MemoryCacheSettings(),
        isNot(MemoryCacheSettings(gcSettings: MemoryLruGcSettings())));
    expect(MemoryLruGcSettings(sizeBytes: 2000000),
        MemoryLruGcSettings(sizeBytes: 2000000));
    expect(const MemoryEagerGcSettings(), const MemoryEagerGcSettings());
    expect(const MemoryEagerGcSettings().hashCode,
        const MemoryEagerGcSettings().hashCode);
    expect(Settings(cacheSettings: const MemoryCacheSettings()),
        Settings(cacheSettings: const MemoryCacheSettings()));
    expect(Settings(cacheSettings: const MemoryCacheSettings()),
        isNot(Settings(persistenceEnabled: false)));
    expect(
        Settings(cacheSettings: const MemoryCacheSettings())
            .toString(),
        contains('MemoryCacheSettings{gcSettings=MemoryEagerGcSettings{}}'));
  });

  group('emulator', () {
    test('withEmulator sets host, port and disables ssl', () {
      final Settings settings =
          Settings().withEmulator('10.0.2.2', 8080);
      expect(settings.host, '10.0.2.2');
      expect(settings.port, 8080);
      expect(settings.sslEnabled, isFalse);
    });

    test('withEmulator keeps the other settings', () {
      final Settings settings = Settings(
        cacheSettings: PersistentCacheSettings(sizeBytes: 2000000),
      ).withEmulator('localhost', 9000);
      expect(
          settings.cacheSettings, PersistentCacheSettings(sizeBytes: 2000000));
      expect(settings.cacheSizeBytes, 2000000);

      final Settings legacy =
          Settings(persistenceEnabled: false)
              .withEmulator('localhost', 9000);
      expect(legacy.persistenceEnabled, isFalse);
    });

    test('withEmulator replaces a host that was set before', () {
      // Upstream (57ffa1f) warns and uses the emulator host.
      final Settings settings =
          Settings(host: 'myhost.com', port: 1, sslEnabled: true)
              .withEmulator('10.0.2.2', 8080);
      expect(settings.host, '10.0.2.2');
      expect(settings.port, 8080);
      expect(settings.sslEnabled, isFalse);
    });
  });

  group('SnapshotListenOptions', () {
    test('defaults', () {
      const SnapshotListenOptions options = SnapshotListenOptions();
      expect(options.metadataChanges, MetadataChanges.exclude);
      expect(options.source, ListenSource.defaultSource);
    });

    test('value semantics', () {
      expect(const SnapshotListenOptions(source: ListenSource.cache),
          const SnapshotListenOptions(source: ListenSource.cache));
      expect(const SnapshotListenOptions(source: ListenSource.cache),
          isNot(const SnapshotListenOptions()));
      expect(
          const SnapshotListenOptions(metadataChanges: MetadataChanges.include)
              .toString(),
          contains('MetadataChanges.include'));
    });
  });
  group('long polling settings', () {
    test('auto detection is on by default and off when polling is forced', () {
      final Settings defaults = Settings();
      expect(defaults.webExperimentalForceLongPolling, isFalse);
      expect(defaults.webExperimentalAutoDetectLongPolling, isTrue);

      final Settings forced =
          Settings(webExperimentalForceLongPolling: true);
      expect(forced.webExperimentalForceLongPolling, isTrue);
      expect(forced.webExperimentalAutoDetectLongPolling, isFalse);

      final Settings off =
          Settings(webExperimentalAutoDetectLongPolling: false);
      expect(off.webExperimentalForceLongPolling, isFalse);
      expect(off.webExperimentalAutoDetectLongPolling, isFalse);
    });

    test('both together are rejected, as in the JS SDK', () {
      expect(
          () => Settings(
              webExperimentalForceLongPolling: true,
              webExperimentalAutoDetectLongPolling: true),
          throwsArgumentError);
    });

    test('copies keep them, and forcing in a copy turns detection off', () {
      final Settings forced =
          Settings(webExperimentalForceLongPolling: true);
      final Settings emulator = forced.withEmulator('localhost', 8080);
      expect(emulator.webExperimentalForceLongPolling, isTrue);
      expect(emulator.webExperimentalAutoDetectLongPolling, isFalse);
      expect(forced.copyWith(port: 1).webExperimentalForceLongPolling, isTrue);

      final Settings copy =
          Settings().copyWith(webExperimentalForceLongPolling: true);
      expect(copy.webExperimentalForceLongPolling, isTrue);
      expect(copy.webExperimentalAutoDetectLongPolling, isFalse);
      expect(
          copy
              .copyWith(webExperimentalForceLongPolling: false)
              .webExperimentalAutoDetectLongPolling,
          isTrue);
    });

    test('they are part of equality', () {
      expect(Settings(webExperimentalForceLongPolling: true),
          Settings(webExperimentalForceLongPolling: true));
      expect(Settings(webExperimentalForceLongPolling: true),
          isNot(Settings()));
      expect(Settings(webExperimentalAutoDetectLongPolling: false),
          isNot(Settings()));
    });
  });

  // Ports of the `timeoutSeconds` tests of the JS SDK
  // (packages/firestore/test/unit/api/database.test.ts). The JS SDK throws a
  // FirestoreError with code invalid-argument; this port throws an
  // ArgumentError, like its other settings, with the same message.
  group('experimentalLongPollingOptions', () {
    Settings withTimeout(num? timeoutSeconds) => Settings(
          webExperimentalLongPollingOptions:
              WebExperimentalLongPollingOptions(timeoutSeconds: timeoutSeconds),
        );

    Matcher throwsInvalidTimeout(String pattern) => throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => '${e.message}',
            'message',
            matches(RegExp(pattern, caseSensitive: false)),
          ),
        );

    test('timeoutSeconds is undefined by default', () {
      expect(
          Settings().webExperimentalLongPollingOptions.timeoutSeconds,
          isNull);
    });

    test('timeoutSeconds minimum value is allowed', () {
      expect(withTimeout(5).webExperimentalLongPollingOptions.timeoutSeconds, 5);
    });

    test('timeoutSeconds maximum value is allowed', () {
      expect(withTimeout(30).webExperimentalLongPollingOptions.timeoutSeconds, 30);
    });

    test('timeoutSeconds typical value is allowed', () {
      expect(withTimeout(25).webExperimentalLongPollingOptions.timeoutSeconds, 25);
    });

    test('timeoutSeconds floating point value is allowed', () {
      expect(
          withTimeout(12.3456).webExperimentalLongPollingOptions.timeoutSeconds,
          12.3456);
    });

    test('timeoutSeconds value one less than minimum throws', () {
      expect(() => withTimeout(4),
          throwsInvalidTimeout(r'invalid.*timeout.*4.*\(.*5.*\)'));
    });

    test('timeoutSeconds value one more than maximum throws', () {
      expect(() => withTimeout(31),
          throwsInvalidTimeout(r'invalid.*timeout.*31.*\(.*30.*\)'));
    });

    test('timeoutSeconds value of 0 throws', () {
      expect(() => withTimeout(0),
          throwsInvalidTimeout(r'invalid.*timeout.*0.*\(.*5.*\)'));
    });

    test('timeoutSeconds value of -0 throws', () {
      expect(() => withTimeout(-0.0),
          throwsInvalidTimeout(r'invalid.*timeout.*0.*\(.*5.*\)'));
    });

    test('timeoutSeconds value of -1 throws', () {
      expect(() => withTimeout(-1),
          throwsInvalidTimeout(r'invalid.*timeout.*-1.*\(.*5.*\)'));
    });

    test('timeoutSeconds value of -infinity throws', () {
      expect(() => withTimeout(double.negativeInfinity),
          throwsInvalidTimeout(r'invalid.*timeout.*-Infinity.*\(.*5.*\)'));
    });

    test('timeoutSeconds value of +infinity throws', () {
      expect(() => withTimeout(double.infinity),
          throwsInvalidTimeout(r'invalid.*timeout.*Infinity.*\(.*30.*\)'));
    });

    test('timeoutSeconds value of NaN throws', () {
      expect(() => withTimeout(double.nan),
          throwsInvalidTimeout(r'invalid.*timeout.*NaN'));
    });

    test('copies keep the options, which are part of equality', () {
      final Settings settings = withTimeout(25);
      expect(
          settings
              .copyWith(host: 'example.com')
              .webExperimentalLongPollingOptions
              .timeoutSeconds,
          25);
      expect(
          settings
              .copyWith(
                  webExperimentalLongPollingOptions:
                      const WebExperimentalLongPollingOptions(timeoutSeconds: 10))
              .webExperimentalLongPollingOptions
              .timeoutSeconds,
          10);
      expect(() => settings.copyWith(
              webExperimentalLongPollingOptions:
                  const WebExperimentalLongPollingOptions(timeoutSeconds: 31)),
          throwsArgumentError);
      expect(withTimeout(25), withTimeout(25));
      expect(withTimeout(25).hashCode, withTimeout(25).hashCode);
      expect(withTimeout(25), isNot(withTimeout(26)));
      expect(withTimeout(25), isNot(Settings()));
    });
  });

  group('grpcFlowControlWindow', () {
    // Upstream: FirebaseFirestoreSettingsTest (Android) and the settings
    // validation of the JS SDK.
    test('defaults to 256 KiB', () {
      expect(Settings.defaultGrpcFlowControlWindow, 262144);
      expect(Settings().grpcFlowControlWindow, 262144);
    });

    test('can be set, and copies keep it', () {
      final Settings settings = Settings(
        grpcFlowControlWindow: 65535,
      );
      expect(settings.grpcFlowControlWindow, 65535);
      expect(settings.copyWith(host: 'a.b.c').grpcFlowControlWindow, 65535);
      expect(
        settings.withEmulator('localhost', 8080).grpcFlowControlWindow,
        65535,
      );
      expect(
        settings
            .copyWith(grpcFlowControlWindow: 1024 * 1024)
            .grpcFlowControlWindow,
        1024 * 1024,
      );
    });

    test('must be a positive integer of at most 2147483647', () {
      for (final int window in <int>[0, -1, 2147483648]) {
        expect(
          () => Settings(grpcFlowControlWindow: window),
          throwsArgumentError,
          reason: '$window',
        );
        expect(
          () => Settings().copyWith(grpcFlowControlWindow: window),
          throwsArgumentError,
          reason: '$window',
        );
      }
      expect(
        Settings(grpcFlowControlWindow: 1).grpcFlowControlWindow,
        1,
      );
      expect(
        Settings(
          grpcFlowControlWindow: 2147483647,
        ).grpcFlowControlWindow,
        2147483647,
      );
    });

    test('is part of equality', () {
      expect(
        Settings(grpcFlowControlWindow: 65535),
        Settings(grpcFlowControlWindow: 65535),
      );
      expect(
        Settings(grpcFlowControlWindow: 65535),
        isNot(Settings()),
      );
    });
  });
}
