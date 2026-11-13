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
  // The harness runs several clients on one persistence (SpecTestCase / SpecClient); the library is what is missing.
  // The reason of each spec also lists what it uses (see [multiClientCapabilities]), so that the specs can be enabled
  // group by group (parity/multi_client_plan.md).
  'multi-client':
      'Needs the primary lease (multi-client stage 1) and SharedClientState with SyncEngine.applyPrimaryState (stage 2).',
  // Upstream Android skips the tag; the port runs these specs. The single-client ones pass (the bloom filter one and
  // the three "Fix #8474" limbo ones, after porting the JS fix to WatchChangeAggregator), except those caught by a
  // more precise entry below: 'fail-database' (the recovery specs) and 'watch-stream-no-backoff'.
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
  'fail-database':
      'Persistence failure recovery (the JS IndexedDbTransactionError handling) is not ported, like Android; see '
      'docs/ARCHITECTURE.md, "Deliberate deviations from upstream" > Persistence. The runner would also need a '
      'failDatabase step over a fault-injecting persistence.',
  'watch-stream-no-backoff':
      'watchStreamClose with runBackoffTimer: false. Runner limitation, not a library one: the mock watch stream '
      '(mock_datastore.dart) restarts synchronously without the backoff timer, as on Android, so a stream left '
      'closed in backoff can not be expressed. See docs/ARCHITECTURE.md, "Tests".',
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

/// Single specs that need a library design the port (like upstream Android) does not have, keyed by
/// `'<describeName> <itName>'`. Unlike [skippedSpecFeatures] these are not detectable from the spec JSON: the spec
/// uses only supported steps but expects behaviour that only the JS SDK implements.
const Map<String, String> knownSpecDivergences = <String, String>{};

/// What a multi-client spec uses beyond a second client, keyed by a short name, with the library part it needs. Only
/// used to explain the skip reason of a multi-client spec (see [multiClientCapabilitiesOf]).
const Map<String, String> multiClientCapabilities = <String, String>{
  'client-state':
      'applyClientState (visibility or forced primary: lease election, stage 1)',
  'primary-state':
      'expectedState.isPrimary / numActiveClients (lease and client metadata, stage 1)',
  'metadata-refresh':
      'runTimer client_metadata_refresh (lease refresh and failover, stage 1)',
  'shutdown': 'shutdown of a client (lease release and failover, stage 1)',
  'remote-listen':
      'listens on a client other than 0 (target state through SharedClientState, stage 2)',
  'remote-write':
      'writes on a client other than 0 (batch state through SharedClientState, stage 2)',
  'remote-bundle':
      'loadBundle on a client other than 0 (changed documents through SharedClientState, stage 2)',
  'remote-network':
      'network, user or pending-writes steps on a client other than 0 (stage 2)',
};

/// Returns the keys of [multiClientCapabilities] that [testJson] uses, in the order of that map.
List<String> multiClientCapabilitiesOf(Map<String, dynamic> testJson) {
  final Set<String> found = <String>{};
  final List<dynamic> steps = testJson['steps'] ?? const <dynamic>[];
  for (final dynamic stepObject in steps) {
    final Map<String, dynamic> step = stepObject as Map<String, dynamic>;
    final bool otherClient = (step['clientIndex'] ?? 0) != 0;
    final Map<String, dynamic> state =
        step['expectedState'] as Map<String, dynamic>? ?? <String, dynamic>{};
    if (step.containsKey('applyClientState')) {
      found.add('client-state');
    }
    if (state.containsKey('isPrimary') ||
        state.containsKey('numActiveClients')) {
      found.add('primary-state');
    }
    if (step['runTimer'] == 'client_metadata_refresh') {
      found.add('metadata-refresh');
    }
    if (step.containsKey('shutdown')) {
      found.add('shutdown');
    }
    if (otherClient && step.containsKey('userListen')) {
      found.add('remote-listen');
    }
    if (otherClient &&
        (step.containsKey('userSet') ||
            step.containsKey('userPatch') ||
            step.containsKey('userDelete'))) {
      found.add('remote-write');
    }
    if (otherClient && step.containsKey('loadBundle')) {
      found.add('remote-bundle');
    }
    if (otherClient &&
        (step.containsKey('enableNetwork') ||
            step.containsKey('changeUser') ||
            step.containsKey('waitForPendingWrites'))) {
      found.add('remote-network');
    }
  }
  return <String>[
    for (final String key in multiClientCapabilities.keys)
      if (found.contains(key)) key,
  ];
}

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
    if ((step['watchStreamClose']
            as Map<String, dynamic>?)?['runBackoffTimer'] ==
        false) {
      features.add('watch-stream-no-backoff');
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
      if (entry.key == 'multi-client') {
        return '[multi-client] ${entry.value}${_multiClientDetails(features, testJson)}';
      }
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

/// The capabilities a multi-client spec uses and the other skipped features it needs, appended to its skip reason.
String _multiClientDetails(
  Set<String> features,
  Map<String, dynamic> testJson,
) {
  final List<String> uses = <String>[
    for (final String key in multiClientCapabilitiesOf(testJson))
      multiClientCapabilities[key]!,
  ];
  final List<String> alsoNeeds = <String>[
    for (final MapEntry<String, String?> entry in skippedSpecFeatures.entries)
      if (entry.key != 'multi-client' &&
          entry.value != null &&
          features.contains(entry.key))
        entry.key,
  ];
  return '${uses.isEmpty ? '' : ' Uses: ${uses.join('; ')}.'}'
      '${alsoNeeds.isEmpty ? '' : ' Also needs: ${alsoNeeds.join(', ')}.'}';
}
