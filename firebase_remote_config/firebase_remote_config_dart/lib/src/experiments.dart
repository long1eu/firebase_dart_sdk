import 'dart:convert';

import 'package:firebase_remote_config_dart/src/json_guard.dart';
import 'package:firebase_remote_config_dart/src/template.dart';
import 'package:meta/meta.dart';

/// Receives the A/B testing state of the active template, so an Analytics client can attribute events
/// to experiment variants (the JS SDK's hand-off, `J:abt/experiment.ts`).
///
/// This package depends on no Analytics package; the app passes an adapter to the `analytics` argument
/// of `FirebaseRemoteConfig`. With `firebase_analytics_dart`, [setUserProperties] calls
/// `analytics.setExperimentProperties(properties)` and [logEvent] calls `analytics.logEvent(name: name)`.
abstract interface class RemoteConfigAnalytics {
  /// Sets one user property per experiment: the name is `firebase` followed by the experiment id, the
  /// value the variant id, and a null value clears the property of an experiment that ended.
  Future<void> setUserProperties(Map<String, String?> properties);

  /// Logs the event [name] without parameters. It is always `set_firebase_experiment_state`, sent right
  /// after [setUserProperties].
  Future<void> logEvent(String name);
}

/// The event logged after the experiment user properties are set (`J:abt/experiment.ts:93`).
const String experimentStateEvent = 'set_firebase_experiment_state';

/// The prefix of an experiment user property; the experiment id follows it (`J:abt/experiment.ts:62`).
const String experimentPropertyPrefix = 'firebase';

/// The most experiments handed to Analytics and kept in the `experiments` record.
const int maxStoredExperiments = 1000;

/// The longest experiment id handed to Analytics and kept in the `experiments` record.
const int maxExperimentIdLength = 256;

/// True when [id] is an experiment id the hand-off accepts: not empty, at most [maxExperimentIdLength]
/// characters.
bool isValidExperimentId(String id) =>
    id.isNotEmpty && id.length <= maxExperimentIdLength;

/// The `experiments` record: the ids of the experiments last handed to Analytics as active (the JS
/// SDK's `active_experiments`, `J:storage/storage.ts:169-175`).
@immutable
final class ExperimentsRecord {
  /// Creates a record; [ids] is copied into an unmodifiable set.
  ExperimentsRecord(Set<String> ids) : ids = Set<String>.unmodifiable(ids);

  /// The experiment ids.
  final Set<String> ids;

  /// The stored text.
  String encode() =>
      jsonEncode(<String, Object?>{'v': 1, 'ids': ids.toList()..sort()});

  /// Reads a stored record, or returns null for a bad one: more than [maxStoredExperiments] ids, or an
  /// id that is not a string or fails [isValidExperimentId].
  static ExperimentsRecord? tryParse(String? text) {
    final Map<String, Object?>? json = decodeRecord(text);
    if (json == null) {
      return null;
    }
    final List<String>? ids = asStringList(json['ids']);
    if (ids == null || ids.length > maxStoredExperiments) {
      return null;
    }
    for (final String id in ids) {
      if (!isValidExperimentId(id)) {
        return null;
      }
    }
    return ExperimentsRecord(ids.toSet());
  }

  @override
  String toString() => 'ExperimentsRecord(<redacted>)';
}

/// The variant of each experiment of [record], by experiment id; the last description of an id wins,
/// as in `J:abt/experiment.ts:47-55`. An id that fails [isValidExperimentId], and every experiment after
/// the first [maxStoredExperiments] ids, is left out and reported to [onDrop].
Map<String, String> activeExperiments(
  TemplateRecord? record,
  DropReporter onDrop,
) {
  final Map<String, String> result = <String, String>{};
  if (record == null) {
    return result;
  }
  for (final Map<String, Object?> experiment in record.experimentDescriptions) {
    // The template parser keeps only descriptions with string ids and variants.
    final String id = experiment['experimentId']! as String;
    final String variant = experiment['variantId']! as String;
    if (!isValidExperimentId(id)) {
      onDrop('experiment id');
      continue;
    }
    if (!result.containsKey(id) && result.length >= maxStoredExperiments) {
      onDrop('experiment over the limit of $maxStoredExperiments');
      continue;
    }
    result[id] = variant;
  }
  return result;
}

/// The user properties for [current] (experiment id to variant id) after [previous] (the ids handed
/// over before): the variant of each current experiment, and null for each previous one that is gone.
Map<String, String?> experimentProperties(
  Map<String, String> current,
  Set<String> previous,
) {
  return <String, String?>{
    for (final MapEntry<String, String> entry in current.entries)
      '$experimentPropertyPrefix${entry.key}': entry.value,
    for (final String id in previous)
      if (!current.containsKey(id)) '$experimentPropertyPrefix$id': null,
  };
}
