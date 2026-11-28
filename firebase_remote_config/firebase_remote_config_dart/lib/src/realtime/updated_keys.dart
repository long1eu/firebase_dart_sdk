import 'package:collection/collection.dart';
import 'package:firebase_remote_config_dart/src/template.dart';

const DeepCollectionEquality _equality = DeepCollectionEquality();

/// The keys that differ between [active] and [fetched] (5.9.4; iOS, `IOS-RC/RCNConfigContent.m:589-682`).
///
/// Over the union of their keys, a key is updated when it exists in only one; its value differs; its
/// personalization entry is in only one or differs; its rollout assignments differ; or the experiments
/// affecting it differ in `experimentId`, `variantId`, `timeToLiveMillis` or `triggerTimeoutMillis`.
/// Comparison is structural. A missing record counts as an empty one.
Set<String> updatedKeys(TemplateRecord? active, TemplateRecord? fetched) {
  final _View before = _View(active);
  final _View after = _View(fetched);
  final Set<String> keys = <String>{...before.keys, ...after.keys};
  final Set<String> result = <String>{};
  for (final String key in keys) {
    if (_differs(before, after, key)) {
      result.add(key);
    }
  }
  return result;
}

bool _differs(_View before, _View after, String key) {
  final Map<String, String> beforeEntries = before.entries;
  final Map<String, String> afterEntries = after.entries;
  if (beforeEntries.containsKey(key) != afterEntries.containsKey(key) ||
      beforeEntries[key] != afterEntries[key]) {
    return true;
  }
  final Map<String, Map<String, Object?>> beforeP = before.personalization;
  final Map<String, Map<String, Object?>> afterP = after.personalization;
  if (beforeP.containsKey(key) != afterP.containsKey(key) ||
      !_equality.equals(beforeP[key], afterP[key])) {
    return true;
  }
  if (!_equality.equals(before.rollouts[key], after.rollouts[key])) {
    return true;
  }
  return !_equality.equals(before.experiments[key], after.experiments[key]);
}

/// The per-key views of one record.
final class _View {
  _View(TemplateRecord? record)
    : entries = record?.entries ?? const <String, String>{},
      personalization =
          record?.personalizationMetadata ??
          const <String, Map<String, Object?>>{},
      rollouts = _rollouts(record),
      experiments = _experiments(record);

  final Map<String, String> entries;
  final Map<String, Map<String, Object?>> personalization;

  /// Key to `rolloutId → variantId` of the rollouts that affect it.
  final Map<String, Map<String, String>> rollouts;

  /// Key to the set of compared experiment fields of the experiments that affect it.
  final Map<String, Set<String>> experiments;

  Iterable<String> get keys sync* {
    yield* entries.keys;
    yield* personalization.keys;
    yield* rollouts.keys;
    yield* experiments.keys;
  }

  static Map<String, Map<String, String>> _rollouts(TemplateRecord? record) {
    final Map<String, Map<String, String>> result =
        <String, Map<String, String>>{};
    for (final Map<String, Object?> rollout
        in record?.rolloutMetadata ?? const <Map<String, Object?>>[]) {
      final Object? keys = rollout['affectedParameterKeys'];
      if (keys is! List<String>) {
        continue;
      }
      for (final String key in keys) {
        (result[key] ??= <String, String>{})[rollout['rolloutId']! as String] =
            rollout['variantId']! as String;
      }
    }
    return result;
  }

  static Map<String, Set<String>> _experiments(TemplateRecord? record) {
    final Map<String, Set<String>> result = <String, Set<String>>{};
    for (final Map<String, Object?> experiment
        in record?.experimentDescriptions ?? const <Map<String, Object?>>[]) {
      final String id = experiment['experimentId']! as String;
      final Object? keys = experiment['affectedParameterKeys'];
      if (keys is! List<String> || id.startsWith('_exp_rollout')) {
        continue;
      }
      // One string per experiment, built from the compared fields only; a set ignores order.
      final String signature = <Object?>[
        id,
        experiment['variantId'],
        experiment['timeToLiveMillis'],
        experiment['triggerTimeoutMillis'],
      ].join('\u0000');
      for (final String key in keys) {
        (result[key] ??= <String>{}).add(signature);
      }
    }
    return result;
  }
}
