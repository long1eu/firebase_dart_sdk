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
/// [Settings.cacheSettings]. The implementations are
/// [PersistentCacheSettings] and [MemoryCacheSettings].
///
/// The cache holds the documents that listeners and reads received and the writes that the backend has not
/// acknowledged yet; reads and listeners use it while the client is offline. This is the `localCache` setting of
/// the JS SDK (`persistentLocalCache()` and `memoryLocalCache()`).
///
/// ```dart
/// final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
///   app: app,
///   openDatabase: openDatabase, // needed for a persistent cache
///   settings: Settings(cacheSettings: PersistentCacheSettings()),
/// );
/// ```
sealed class LocalCacheSettings {
  const LocalCacheSettings();
}

/// Configures a cache stored on disk (the default). The on disk cache is
/// garbage collected once it exceeds [sizeBytes].
///
/// The cache is stored in the SQLite database that the `openDatabase` function of `FirebaseFirestore.instanceFor` opens
/// (a file on the VM, IndexedDB or OPFS on the web). Without that function the instance falls back to a memory
/// cache. The data and the pending writes survive a restart of the program.
///
/// ```dart
/// final Settings settings = Settings(
///   cacheSettings: PersistentCacheSettings(
///     sizeBytes: Settings.cacheSizeUnlimited,
///   ),
/// );
/// ```
final class PersistentCacheSettings extends LocalCacheSettings {
  /// [sizeBytes] is an approximate cache size threshold: if the cache grows
  /// beyond it, Firestore starts removing data that has not been recently used.
  /// Use [Settings.cacheSizeUnlimited] to disable the collection. The
  /// minimum is 1 MB, an [ArgumentError] is thrown otherwise.
  ///
  /// [indexAutoCreation] and [indexBackfill] configure the persistent cache
  /// indexes; the defaults are the behaviour of the official SDKs.
  PersistentCacheSettings({
    this.sizeBytes = Settings.defaultCacheSizeBytes,
    this.indexAutoCreation = false,
    IndexBackfillSettings? indexBackfill,
  }) : indexBackfill = indexBackfill ?? IndexBackfillSettings() {
    if (sizeBytes != Settings.cacheSizeUnlimited &&
        sizeBytes < Settings.minimumCacheBytes) {
      throw ArgumentError(
        'Cache size must be set to at least ${Settings.minimumCacheBytes} bytes',
      );
    }
  }

  /// The cache size threshold, in bytes.
  final int sizeBytes;

  /// Whether the automatic creation of persistent cache indexes is on from the
  /// start of the instance, as if `PersistentCacheIndexManager.enableIndexAutoCreation`
  /// had been called before the first query. Defaults to false.
  ///
  /// The official SDKs have no such setting (there automatic creation is off
  /// after every start until the app turns it on); this one is specific to
  /// this package. `PersistentCacheIndexManager.disableIndexAutoCreation` still
  /// turns it off until the next start.
  final bool indexAutoCreation;

  /// How fast the persistent cache indexes are filled in the background. The
  /// default is the fixed rate of the official SDKs.
  final IndexBackfillSettings indexBackfill;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentCacheSettings &&
          sizeBytes == other.sizeBytes &&
          indexAutoCreation == other.indexAutoCreation &&
          indexBackfill == other.indexBackfill;

  @override
  int get hashCode => Object.hash(sizeBytes, indexAutoCreation, indexBackfill);

  @override
  String toString() =>
      'PersistentCacheSettings{sizeBytes=$sizeBytes, '
      'indexAutoCreation=$indexAutoCreation, indexBackfill=$indexBackfill}';
}

/// The rate at which the persistent cache indexes are filled in the
/// background, see [PersistentCacheSettings.indexBackfill].
///
/// The fill runs on the queue of the instance: while a run lasts, the other
/// operations of the instance wait. A run costs about 50 to 200 microseconds
/// per document on a cache without many pending writes (more with many
/// pending writes in the collection), so [documentsPerRun] sets how long the
/// instance can be blocked, and [documentsPerRun] / [interval] how fast a new
/// index is complete: with the defaults, an index on 10,000 cached documents
/// takes about 200 minutes of running time.
///
/// The official SDKs have a fixed rate (the defaults below); this setting is
/// specific to this package. To fill the indexes at once, for example while a
/// loading screen is shown, see `PersistentCacheIndexManager.fillIndexes`.
///
/// ```dart
/// final Settings settings = Settings(
///   cacheSettings: PersistentCacheSettings(
///     indexAutoCreation: true,
///     indexBackfill: IndexBackfillSettings(
///       documentsPerRun: 200,
///       interval: Duration(seconds: 10),
///     ),
///   ),
/// );
/// ```
final class IndexBackfillSettings {
  /// Throws an [ArgumentError] when [documentsPerRun] is not between 1 and
  /// [maxDocumentsPerRun], when [interval] is shorter than [minInterval] or
  /// longer than [maxDelay], or when [initialDelay] is negative or longer than
  /// [maxDelay].
  IndexBackfillSettings({
    this.documentsPerRun = defaultDocumentsPerRun,
    this.interval = defaultInterval,
    this.initialDelay = defaultInitialDelay,
  }) {
    if (documentsPerRun < 1 || documentsPerRun > maxDocumentsPerRun) {
      throw ArgumentError.value(
        documentsPerRun,
        'documentsPerRun',
        'must be between 1 and $maxDocumentsPerRun',
      );
    }
    if (interval < minInterval || interval > maxDelay) {
      throw ArgumentError.value(
        interval,
        'interval',
        'must be between $minInterval and $maxDelay',
      );
    }
    if (initialDelay < Duration.zero || initialDelay > maxDelay) {
      throw ArgumentError.value(
        initialDelay,
        'initialDelay',
        'must be between ${Duration.zero} and $maxDelay',
      );
    }
  }

  /// The number of documents of the official SDKs, 50.
  static const int defaultDocumentsPerRun = 50;

  /// The delay between two runs in the official SDKs, one minute.
  static const Duration defaultInterval = Duration(minutes: 1);

  /// The delay before the first run in the official SDKs, 15 seconds.
  static const Duration defaultInitialDelay = Duration(seconds: 15);

  /// The largest [documentsPerRun], 1,000: a run of that size blocks the
  /// instance for about 50 to 200 ms on a cache without many pending writes.
  static const int maxDocumentsPerRun = 1000;

  /// The shortest [interval], one second.
  static const Duration minInterval = Duration(seconds: 1);

  /// The longest [interval] and [initialDelay], one day.
  static const Duration maxDelay = Duration(days: 1);

  /// The maximum number of documents that one run indexes, over all
  /// collections. Defaults to 50.
  final int documentsPerRun;

  /// The delay between the end of a run and the start of the next one.
  /// Defaults to one minute.
  final Duration interval;

  /// The delay between the start of the instance and the first run. Defaults
  /// to 15 seconds.
  final Duration initialDelay;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IndexBackfillSettings &&
          documentsPerRun == other.documentsPerRun &&
          interval == other.interval &&
          initialDelay == other.initialDelay;

  @override
  int get hashCode => Object.hash(documentsPerRun, interval, initialDelay);

  @override
  String toString() =>
      'IndexBackfillSettings{documentsPerRun=$documentsPerRun, '
      'interval=$interval, initialDelay=$initialDelay}';
}

/// Configures an in memory cache, which is lost when the instance is shut
/// down. The memory cache is garbage collected as configured by [gcSettings].
///
/// Writes that the backend has not acknowledged when the instance is terminated are lost with it.
///
/// ```dart
/// final Settings settings = Settings(
///   cacheSettings: const MemoryCacheSettings(),
/// );
/// ```
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

/// Configures the garbage collector of a [MemoryCacheSettings]: [MemoryEagerGcSettings] (the default) or
/// [MemoryLruGcSettings].
sealed class MemoryGarbageCollectorSettings {
  const MemoryGarbageCollectorSettings();
}

/// Eager garbage collection: documents that are no longer needed by any
/// listener or pending write are removed from the memory cache immediately.
final class MemoryEagerGcSettings extends MemoryGarbageCollectorSettings {
  /// Creates the settings; eager collection has no options.
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
///
/// Unlike eager collection, documents stay in the cache after their last listener stopped, so a later read or
/// listener can be answered from the cache while offline.
///
/// ```dart
/// final Settings settings = Settings(
///   cacheSettings: MemoryCacheSettings(
///     gcSettings: MemoryLruGcSettings(sizeBytes: 10 * 1024 * 1024),
///   ),
/// );
/// ```
final class MemoryLruGcSettings extends MemoryGarbageCollectorSettings {
  /// [sizeBytes] is an approximate threshold, see
  /// [PersistentCacheSettings.sizeBytes] for the accepted values.
  MemoryLruGcSettings({this.sizeBytes = Settings.defaultCacheSizeBytes}) {
    if (sizeBytes != Settings.cacheSizeUnlimited &&
        sizeBytes < Settings.minimumCacheBytes) {
      throw ArgumentError(
        'Cache size must be set to at least ${Settings.minimumCacheBytes} bytes',
      );
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
