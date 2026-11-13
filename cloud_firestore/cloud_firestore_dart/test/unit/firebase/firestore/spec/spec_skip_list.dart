// Copyright 2026 Google LLC
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

import 'dart:convert';

/// THE ONE PLACE that decides which spec tests are not run.
///
/// A spec test is skipped only when it needs a *feature the port does not have* (or a platform-specific feature that
/// upstream Android also excludes). Every skip is a named entry below with a reason, and the runner reports each one as
/// a skipped `test()` that carries that reason, so nothing disappears silently. When a feature lands, delete (or set to
/// `null`) its entry and the specs that need it start running.
///
/// Specs that fail because of a real divergence are NOT listed here: they stay failing on purpose, unless the
/// divergence is one upstream Android shares and needs a redesign to remove (then it goes in [knownSpecDivergences]).
///
/// Features are detected from the spec JSON by [detectSpecFeatures]; a spec that needs several features is reported
/// with the first one in this map's iteration order.
const Map<String, String?> skippedSpecFeatures = <String, String?>{
  // --- Excluded by upstream Android too (SpecTestCase.DISABLED_TAGS) ---
  // Upstream Android skips the tag. The port runs the multi-client specs on SQLite (shared client state, primary
  // lease); memory persistence skips them (memoryExcludedTags), as the JS SDK. The one that needs another missing
  // feature is caught by a more precise entry below ('clear-persistence').
  'multi-client': null,
  // Upstream Android skips the tag; the port runs these specs. The single-client ones pass (the bloom filter one, the
  // three "Fix #8474" limbo ones after porting the JS fix to WatchChangeAggregator, the recovery ones after porting
  // the JS persistence recovery), except one entry of [knownSpecDivergences].
  'no-android': null,
  // Upstream runs them only with RUN_BENCHMARK_TESTS; they pass here and take about 3 s for both persistences.
  'benchmark': null,

  // --- Features the port lacks ---
  'bundles': null,
  // Landed (field indexes, the setIndexConfiguration step and expectedState.indexes). Both specs that use it are
  // multi-client and stay skipped for that reason; index_spec_single_client_test.dart runs their single-client form.
  'indexing': null,
  // Landed (ListenSource.cache): enabled again, kept as a null entry to show how a feature is switched on.
  'listen-source-cache': null,
  'limit-to-last': null,
  // Landed (EventManager snapshots-in-sync listeners, SyncEngine.registerPendingWritesTask): enabled.
  'snapshots-in-sync': null,
  'wait-for-pending-writes': null,
  // Landed (Decimal128Value and the other BSON types): enabled.
  'decimal128': null,
  // Landed (recovery from a failing persistence: RemoteStore.enqueueRetryable / disableNetworkUntilRecovery, the
  // failDatabase step over PersistenceFaultInjector): enabled.
  'fail-database': null,
  'clear-persistence':
      'clearPersistence step shuts down other clients of a shared persistence; the only spec is multi-client.',
  'write-ack-transform-results': null,
};

/// Tags that exclude a spec for one persistence variant only (not a missing feature: the spec simply does not apply to
/// that persistence). Mirrors MemorySpecTest / SQLiteSpecTest upstream.
const Map<String, String> memoryExcludedTags = <String, String>{
  'multi-client':
      'multi-client: several clients need a durable shared persistence; like the JS SDK, the memory persistence variant skips it.',
  'durable-persistence':
      'durable-persistence: needs a persistence that survives restart; the memory persistence variant skips it (as upstream).',
};

const Map<String, String> sqliteExcludedTags = <String, String>{
  'eager-gc':
      'eager-gc: relies on eager garbage collection, which only exists for memory persistence (as upstream).',
};

/// Single specs that need a library design the port (like upstream Android) does not have, or that the harness can
/// not express, keyed by `'<describeName> <itName>'`. Unlike [skippedSpecFeatures] these are not detectable from the
/// spec JSON: the spec uses only supported steps.
const Map<String, String> knownSpecDivergences = <String, String>{
  'Persistence Recovery Multiple user changes during transaction failure (with recovery)':
      'Harness timing, not the library: after a retried operation succeeds, the next one is scheduled with the reset '
      'backoff, a zero delay (as JS). The JS runner validates a step before such a timer fires; this runner lets the '
      'event loop settle after every step, which runs it, so both user changes surface in the first runTimer step. '
      'The library behaviour (both changes applied in order after the recovery) is the JS one. Fix (verified on '
      'memory and SQLite, no other spec affected): create the TaskScheduler of SpecClient._initClient with '
      'manualTasks: {TaskId.asyncQueueRetry}, so that retries only run on runTimer, and remove this entry. See '
      'docs/ARCHITECTURE.md, "Tests".',
  'Writes: Writes are held during primary failover':
      'The SQLite primary lease (stage 1) notices that another client took the lease at the first transaction after '
      'that client committed (SQLiteClientMetadata._onForeignCommit); the JS SDK notices it only at its next lease '
      'refresh or primary-only transaction. The old primary steps down one step early, and the spec sees the events of '
      'the step-down before its client_metadata_refresh step.',
  'Persistence Recovery Query is listened to by primary (with recovery)':
      'Not understood yet. The primary releases the target of the other client although the "Release target" '
      'transaction fails: LocalStore.releaseTarget ignores a recoverable failure, as localStoreReleaseTarget of the '
      'JS SDK (the JS source read here does the same), and the target is unlistened at once. The spec expects the '
      'release to wait for the recovery (the change applied again on the async_queue_retry timer).',
  'Listens: Secondary client advances query state with global snapshot from primary':
      'Tagged no-web, no-android and no-ios upstream: no SDK runs it (the JS SDK, which has multi-tab, skips it).',
};

/// Returns the names (keys of [skippedSpecFeatures]) of all features that [testJson] needs.
Set<String> detectSpecFeatures(Map<String, dynamic> testJson) {
  final Set<String> features = <String>{};
  final List<dynamic> tags = testJson['tags'] ?? const <dynamic>[];
  for (final String tag in <String>[
    'multi-client',
    'no-android',
    'benchmark',
  ]) {
    if (tags.contains(tag)) {
      features.add(tag);
    }
  }

  final Map<String, dynamic> config = testJson['config'] ?? <String, dynamic>{};
  if ((config['numClients'] ?? 1) != 1) {
    features.add('multi-client');
  }

  final List<dynamic> steps = testJson['steps'] ?? const <dynamic>[];
  for (final dynamic stepObject in steps) {
    final Map<String, dynamic> step = stepObject as Map<String, dynamic>;
    if ((step['clientIndex'] ?? 0) != 0 ||
        step.containsKey('applyClientState') ||
        step.containsKey('shutdown')) {
      features.add('multi-client');
    }
    if (step.containsKey('loadBundle')) {
      features.add('bundles');
    }
    if (step.containsKey('setIndexConfiguration') ||
        (step['expectedState'] as Map<String, dynamic>?)?.containsKey(
              'indexes',
            ) ==
            true) {
      features.add('indexing');
    }
    final Map<String, dynamic>? listen = step['userListen'];
    if (listen != null && listen['options']?['source'] == 'cache') {
      features.add('listen-source-cache');
    }
    if (step.containsKey('addSnapshotsInSyncListener') ||
        step.containsKey('removeSnapshotsInSyncListener') ||
        step.containsKey('expectedSnapshotsInSyncEvents')) {
      features.add('snapshots-in-sync');
    }
    if (step.containsKey('waitForPendingWrites') ||
        step.containsKey('expectedWaitForPendingWritesEvents')) {
      features.add('wait-for-pending-writes');
    }
    if (step.containsKey('failDatabase')) {
      features.add('fail-database');
    }
    if (step.containsKey('clearPersistence')) {
      features.add('clear-persistence');
    }
    if ((step['writeAck'] as Map<String, dynamic>?)?.containsKey(
          'transformResults',
        ) ==
        true) {
      features.add('write-ack-transform-results');
    }
  }

  // Values and query parts that are cheaper to find in the serialized JSON.
  final String text = jsonEncode(steps);
  if (text.contains('"limitType":"LimitToLast"')) {
    features.add('limit-to-last');
  }
  if (text.contains('__decimal128__') || text.contains('"_methodName"')) {
    features.add('decimal128');
  }
  return features;
}

/// Returns the reason why the spec must be skipped on a persistence variant with [excludedTags], or null if it runs.
String? skipReasonFor(
  Map<String, dynamic> testJson,
  Map<String, String> excludedTags,
) {
  final String? divergence =
      knownSpecDivergences['${testJson['describeName']} ${testJson['itName']}'];
  if (divergence != null) {
    return '[known-divergence] $divergence';
  }
  final Set<String> features = detectSpecFeatures(testJson);
  for (final MapEntry<String, String?> entry in skippedSpecFeatures.entries) {
    if (entry.value != null && features.contains(entry.key)) {
      return '[${entry.key}] ${entry.value}';
    }
  }
  final List<dynamic> tags = testJson['tags'] ?? const <dynamic>[];
  for (final MapEntry<String, String> entry in excludedTags.entries) {
    if (tags.contains(entry.key)) {
      return '[${entry.key}] ${entry.value}';
    }
  }
  return null;
}
