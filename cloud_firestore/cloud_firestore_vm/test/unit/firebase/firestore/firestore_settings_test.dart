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

import 'package:cloud_firestore_vm/cloud_firestore_vm.dart';
import 'package:test/test.dart';

void main() {
  test('default settings', () {
    final FirestoreSettings settings = FirestoreSettings();
    expect(settings.host, 'firestore.googleapis.com');
    expect(settings.sslEnabled, isTrue);
    expect(settings.persistenceEnabled, isTrue);
    expect(settings.cacheSizeBytes, 104857600);
    expect(settings.cacheSettings, isNull);
  });

  test('persistent cache settings customize the legacy getters', () {
    final FirestoreSettings settings = FirestoreSettings(
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
    final FirestoreSettings settings = FirestoreSettings(
      host: 'a.b.c',
      sslEnabled: false,
      cacheSettings: const MemoryCacheSettings(),
    );
    expect(settings.persistenceEnabled, isFalse);
    expect(settings.cacheSizeBytes, FirestoreSettings.cacheSizeUnlimited);
    expect((settings.cacheSettings! as MemoryCacheSettings).gcSettings,
        const MemoryEagerGcSettings());
  });

  test('copyWith keeps the cache settings and the derived values', () {
    final FirestoreSettings settings1 = FirestoreSettings(
      host: 'a.b.c',
      sslEnabled: false,
      cacheSettings: const MemoryCacheSettings(),
    );
    final FirestoreSettings settings2 = settings1.copyWith(port: 1234);
    expect(settings2.host, 'a.b.c');
    expect(settings2.port, 1234);
    expect(settings2.sslEnabled, isFalse);
    expect(settings2.persistenceEnabled, isFalse);
    expect(settings2.cacheSizeBytes, FirestoreSettings.cacheSizeUnlimited);
    expect(settings2.cacheSettings, settings1.cacheSettings);
  });

  test('copyWith can replace the cache settings', () {
    final FirestoreSettings settings = FirestoreSettings(
      cacheSettings: const MemoryCacheSettings(),
    ).copyWith(cacheSettings: PersistentCacheSettings(sizeBytes: 5000000));
    expect(settings.persistenceEnabled, isTrue);
    expect(settings.cacheSizeBytes, 5000000);
  });

  test('cannot mix the legacy and the new cache config', () {
    expect(
        () => FirestoreSettings(
              persistenceEnabled: false,
              cacheSettings: const MemoryCacheSettings(),
            ),
        throwsStateError);
    expect(
        () => FirestoreSettings(
              cacheSizeBytes: 2000000,
              cacheSettings: PersistentCacheSettings(),
            ),
        throwsStateError);
    expect(
        () => FirestoreSettings(cacheSettings: const MemoryCacheSettings())
            .copyWith(persistenceEnabled: false),
        throwsStateError);
  });

  test('legacy settings keep working', () {
    final FirestoreSettings settings =
        FirestoreSettings(persistenceEnabled: false);
    expect(settings.persistenceEnabled, isFalse);
    expect(settings.cacheSettings, isNull);
    final FirestoreSettings sized = FirestoreSettings(cacheSizeBytes: 2000000);
    expect(sized.cacheSizeBytes, 2000000);
  });

  test('validates the cache sizes', () {
    expect(() => PersistentCacheSettings(sizeBytes: 100), throwsArgumentError);
    expect(() => MemoryLruGcSettings(sizeBytes: 100), throwsArgumentError);
    expect(
        PersistentCacheSettings(sizeBytes: FirestoreSettings.cacheSizeUnlimited)
            .sizeBytes,
        -1);
    expect(MemoryLruGcSettings().sizeBytes,
        FirestoreSettings.defaultCacheSizeBytes);
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
    expect(FirestoreSettings(cacheSettings: const MemoryCacheSettings()),
        FirestoreSettings(cacheSettings: const MemoryCacheSettings()));
    expect(FirestoreSettings(cacheSettings: const MemoryCacheSettings()),
        isNot(FirestoreSettings(persistenceEnabled: false)));
    expect(
        FirestoreSettings(cacheSettings: const MemoryCacheSettings())
            .toString(),
        contains('MemoryCacheSettings{gcSettings=MemoryEagerGcSettings{}}'));
  });

  group('emulator', () {
    test('withEmulator sets host, port and disables ssl', () {
      final FirestoreSettings settings =
          FirestoreSettings().withEmulator('10.0.2.2', 8080);
      expect(settings.host, '10.0.2.2');
      expect(settings.port, 8080);
      expect(settings.sslEnabled, isFalse);
    });

    test('withEmulator keeps the other settings', () {
      final FirestoreSettings settings = FirestoreSettings(
        cacheSettings: PersistentCacheSettings(sizeBytes: 2000000),
      ).withEmulator('localhost', 9000);
      expect(
          settings.cacheSettings, PersistentCacheSettings(sizeBytes: 2000000));
      expect(settings.cacheSizeBytes, 2000000);

      final FirestoreSettings legacy =
          FirestoreSettings(persistenceEnabled: false)
              .withEmulator('localhost', 9000);
      expect(legacy.persistenceEnabled, isFalse);
    });

    test('withEmulator replaces a host that was set before', () {
      // Upstream (57ffa1f) warns and uses the emulator host.
      final FirestoreSettings settings =
          FirestoreSettings(host: 'myhost.com', port: 1, sslEnabled: true)
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
}
