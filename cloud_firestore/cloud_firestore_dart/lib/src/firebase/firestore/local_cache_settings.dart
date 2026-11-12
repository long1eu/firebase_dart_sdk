// Copyright 2023 Google LLC (behaviour ported from the Android SDK)
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

import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_settings.dart';

/// Configures the local cache of a Firestore instance, see
/// [FirestoreSettings.cacheSettings]. The implementations are
/// [PersistentCacheSettings] and [MemoryCacheSettings].
sealed class LocalCacheSettings {
  const LocalCacheSettings();
}

/// Configures a cache stored on disk (the default). The on disk cache is
/// garbage collected once it exceeds [sizeBytes].
final class PersistentCacheSettings extends LocalCacheSettings {
  /// [sizeBytes] is an approximate cache size threshold: if the cache grows
  /// beyond it, Firestore starts removing data that has not been recently used.
  /// Use [FirestoreSettings.cacheSizeUnlimited] to disable the collection. The
  /// minimum is 1 MB, an [ArgumentError] is thrown otherwise.
  PersistentCacheSettings(
      {this.sizeBytes = FirestoreSettings.defaultCacheSizeBytes}) {
    if (sizeBytes != FirestoreSettings.cacheSizeUnlimited &&
        sizeBytes < FirestoreSettings.minimumCacheBytes) {
      throw ArgumentError(
          'Cache size must be set to at least ${FirestoreSettings.minimumCacheBytes} bytes');
    }
  }

  /// The cache size threshold, in bytes.
  final int sizeBytes;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentCacheSettings && sizeBytes == other.sizeBytes;

  @override
  int get hashCode => sizeBytes.hashCode;

  @override
  String toString() => 'PersistentCacheSettings{sizeBytes=$sizeBytes}';
}

/// Configures an in memory cache, which is lost when the instance is shut
/// down. The memory cache is garbage collected as configured by [gcSettings].
final class MemoryCacheSettings extends LocalCacheSettings {
  /// Creates the settings, by default with eager garbage collection.
  const MemoryCacheSettings({this.gcSettings = const MemoryEagerGcSettings()});

  /// The garbage collector of the memory cache.
  final MemoryGarbageCollectorSettings gcSettings;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MemoryCacheSettings && gcSettings == other.gcSettings;

  @override
  int get hashCode => gcSettings.hashCode;

  @override
  String toString() => 'MemoryCacheSettings{gcSettings=$gcSettings}';
}

/// Configures the garbage collector of a [MemoryCacheSettings].
sealed class MemoryGarbageCollectorSettings {
  const MemoryGarbageCollectorSettings();
}

/// Eager garbage collection: documents that are no longer needed by any
/// listener or pending write are removed from the memory cache immediately.
final class MemoryEagerGcSettings extends MemoryGarbageCollectorSettings {
  const MemoryEagerGcSettings();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is MemoryEagerGcSettings;

  @override
  int get hashCode => (MemoryEagerGcSettings).hashCode;

  @override
  String toString() => 'MemoryEagerGcSettings{}';
}

/// Least recently used garbage collection: the memory cache is collected once
/// it exceeds [sizeBytes], starting with the least recently used data.
final class MemoryLruGcSettings extends MemoryGarbageCollectorSettings {
  /// [sizeBytes] is an approximate threshold, see
  /// [PersistentCacheSettings.sizeBytes] for the accepted values.
  MemoryLruGcSettings(
      {this.sizeBytes = FirestoreSettings.defaultCacheSizeBytes}) {
    if (sizeBytes != FirestoreSettings.cacheSizeUnlimited &&
        sizeBytes < FirestoreSettings.minimumCacheBytes) {
      throw ArgumentError(
          'Cache size must be set to at least ${FirestoreSettings.minimumCacheBytes} bytes');
    }
  }

  /// The cache size threshold, in bytes.
  final int sizeBytes;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MemoryLruGcSettings && sizeBytes == other.sizeBytes;

  @override
  int get hashCode => sizeBytes.hashCode;

  @override
  String toString() => 'MemoryLruGcSettings{sizeBytes=$sizeBytes}';
}
