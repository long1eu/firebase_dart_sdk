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
  /// [mergeUnsentWrites] is experimental and off by default, see [mergeUnsentWrites].
  PersistentCacheSettings({
    this.sizeBytes = Settings.defaultCacheSizeBytes,
    this.indexAutoCreation = false,
    IndexBackfillSettings? indexBackfill,
    this.mergeUnsentWrites = false,
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

  /// **Experimental, not in the official SDKs.** Whether a write to a document whose previous write is still pending
  /// and was not sent yet replaces that write with one merged write, instead of queuing a second one. Off by default;
  /// when off nothing changes.
  ///
  /// This keeps the queue of pending writes short for an app that stays offline for a long time and edits the same
  /// documents again and again: about one pending write per document instead of one per edit, so a smaller cache, a
  /// shorter reconnect and fewer billed writes. The documents on the backend end up the same as when every write is
  /// sent, as long as the backend would have accepted each of them.
  ///
  /// A write is merged only when all of these hold:
  ///
  /// * It is a single write (`set`, `update` or `delete`, or a `WriteBatch` with one write), and the newest pending
  ///   write of its document is also a batch with one write. Batches with several writes are atomic and are never
  ///   merged into, nor merged.
  /// * That pending write was never handed to the network layer in this session (in particular it is not in flight,
  ///   and the up to 10 writes queued for the write stream are left alone). Writes queued while the network is enabled
  ///   but the device is offline are handed out ahead of time, so the first few writes of an offline period stay
  ///   separate.
  /// * No other client uses the cache: with a persistent cache, no other client refreshed its row in the cache within
  ///   the last 30 minutes (unless the database is an `ExclusiveDatabase`); clients that share their state are never
  ///   merged.
  /// * The two writes combine in one of these ways (other combinations stay queued as two writes):
  ///   * The new write is a `set` without merge (also one with `serverTimestamp`, but not one with `increment`,
  ///     `arrayUnion` or `arrayRemove`, which the local view computes from the value before the write) or a
  ///     `delete`: it replaces the pending write, whatever that was. The result of such a write does not depend on
  ///     the document before it.
  ///   * The new write is an `update` or a `set` with merge, and the pending write is:
  ///     * a `set` (with no transforms but `serverTimestamp`): one `set` of the pending value with the new fields
  ///       applied;
  ///     * an `update` or a `set` with merge: one write of the fields of both (the paths of both masks, with the values
  ///       after both), with the precondition of the pending write; only when the pending write has no precondition (a
  ///       `set` with merge) or both are `update`s (if the first one fails on a missing document, so does the second);
  ///     * a `delete`, and the new write is a `set` with merge: one `set` of the new fields.
  ///
  ///     Their transforms (`serverTimestamp`, `increment`, `arrayUnion`, `arrayRemove`) combine field by field:
  ///     * a transform of the pending write on a field that the new write writes, deletes or sets to `serverTimestamp`
  ///       is dropped (the later write wins); a `serverTimestamp` of the new write stays;
  ///     * two `arrayUnion`s of the same field become one `arrayUnion` of the elements of both, in order and without
  ///       repeating an element; two `arrayRemove`s become one `arrayRemove` of the elements of both;
  ///     * an `increment` of the new write on a field whose value before it is known (one the pending write set, or
  ///       any field when the pending write is a `set` or a `delete`) is written as its result, when both numbers are
  ///       integers (within +-2^53) or both are doubles;
  ///     * after an `update` or a `set` with merge, a transform on a field that overlaps nothing the other write
  ///       writes, deletes or transforms (no field equal to it, inside it or containing it) stays as it is, and so does
  ///       a transform of the new write on a field it writes itself.
  ///
  ///     Anything else stays queued as two writes, in particular an `increment` after an `increment` of the same
  ///     field: the backend adds the two numbers one at a time, and a field that holds a double can round differently
  ///     when the two are added first. Also an `arrayUnion` after an `arrayRemove` of the same field (or the reverse),
  ///     an `arrayUnion` or `arrayRemove` of the new write after a `set` or a `delete`, a pending `set` with
  ///     `increment` or array transforms, and any other overlap of a transform with a field of the other write.
  ///
  ///   The local view of the merged write is the same as with two writes, except for a `serverTimestamp` of the
  ///   pending write that stays: until the backend confirms it, its estimate is the time of the newer write.
  ///
  /// The merged write takes the place of the newer write in the queue: writes to other documents queued in between
  /// now reach the backend before the earlier state of this document, which never reaches it at all. The future of
  /// every merged write completes, or fails, with the merged write, and `waitForPendingWrites` waits for it.
  ///
  /// Writes that are already queued when an instance starts with the setting on (queued in an earlier session, or
  /// with the setting off) are merged once, at start, by the same rules and on the same conditions: each write is
  /// merged into the pending write of its document as if it had just been made, in the order of the queue, so the
  /// queue becomes the one the setting would have built from the same writes. This runs in transactions of 500
  /// writes queued as operations of the instance, so reads and writes of the app run between them; no write is sent
  /// to the backend until it is done. A write made meanwhile is merged when the merge of the queue reaches it. The
  /// progress is saved with each transaction: a merge that is stopped (the app is closed, the process is killed)
  /// resumes where it was at the next start, and a queue that was merged is not read again. It does not run while
  /// another client uses the cache, and the queue of a user who signs in later is merged when they sign in.
  ///
  /// What the app gives up:
  ///
  /// * Security rules and Cloud Functions triggers see one write instead of several, and never the intermediate
  ///   states. Rules that check a transition (`request.resource` against `resource`) see the transition from the
  ///   first state to the last.
  /// * A rejection rejects all the merged writes: the future of each of them fails with the same error.
  /// * Writes to other documents in between no longer see this document in its intermediate state, for example a
  ///   rule that reads it with `get()`. Do not enable this when rules or functions depend on the order of writes
  ///   across documents.
  /// * The precondition of a write that is replaced by a `set` or a `delete` is not checked: an `update` of a
  ///   missing document that is followed by a `set` succeeds instead of failing.
  final bool mergeUnsentWrites;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistentCacheSettings &&
          sizeBytes == other.sizeBytes &&
          indexAutoCreation == other.indexAutoCreation &&
          indexBackfill == other.indexBackfill &&
          mergeUnsentWrites == other.mergeUnsentWrites;

  @override
  int get hashCode => Object.hash(
    sizeBytes,
    indexAutoCreation,
    indexBackfill,
    mergeUnsentWrites,
  );

  @override
  String toString() =>
      'PersistentCacheSettings{sizeBytes=$sizeBytes, '
      'indexAutoCreation=$indexAutoCreation, indexBackfill=$indexBackfill'
      '${mergeUnsentWrites ? ', mergeUnsentWrites=true' : ''}}';
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
  /// Creates the settings, by default with eager garbage collection and without merging writes.
  const MemoryCacheSettings({
    this.gcSettings = const MemoryEagerGcSettings(),
    this.mergeUnsentWrites = false,
  });

  /// The garbage collector of the memory cache.
  final MemoryGarbageCollectorSettings gcSettings;

  /// **Experimental, not in the official SDKs.** Whether a write to a document whose previous write is still pending
  /// and was not sent yet replaces that write with one merged write. Off by default. The conditions and what the app
  /// gives up are those of [PersistentCacheSettings.mergeUnsentWrites].
  final bool mergeUnsentWrites;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MemoryCacheSettings &&
          gcSettings == other.gcSettings &&
          mergeUnsentWrites == other.mergeUnsentWrites;

  @override
  int get hashCode => Object.hash(gcSettings, mergeUnsentWrites);

  @override
  String toString() =>
      'MemoryCacheSettings{gcSettings=$gcSettings'
      '${mergeUnsentWrites ? ', mergeUnsentWrites=true' : ''}}';
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
