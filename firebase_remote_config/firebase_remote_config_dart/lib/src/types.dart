import 'package:meta/meta.dart';

/// What a successful `FirebaseRemoteConfig.fetch` did.
enum FetchResult {
  /// The server sent a template, now stored as the fetched record; `activate` makes it visible.
  updated,

  /// The server said the stored template is current.
  unchanged,

  /// No request was sent: the last successful fetch is younger than the minimum fetch interval.
  cached,
}

/// The outcome of the last fetch, as `RemoteConfigInfo.lastFetchStatus` reports it.
enum RemoteConfigFetchStatus {
  /// No fetch has completed on this store.
  noFetchYet,

  /// The last fetch succeeded (a cached answer counts).
  success,

  /// The last fetch failed.
  failure,

  /// The last fetch was refused by the throttle, locally or with a 429 from the server.
  throttled,
}

/// The state of the fetches and templates of a `FirebaseRemoteConfig`.
@immutable
final class RemoteConfigInfo {
  /// Creates the state; the package creates them.
  const RemoteConfigInfo({
    required this.lastFetchStatus,
    this.lastSuccessfulFetchTime,
    this.throttledUntil,
    this.activeTemplateVersion,
    this.fetchedTemplateVersion,
  });

  /// The outcome of the last fetch.
  final RemoteConfigFetchStatus lastFetchStatus;

  /// When the last fetch that reached the server succeeded; an answer from the cache does not change it.
  final DateTime? lastSuccessfulFetchTime;

  /// The end of the current throttle window, or null when there is none or it has ended.
  final DateTime? throttledUntil;

  /// The template version of the active record, when the server gave one.
  final int? activeTemplateVersion;

  /// The template version of the fetched record, when the server gave one.
  final int? fetchedTemplateVersion;

  @override
  bool operator ==(Object other) =>
      other is RemoteConfigInfo &&
      other.lastFetchStatus == lastFetchStatus &&
      other.lastSuccessfulFetchTime == lastSuccessfulFetchTime &&
      other.throttledUntil == throttledUntil &&
      other.activeTemplateVersion == activeTemplateVersion &&
      other.fetchedTemplateVersion == fetchedTemplateVersion;

  @override
  int get hashCode => Object.hash(
    lastFetchStatus,
    lastSuccessfulFetchTime,
    throttledUntil,
    activeTemplateVersion,
    fetchedTemplateVersion,
  );

  @override
  String toString() =>
      'RemoteConfigInfo(${lastFetchStatus.name}, '
      'lastSuccessfulFetchTime: $lastSuccessfulFetchTime, throttledUntil: $throttledUntil, '
      'active: $activeTemplateVersion, fetched: $fetchedTemplateVersion)';
}

/// An event of `FirebaseRemoteConfig.onConfigUpdated`: a newer template was fetched, and these keys
/// differ from the active template. Call `activate` to make them visible.
@immutable
final class RemoteConfigUpdate {
  /// Creates an event for [updatedKeys]; the set is copied into an unmodifiable one.
  RemoteConfigUpdate(Set<String> updatedKeys)
    : updatedKeys = Set<String>.unmodifiable(updatedKeys);

  /// The keys whose value or metadata differ between the active and the newly fetched template.
  final Set<String> updatedKeys;

  @override
  String toString() => 'RemoteConfigUpdate(${updatedKeys.length} keys)';
}

/// One rollout assigned to this installation in the active template, as Android's `RolloutAssignment`
/// gives it to Crashlytics. Events of `FirebaseRemoteConfig.onRolloutsStateChanged` hold a set of them.
@immutable
final class RolloutAssignment {
  /// Creates an assignment; the package creates them.
  const RolloutAssignment({
    required this.rolloutId,
    required this.variantId,
    required this.parameterKey,
    required this.parameterValue,
    required this.templateVersion,
  });

  /// The id of the rollout.
  final String rolloutId;

  /// The variant of the rollout this installation is in.
  final String variantId;

  /// The first parameter key the rollout affects, or `''` when it names none.
  final String parameterKey;

  /// The value of [parameterKey] as `getString` reads it: active, else default, else `''`.
  final String parameterValue;

  /// The template version of the active record, or 0 when it has none.
  final int templateVersion;

  @override
  bool operator ==(Object other) =>
      other is RolloutAssignment &&
      other.rolloutId == rolloutId &&
      other.variantId == variantId &&
      other.parameterKey == parameterKey &&
      other.parameterValue == parameterValue &&
      other.templateVersion == templateVersion;

  @override
  int get hashCode => Object.hash(
    rolloutId,
    variantId,
    parameterKey,
    parameterValue,
    templateVersion,
  );

  /// Prints the ids and the version, never the parameter value.
  @override
  String toString() =>
      'RolloutAssignment($rolloutId, $variantId, version: $templateVersion)';
}
