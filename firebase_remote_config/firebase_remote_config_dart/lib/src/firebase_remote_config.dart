import 'dart:async';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_installations_dart/firebase_installations_dart.dart';
import 'package:firebase_remote_config_dart/src/custom_signals.dart';
import 'package:firebase_remote_config_dart/src/exception.dart';
import 'package:firebase_remote_config_dart/src/experiments.dart';
import 'package:firebase_remote_config_dart/src/fetch_client.dart';
import 'package:firebase_remote_config_dart/src/http_rules.dart';
import 'package:firebase_remote_config_dart/src/log_once.dart';
import 'package:firebase_remote_config_dart/src/logger.dart';
import 'package:firebase_remote_config_dart/src/platform.dart';
import 'package:firebase_remote_config_dart/src/realtime/realtime_client.dart';
import 'package:firebase_remote_config_dart/src/records.dart';
import 'package:firebase_remote_config_dart/src/template.dart';
import 'package:firebase_remote_config_dart/src/throttle.dart';
import 'package:firebase_remote_config_dart/src/types.dart';
import 'package:firebase_remote_config_dart/src/value.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

/// Remote Config for one [FirebaseApp]: fetches the template the server evaluated for this installation,
/// keeps it in the store of [installations], and answers reads from the activated template and the
/// [defaults].
///
/// ```dart
/// final FirebaseRemoteConfig remoteConfig = FirebaseRemoteConfig(
///   app,
///   installations: installations,
///   defaults: <String, Object>{'welcome': 'Hello'},
/// );
/// await remoteConfig.fetchAndActivate();
/// print(remoteConfig.getString('welcome'));
/// await remoteConfig.close();
/// ```
///
/// Reads are synchronous and never fail: before the stored records are loaded ([isInitialized]) and
/// for keys the server did not send, they answer from [defaults], else with a static value (`''`,
/// `false`, `0`, `0.0`). [fetch] stores a new template as the fetched record; [activate] makes it the
/// one reads use. Listening to [onConfigUpdated] opens a realtime stream that fetches each newer
/// template as soon as it is published.
class FirebaseRemoteConfig {
  /// Starts loading the records from installations.store. Sends nothing.
  ///
  /// Throws [FirebaseRemoteConfigException] (`invalid-app-config`) when projectId, apiKey or appId is
  /// missing; [ArgumentError] for an empty default key, a default value that is not String, bool, int or
  /// finite double, a negative interval or timeout, or a bad origin.
  ///
  /// [httpClient] is closed by [close] only when this instance created it. [languageCode] overrides the
  /// language of the process (5.6); an empty or blank one sends `en`. [logger] receives messages without values or tokens.
  /// [analytics] receives the experiments of each template [activate] makes active (A42); without it
  /// the A/B testing hand-off is skipped with one warning.
  FirebaseRemoteConfig(
    this.app, {
    required this.installations,
    Map<String, Object> defaults = const <String, Object>{},
    this.minimumFetchInterval = const Duration(hours: 12),
    this.fetchTimeout = const Duration(seconds: 60),
    String? languageCode,
    http.Client? httpClient,
    RemoteConfigLogger? logger,
    RemoteConfigAnalytics? analytics,
    @visibleForTesting Uri? serverOrigin,
    @visibleForTesting Uri? realtimeOrigin,
    @visibleForTesting DateTime Function()? clock,
    @visibleForTesting double Function()? random,
    @visibleForTesting Future<void> Function(Duration duration)? delay,
  }) : defaults = _checkDefaults(defaults),
       _ownsClient = httpClient == null,
       _client = httpClient ?? http.Client(),
       _logger = logger,
       _analytics = analytics,
       _clock = clock ?? DateTime.now,
       _random = random ?? math.Random().nextDouble,
       _languageCode = _language(languageCode),
       _keyPrefix = 'remote_config/${app.persistenceKey}/' {
    _checkOptions(app.options);
    _checkDuration(minimumFetchInterval, 'minimumFetchInterval');
    _checkDuration(fetchTimeout, 'fetchTimeout');
    _store = installations.store;
    _logOnce = LogOnce(
      logger == null
          ? null
          : (String message) => logger(RemoteConfigLogLevel.warning, message),
    );
    _fetchClient = FetchClient(
      client: _client,
      origin: checkOrigin(
        serverOrigin ??
            Uri.parse('https://firebaseremoteconfig.googleapis.com'),
      ),
      projectId: app.options.projectId!,
      apiKey: app.options.apiKey,
      appId: app.options.appId,
      extraHeaders: installations.headers,
      clock: _clock,
      onDrop: _reportDrop,
    );
    _initialization = _load();
    // A failed load is reported by ensureInitialized and the calls that wait for it.
    _initialization.ignore();
    _realtime = RealtimeClient(
      options: app.options,
      installations: installations,
      fetchForRealtime: _fetchForRealtime,
      templates: () => (active: _active, fetched: _fetched),
      isInBackground: () => app.onBackgroundChanged.value,
      backgroundChanged: app.onBackgroundChanged,
      networkConnected: app.onNetworkConnected,
      visibility: createVisibility(),
      httpClient: _client,
      origin: checkOrigin(
        realtimeOrigin ??
            Uri.parse('https://firebaseremoteconfigrealtime.googleapis.com'),
      ),
      clock: _clock,
      random: _random,
      delay: delay,
      logger: logger,
      ready: _initialization,
      onBackoffChanged: _onRealtimeBackoff,
    );
    _subscriptions.add(installations.onIdChange.listen(_onIdChange));
    _subscriptions.add(
      app.onDeleteApp.listen((String _) => unawaited(close())),
    );
  }

  /// The app whose project this instance fetches for.
  final FirebaseApp app;

  /// The Installations instance that gives the installation id and token, and whose store keeps the
  /// records. [close] does not close it.
  final FirebaseInstallations installations;

  /// The interval within which [fetch] answers from the cache, unless a call gives its own.
  final Duration minimumFetchInterval;

  /// The deadline of a [fetch] call, unless a call gives its own.
  final Duration fetchTimeout;

  /// The defaults, as values with source [ValueSource.valueDefault]. Unmodifiable.
  final Map<String, RemoteConfigValue> defaults;

  final bool _ownsClient;
  final http.Client _client;
  final RemoteConfigLogger? _logger;
  final RemoteConfigAnalytics? _analytics;
  final DateTime Function() _clock;
  final double Function() _random;
  final String _languageCode;
  final String _keyPrefix;
  final Completer<void> _closedSignal = Completer<void>();
  final List<StreamSubscription<Object?>> _subscriptions =
      <StreamSubscription<Object?>>[];
  final StreamController<void> _activated = StreamController<void>.broadcast();
  final Set<MultiStreamController<Set<RolloutAssignment>>> _rolloutListeners =
      <MultiStreamController<Set<RolloutAssignment>>>{};
  late final KeyValueStore _store;
  late final LogOnce _logOnce;
  late final FetchClient _fetchClient;
  late final RealtimeClient _realtime;
  late final Future<void> _initialization;

  bool _initialized = false;
  bool _closed = false;
  TemplateRecord? _active;
  TemplateRecord? _fetched;
  MetaRecord _meta = const MetaRecord();
  ThrottleRecord _throttle = const ThrottleRecord();
  Map<String, String> _signals = const <String, String>{};
  String? _requestFid;
  bool _staleIfRequestFails = false;
  _InFlight? _inFlight;
  Future<void>? _resetting;
  Future<void>? _clearing;
  int _resetGeneration = 0;
  Set<RolloutAssignment> _rollouts = const <RolloutAssignment>{};
  // The A/B testing hand-offs of activate and reset run one at a time, in call order.
  Future<void> _experimentsTail = Future<void>.value();
  Future<void> _backoffTail = Future<void>.value();

  /// Completes when the stored records are loaded. Started by the constructor and memoized; it fails
  /// only when the store cannot start (`storage-error`).
  Future<void> ensureInitialized() => _initialization;

  /// True once the stored records are loaded.
  bool get isInitialized => _initialized;

  /// Fetches the template of this installation and stores it as the fetched record (5.5).
  ///
  /// Answers [FetchResult.cached] without a request while the last successful fetch is younger than
  /// [minimumFetchInterval] (this call's, else the constructor's), unless custom signals or the
  /// installation changed since. Inside a throttle window it throws `fetch-throttle` at once and sends
  /// nothing. [timeout] (else [fetchTimeout]) covers the whole call, Installations included. Calls made
  /// while one is in flight share its result, unless custom signals or the installation changed since
  /// that request was built (it then waits and sends its own); a realtime retry, which sends no
  /// `If-None-Match`, never joins a request that sends one.
  Future<FetchResult> fetch({
    Duration? minimumFetchInterval,
    Duration? timeout,
  }) async {
    _checkDuration(minimumFetchInterval, 'minimumFetchInterval');
    _checkDuration(timeout, 'timeout');
    return _fetch(
      interval: minimumFetchInterval ?? this.minimumFetchInterval,
      timeout: timeout ?? fetchTimeout,
      fetchType: 'BASE/1',
    );
  }

  /// Makes the fetched record the active one (5.5). Returns true when it did; false when there is no
  /// fetched record, it is already active (the same fetch time), or the active record is kept: both
  /// have a template version, the active one's is higher, its fetch time is not in the future, and it
  /// was fetched at most 24 h before the fetched record. Otherwise the fetched record replaces it; a
  /// record without a version therefore replaces any other fetch. A `NO_TEMPLATE` or `EMPTY_CONFIG`
  /// record keeps the version the server sent, if any.
  ///
  /// The fetched record is the newer of the stored one and the one in memory (the higher version when
  /// both have one, else the later fetch time; whichever exists when one is missing), except that a
  /// stored record with a fetch time in the future loses to a different template in memory (a
  /// different version, or the stored one has none). Memory with the same version is that stored
  /// record, clamped to now when it was loaded.
  ///
  /// A [reset] that starts while this call runs wins (A38): the call returns true only when its record
  /// is active in the store and in memory when it returns, and [onActivated] emits only then. A call
  /// whose record the reset removed returns false; one whose record survived a failed reset returns
  /// true.
  ///
  /// When it returns true, it first hands the experiments of the new active template to the
  /// `analytics` constructor argument (A42): one `setUserProperties` call with `firebase<experimentId>`
  /// set to the variant id for each experiment and to null for each experiment handed over before that
  /// is gone, then `logEvent('set_firebase_experiment_state')`; nothing when that map is empty. A
  /// failure of the hand-off, including the two calls not completing within [fetchTimeout] of the
  /// hand-off being queued, is logged and never fails this call; the next activate retries it.
  ///
  /// Throws `storage-error` when the store fails; memory is then unchanged.
  Future<bool> activate() async {
    _checkOpen();
    await _guard(_initialization, null);
    // Inline, so no await falls between the last check and reading the generation (A38).
    while (_resetting != null) {
      await _guard(_resetting!, null);
    }
    final int resetGeneration = _resetGeneration;
    final TemplateRecord? fetchedBefore = _fetched;
    // One `now` for every read below (A13): the fetched record is clamped to it, and the transform
    // compares the stored active record's time against it.
    final DateTime now = _clock();
    final String? storedText = await _storeCall(
      () => _store.read(_key('fetched')),
    );
    final TemplateRecord? storedRaw = TemplateRecord.tryParse(
      storedText,
      onDrop: _reportDrop,
    );
    // A stored record fetched "in the future" is corrupt or tampered (A21): another record in memory
    // wins over it. Memory holding that same template (same version) is the record itself, clamped
    // when it was loaded, so the clamped stored record is used and activate stays idempotent.
    final TemplateRecord? memory = _fetched;
    final bool memoryWins =
        storedRaw != null &&
        memory != null &&
        storedRaw.fetchTime.isAfter(now) &&
        (storedRaw.templateVersion == null ||
            storedRaw.templateVersion != memory.templateVersion);
    final TemplateRecord? fetched = memoryWins
        ? memory
        : _newer(TemplateRecord.tryParse(storedText, now: now), memory);
    if (fetched == null) {
      return false;
    }
    final String fetchedText = fetched.encode();
    bool wrote = false;
    final String? result = await _storeCall(
      () => _store.update(_key('active'), (String? current) {
        // A reset started since this call began: the record it read belongs to the cleared state.
        if (resetGeneration != _resetGeneration) {
          wrote = false;
          return current;
        }
        // Not clamped: _keepsActive replaces an active record with a future fetch time.
        final TemplateRecord? active = TemplateRecord.tryParse(current);
        if (active != null && _keepsActive(active, fetched, now)) {
          wrote = false;
          return current;
        }
        wrote = true;
        return fetchedText;
      }),
    );
    _checkOpen();
    int generation = resetGeneration;
    String? activeText = result;
    // A reset started during the update. When this call wrote the store, its record counts only if
    // the reset failed before removing it; memory then takes it.
    if (generation != _resetGeneration) {
      if (!wrote) {
        return false;
      }
      final int? survived = await _survivedResets(fetchedText);
      if (survived == null) {
        return false;
      }
      _checkOpen();
      generation = survived;
      activeText = fetchedText;
    }
    _active = TemplateRecord.tryParse(
      activeText,
      onDrop: _reportDrop,
      now: now,
    );
    // A fetch that completed during the update stored a newer record; keep it.
    if (identical(_fetched, fetchedBefore)) {
      _fetched = fetched;
    }
    _updateRollouts();
    if (!wrote) {
      return false;
    }
    await _handOffExperiments(_active, generation);
    // A reset that started during the hand-off clears this record unless it fails. Its start made the
    // hand-off skip, and a failed reset never cleared the experiments, so the hand-off runs again for
    // the record that survived (A42).
    while (generation != _resetGeneration) {
      final int? survived = await _survivedResets(fetchedText);
      if (survived == null) {
        return false;
      }
      generation = survived;
      await _handOffExperiments(_active, generation);
    }
    if (!_closed) {
      _activated.add(null);
    }
    return true;
  }

  /// Clears the fetched and the active template, the fetch state ([info]) and the throttle, in memory
  /// and in the store (Android's `reset`, `A:FirebaseRemoteConfig.java:549-561`). The [defaults], the
  /// custom signals and the realtime backoff stay.
  ///
  /// It waits for a fetch in flight to settle; fetches, activates and other resets called meanwhile
  /// wait for it, and custom-signal and ID-change updates of the fetch state wait while it clears. An
  /// [activate] already running returns false unless this reset fails before removing its record (see
  /// [activate]). Afterwards reads answer from
  /// [defaults], [info] is as before the first fetch, the next [fetch] sends a request without
  /// `If-None-Match`, and an open realtime stream stays open: its next connect announces version 0, so
  /// the server's current template is fetched (not activated). [onActivated] does not emit;
  /// [onRolloutsStateChanged] emits an empty set when rollouts were active.
  ///
  /// It also clears the experiments handed to `analytics` (A42): after a hand-off of an [activate] in
  /// progress, it sends `firebase<experimentId>` = null for each of them and logs
  /// `set_firebase_experiment_state`, then removes the stored set. When that hand-off fails, the set
  /// stays stored, so the next [activate] clears what is gone.
  ///
  /// Throws `storage-error` when the store fails; memory is then unchanged, and the records cleared
  /// before the failure stay cleared in the store.
  Future<void> reset() async {
    _checkOpen();
    await _guard(_initialization, null);
    // Resets run one at a time. Inline, so no await falls between the last check and taking the slot.
    while (_resetting != null) {
      await _guard(_resetting!, null);
    }
    final Completer<void> done = Completer<void>();
    final Completer<void> clearing = Completer<void>();
    _resetting = done.future;
    // Every activate that began before this point now counts only if this reset fails (A38).
    _resetGeneration++;
    try {
      await _waitForFetches();
      // From here, meta and throttle updates (custom signals, an ID change) wait for the end.
      _clearing = clearing.future;
      for (final String name in const <String>[
        'fetched',
        'active',
        'meta',
        'throttle',
      ]) {
        _checkOpen();
        await _storeCall(() => _store.update(_key(name), (String? _) => null));
      }
      await _clearExperiments();
      _checkOpen();
      _fetched = null;
      _active = null;
      _meta = const MetaRecord();
      _throttle = const ThrottleRecord();
      _staleIfRequestFails = false;
      _updateRollouts();
    } finally {
      if (identical(_clearing, clearing.future)) {
        _clearing = null;
      }
      clearing.complete();
      if (identical(_resetting, done.future)) {
        _resetting = null;
      }
      done.complete();
    }
  }

  /// Emits after each [activate] that returned true (iOS's `FIRRemoteConfigActivateNotification`,
  /// `I:FIRRemoteConfig.m:482-493`). A broadcast stream; it ends at [close].
  Stream<void> get onActivated => _activated.stream;

  /// The rollouts assigned to this installation in the active template (Android's
  /// `RolloutsStateSubscriptionsHandler`, `AI:rollouts/RolloutsStateSubscriptionsHandler.java:53-95`).
  ///
  /// Each listener first gets the current set once the stored records are loaded (an empty set when
  /// nothing is active, nothing when the load fails), then a new set after each [activate] or [reset]
  /// that changes it. One [RolloutAssignment] per rollout, for its first affected parameter. A broadcast
  /// stream; it ends at [close].
  Stream<Set<RolloutAssignment>> get onRolloutsStateChanged =>
      Stream<Set<RolloutAssignment>>.multi(
        _onRolloutsListen,
        isBroadcast: true,
      );

  /// [fetch], then [activate] after a successful fetch (including [FetchResult.cached] and
  /// [FetchResult.unchanged]); returns what [activate] returns.
  Future<bool> fetchAndActivate({
    Duration? minimumFetchInterval,
    Duration? timeout,
  }) async {
    await fetch(minimumFetchInterval: minimumFetchInterval, timeout: timeout);
    return activate();
  }

  /// The value of [key]: the active template's, else the default, else the static value (`''`).
  RemoteConfigValue getValue(String key) =>
      _remote(key) ?? defaults[key] ?? staticValue;

  /// The value of [key] from one [source] only (iOS's `configValueForKey:source:`): the active
  /// template's for [ValueSource.valueRemote], the default for [ValueSource.valueDefault]. When that
  /// source has no [key], and always for [ValueSource.valueStatic], the static value (`''`).
  RemoteConfigValue getValueFrom(String key, ValueSource source) {
    final RemoteConfigValue? value = switch (source) {
      ValueSource.valueRemote => _remote(key),
      ValueSource.valueDefault => defaults[key],
      ValueSource.valueStatic => null,
    };
    return value ?? staticValue;
  }

  /// The keys of the active template and the defaults that start with [prefix], without duplicates and
  /// sorted by UTF-16 code units (Android's `getKeysByPrefix`). An empty [prefix] gives every key.
  /// Unmodifiable.
  List<String> getKeysByPrefix(String prefix) {
    final List<String> keys = <String>[
      for (final String key in <String>{
        ...?_active?.entries.keys,
        ...defaults.keys,
      })
        if (key.startsWith(prefix)) key,
    ]..sort();
    return List<String>.unmodifiable(keys);
  }

  /// Every key of the active template and the defaults, each as [getValue] gives it.
  Map<String, RemoteConfigValue> getAll() {
    final Set<String> keys = <String>{
      ...?_active?.entries.keys,
      ...defaults.keys,
    };
    return <String, RemoteConfigValue>{
      for (final String key in keys) key: getValue(key),
    };
  }

  /// The active value of [key], else the default, else `''`.
  String getString(String key) => getValue(key).text;

  /// The active value of [key] if it is a boolean (see [RemoteConfigValue.asBool]), else the default if
  /// it is one, else false.
  bool getBool(String key) =>
      _convert(key, (RemoteConfigValue value) => value.asBool()) ?? false;

  /// The active value of [key] if it is an integer, else the default if it is one, else 0.
  int getInt(String key) =>
      _convert(key, (RemoteConfigValue value) => value.asInt()) ?? 0;

  /// The active value of [key] if it is a finite number, else the default if it is one, else 0.0.
  double getDouble(String key) =>
      _convert(key, (RemoteConfigValue value) => value.asDouble()) ?? 0.0;

  /// The state of the fetches and the template versions.
  RemoteConfigInfo get info => RemoteConfigInfo(
    lastFetchStatus: _meta.lastFetchStatus,
    lastSuccessfulFetchTime: _meta.lastSuccessfulFetchTime,
    throttledUntil: Throttle.isThrottled(_throttle, _clock())
        ? _throttle.until
        : null,
    activeTemplateVersion: _active?.templateVersion,
    fetchedTemplateVersion: _fetched?.templateVersion,
  );

  /// Merges [signals] into the stored custom signals (5.8); a null value removes its key. Values are
  /// `String`, `int` or finite `double`, sent as text on every fetch.
  ///
  /// Throws an [ArgumentError] naming the limit and the entry's position when a key is not 1-250
  /// characters, a string is over 500 characters, a value has another type, or more than 100 signals
  /// would remain; nothing is stored then. Throws `storage-error` when the store fails. A change makes
  /// the next [fetch] skip the cache.
  Future<void> setCustomSignals(Map<String, Object?> signals) async {
    _checkOpen();
    final Map<String, String?> changes = normalizeSignalChanges(signals);
    await _guard(_initialization, null);
    bool tooMany = false;
    bool changed = false;
    final String? result = await _storeCall(
      () => _store.update(_key('signals'), (String? current) {
        final Map<String, String> stored =
            SignalsRecord.tryParse(current)?.signals ??
            const <String, String>{};
        final Map<String, String> merged = mergeSignals(stored, changes);
        tooMany = merged.length > maxSignals;
        changed = !_sameMap(stored, merged);
        if (tooMany || !changed) {
          return current;
        }
        return SignalsRecord(merged).encode();
      }),
    );
    if (tooMany) {
      throw ArgumentError(
        'More than $maxSignals custom signals would remain after the merge.',
      );
    }
    _checkOpen();
    _signals =
        SignalsRecord.tryParse(result)?.signals ?? const <String, String>{};
    if (changed) {
      await _updateMeta((MetaRecord meta) => meta.incrementStale());
    }
  }

  /// The stored custom signals. Unmodifiable.
  Map<String, String> get customSignals =>
      Map<String, String>.unmodifiable(_signals);

  /// Realtime updates (5.9): while it has a listener, the instance is open and the app is in the
  /// foreground, a stream to the server announces newer templates; each is fetched (not activated) and
  /// an event names the keys that differ from the active template.
  ///
  /// Errors on the stream are [FirebaseRemoteConfigException]s (`stream-error`, `realtime-unavailable`,
  /// `update-message-invalid`, `update-not-fetched`). Only `realtime-unavailable` ends it; do not use
  /// `cancelOnError` if you want to keep receiving updates after an error.
  Stream<RemoteConfigUpdate> get onConfigUpdated => _realtime.stream;

  /// Ends [onConfigUpdated], aborts the realtime stream and any request, and closes the HTTP client if
  /// this instance created it. Idempotent. Later async calls fail with `remote-config-closed`; reads keep
  /// answering from memory. It does not close [installations].
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _closedSignal.complete();
    _fetchClient.abortAll();
    // Not awaited: cancelling takes effect at once, and the returned futures can complete outside the
    // caller's zone (fake_async tests never see them complete).
    for (final StreamSubscription<Object?> subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    // Not awaited: closing a controller without a listener never completes.
    unawaited(_activated.close());
    final List<MultiStreamController<Set<RolloutAssignment>>> rolloutListeners =
        _rolloutListeners.toList();
    _rolloutListeners.clear();
    for (final MultiStreamController<Set<RolloutAssignment>> listener
        in rolloutListeners) {
      unawaited(listener.close());
    }
    await _realtime.close();
    if (_ownsClient) {
      _client.close();
    }
  }

  /// Attempts 2 and 3 of an auto-fetch chain send no `If-None-Match`: the server then answers with the
  /// whole template and its version, so a publish that left this client's values as they were still
  /// brings the chain to the announced version.
  Future<FetchResult> _fetchForRealtime(int attempt) => _fetch(
    interval: Duration.zero,
    timeout: fetchTimeout,
    fetchType: 'REALTIME/$attempt',
    etagAllowed: attempt == 1,
  );

  Future<FetchResult> _fetch({
    required Duration interval,
    required Duration timeout,
    required String fetchType,
    bool etagAllowed = true,
  }) async {
    _checkOpen();
    final DateTime deadline = _clock().add(timeout);
    await _guard(_initialization, deadline);
    while (true) {
      _checkOpen();
      // A reset in progress clears what this request would build on; it starts after the reset.
      final Future<void>? resetting = _resetting;
      if (resetting != null) {
        await _guard(resetting, deadline);
        continue;
      }
      final _InFlight? inFlight = _inFlight;
      if (inFlight == null) {
        break;
      }
      final int? built = inFlight.generation;
      // A request still waiting for Installations reads the generation afterwards, so it covers any
      // change made so far. A call that must go without an ETag joins only a request without one.
      if ((built == null || built == _meta.staleGeneration) &&
          (etagAllowed || !inFlight.etagAllowed)) {
        return _guard(inFlight.future, deadline);
      }
      // Built before the stale generation changed, or with an ETag this call must not send: wait for
      // it, then send a request of our own.
      await _guard(
        inFlight.future.then<void>((FetchResult _) {}, onError: (Object _) {}),
        deadline,
      );
    }
    final _InFlight inFlight = _InFlight(
      _meta.staleGeneration,
      etagAllowed: etagAllowed,
    );
    inFlight.future = _fetchOnce(interval, deadline, fetchType, inFlight);
    _inFlight = inFlight;
    try {
      return await inFlight.future;
    } finally {
      if (identical(_inFlight, inFlight)) {
        _inFlight = null;
      }
    }
  }

  Future<FetchResult> _fetchOnce(
    Duration interval,
    DateTime deadline,
    String fetchType,
    _InFlight inFlight,
  ) async {
    final int? generation = inFlight.generation;
    final DateTime now = _clock();
    final DateTime? last = _meta.lastSuccessfulFetchTime;
    // A negative age (the clock moved back) counts as expired.
    final Duration? age = last == null ? null : now.difference(last);
    if ((_active != null || _fetched != null) &&
        generation == 0 &&
        age != null &&
        !age.isNegative &&
        age < interval) {
      await _updateMeta(
        (MetaRecord meta) =>
            meta.copyWith(lastFetchStatus: RemoteConfigFetchStatus.success),
      );
      return FetchResult.cached;
    }
    if (Throttle.isThrottled(_throttle, now)) {
      await _setStatus(RemoteConfigFetchStatus.throttled);
      throw FirebaseRemoteConfigException(
        code: 'fetch-throttle',
        message: 'Fetches are throttled after earlier failures.',
        throttledUntil: _throttle.until,
      );
    }
    try {
      return await _request(deadline, fetchType, inFlight);
    } on FirebaseRemoteConfigException catch (error) {
      if (error.code != 'remote-config-closed') {
        await _setStatus(
          error.code == 'fetch-throttle'
              ? RemoteConfigFetchStatus.throttled
              : RemoteConfigFetchStatus.failure,
        );
      }
      rethrow;
    }
  }

  Future<FetchResult> _request(
    DateTime deadline,
    String fetchType,
    _InFlight inFlight,
  ) async {
    // The generation is read after Installations returns (A8); until then every caller may join.
    inFlight.generation = null;
    final ({String id, String token}) installation;
    try {
      installation = await _guard(installations.getIdAndToken(), deadline);
    } on FirebaseRemoteConfigException {
      rethrow;
    } catch (error) {
      throw FirebaseRemoteConfigException(
        code: 'installations-error',
        message: 'Getting the installation id and token failed.',
        cause: error,
      );
    }
    _requestFid = installation.id;
    bool succeeded = false;
    try {
      final FetchResult result = await _send(
        installation,
        deadline,
        fetchType,
        inFlight,
      );
      succeeded = true;
      return result;
    } finally {
      _requestFid = null;
      // An ID change to this request's FID was left to its success; without one, the cache is stale.
      if (_staleIfRequestFails) {
        _staleIfRequestFails = false;
        if (!succeeded && !_closed) {
          await _updateMeta((MetaRecord meta) => meta.incrementStale());
        }
      }
    }
  }

  Future<FetchResult> _send(
    ({String id, String token}) installation,
    DateTime deadline,
    String fetchType,
    _InFlight inFlight,
  ) async {
    final Duration left = deadline.difference(_clock());
    if (left <= Duration.zero) {
      throw _timeout();
    }
    // Read after Installations returns, so the FID, the signals and the generation belong to the same
    // moment. The ETag goes only with the FID whose last successful fetch stored it.
    final int generation = _meta.staleGeneration;
    inFlight.generation = generation;
    final bool sendEtag =
        inFlight.etagAllowed && generation == 0 && _meta.fid == installation.id;
    // 5.5: the ETag stored in the fetched record, else the one in the active record.
    final String? etag = _fetched?.etag ?? _active?.etag;
    final DateTime sentAt = _clock();
    final FetchOutcome outcome = await _fetchClient.fetch(
      FetchRequest(
        installationId: installation.id,
        installationToken: installation.token,
        languageCode: _languageCode,
        customSignals: _signals,
        fetchType: fetchType,
        deadline: left,
        etag: sendEtag ? etag : null,
      ),
    );
    _checkOpen();
    switch (outcome) {
      case FetchUpdated(:final TemplateRecord record):
        await _storeFetched(record, sentAt);
        await _afterSuccess(generation, installation.id);
        _log(
          RemoteConfigLogLevel.info,
          'Fetched template version ${record.templateVersion ?? 'none'}.',
        );
        return FetchResult.updated;
      case FetchUnchanged():
        await _afterSuccess(generation, installation.id);
        _log(RemoteConfigLogLevel.debug, 'The fetched template is current.');
        return FetchResult.unchanged;
      case FetchFailed(:final FirebaseRemoteConfigException error):
        throw await _afterFailure(error);
    }
  }

  /// Writes [record], the answer to a request sent at [sentAt], unless the stored record is a newer
  /// answer that another instance stored meanwhile (see [_keepsStored]).
  Future<void> _storeFetched(TemplateRecord record, DateTime sentAt) async {
    final String text = record.encode();
    try {
      final String? stored = await _store.update(_key('fetched'), (
        String? current,
      ) {
        // Not clamped (A13) here: A21 replaces a record with a future fetch time, and a clamp would turn
        // that time into now and let a tampered record be kept. A kept record is never in the future.
        final TemplateRecord? existing = TemplateRecord.tryParse(current);
        if (existing != null &&
            _keepsStored(existing, record, sentAt, _clock())) {
          return current;
        }
        return text;
      });
      _fetched =
          TemplateRecord.tryParse(stored, onDrop: _reportDrop, now: _clock()) ??
          record;
    } catch (error) {
      _writeFailed('fetched');
      _fetched = record;
    }
  }

  Future<void> _afterSuccess(int generation, String fid) async {
    final DateTime now = _clock();
    await _updateMeta(
      (MetaRecord meta) => meta.copyWith(
        lastFetchStatus: RemoteConfigFetchStatus.success,
        lastSuccessfulFetchTime: now,
        staleGeneration: meta.staleGeneration == generation ? 0 : null,
        fid: fid,
      ),
    );
    if (_throttle.count != 0 || _throttle.until != null) {
      await _updateThrottle((ThrottleRecord _) => const ThrottleRecord());
    }
  }

  Future<FirebaseRemoteConfigException> _afterFailure(
    FirebaseRemoteConfigException error,
  ) async {
    final int? status = error.httpStatus;
    if (status == null || !Throttle.isThrottlingStatus(status)) {
      return error;
    }
    final DateTime now = _clock();
    final double random = _random();
    await _updateThrottle(
      (ThrottleRecord record) => Throttle.afterFailure(record, now, random),
    );
    return error.withThrottle(_throttle.until ?? now);
  }

  Future<void> _setStatus(RemoteConfigFetchStatus status) =>
      _updateMeta((MetaRecord meta) => meta.copyWith(lastFetchStatus: status));

  Future<void> _updateMeta(MetaRecord Function(MetaRecord meta) change) async {
    // Checked first, so an update outside a reset keeps its timing (no extra microtask). The loop is
    // inline, so no await falls between the last check and the store call; after waiting, a closed
    // instance writes nothing.
    if (_clearing != null) {
      while (_clearing != null) {
        await _clearing;
      }
      if (_closed) {
        return;
      }
    }
    final DateTime now = _clock();
    try {
      final String? stored = await _store.update(_key('meta'), (
        String? current,
      ) {
        return change(MetaRecord.tryParse(current, now) ?? _meta).encode();
      });
      _meta = MetaRecord.tryParse(stored, now) ?? change(_meta);
    } catch (error) {
      _writeFailed('meta');
      _meta = change(_meta);
    }
  }

  Future<void> _updateThrottle(
    ThrottleRecord Function(ThrottleRecord record) change,
  ) async {
    // Checked first, so an update outside a reset keeps its timing (no extra microtask). The loop is
    // inline, so no await falls between the last check and the store call; after waiting, a closed
    // instance writes nothing.
    if (_clearing != null) {
      while (_clearing != null) {
        await _clearing;
      }
      if (_closed) {
        return;
      }
    }
    final DateTime now = _clock();
    try {
      final String? stored = await _store.update(_key('throttle'), (
        String? current,
      ) {
        return change(
          ThrottleRecord.tryParse(current, now) ?? _throttle,
        ).encode();
      });
      _throttle = ThrottleRecord.tryParse(stored, now) ?? change(_throttle);
    } catch (error) {
      _writeFailed('throttle');
      _throttle = change(_throttle);
    }
  }

  Future<void> _load() async {
    final List<String?> texts;
    try {
      texts = await Future.wait(<Future<String?>>[
        for (final String name in const <String>[
          'fetched',
          'active',
          'meta',
          'throttle',
          'signals',
          'realtime',
        ])
          _store.read(_key(name)),
      ]);
    } catch (error) {
      throw FirebaseRemoteConfigException(
        code: 'storage-error',
        message:
            'The store could not be read; Remote Config answers from defaults.',
        cause: error,
      );
    }
    final DateTime now = _clock();
    _fetched = _loaded(
      'fetched',
      texts[0],
      (String? text) => TemplateRecord.tryParse(text, now: now),
    );
    _active = _loaded(
      'active',
      texts[1],
      (String? text) => TemplateRecord.tryParse(text, now: now),
    );
    _meta =
        _loaded(
          'meta',
          texts[2],
          (String? text) => MetaRecord.tryParse(text, now),
        ) ??
        const MetaRecord();
    _throttle =
        _loaded(
          'throttle',
          texts[3],
          (String? text) => ThrottleRecord.tryParse(text, now),
        ) ??
        const ThrottleRecord();
    _signals =
        _loaded('signals', texts[4], SignalsRecord.tryParse)?.signals ??
        const <String, String>{};
    final RealtimeBackoffRecord? backoff = _loaded(
      'realtime',
      texts[5],
      (String? text) => RealtimeBackoffRecord.tryParse(text, now),
    );
    if (backoff != null) {
      _realtime.restoreBackoff(backoff);
    }
    _rollouts = _rolloutsOf(_active);
    _initialized = true;
  }

  T? _loaded<T>(String name, String? text, T? Function(String? text) parse) {
    if (text == null) {
      return null;
    }
    T? record;
    try {
      record = parse(text);
    } on Object {
      // The parsers return null for bad content; a throw is still a bad record, never a failed load.
      record = null;
    }
    if (record == null) {
      _logOnce(
        'load-$name',
        'The stored $name record could not be read; it is ignored.',
      );
    }
    return record;
  }

  /// After a [reset] started during an [activate]: waits for every reset to end and checks that the
  /// stored active record is still [text] (each reset failed before removing it). Returns the reset
  /// generation that held while no reset ran and the record was found, or null when it was removed
  /// or the read failed (a failed read counts as removed, A38).
  ///
  /// The generation is compared again after the caller resumes, a microtask later: a reset that took
  /// the slot in that gap starts the wait again, so it is never adopted.
  Future<int?> _survivedResets(String text) async {
    while (true) {
      final int? generation = await _survivedReset(text);
      if (generation == null || generation == _resetGeneration) {
        return generation;
      }
    }
  }

  Future<int?> _survivedReset(String text) async {
    while (true) {
      final Future<void>? resetting = _resetting;
      if (resetting != null) {
        await _guard(resetting, null);
        continue;
      }
      final String? stored;
      try {
        stored = await _store.read(_key('active'));
      } catch (error) {
        _logOnce(
          'store-call',
          'A store call failed; the operation changed nothing.',
        );
        return null;
      }
      if (_resetting == null) {
        return stored == text ? _resetGeneration : null;
      }
    }
  }

  /// Waits until no fetch is in flight, ignoring their results.
  Future<void> _waitForFetches() async {
    while (true) {
      final _InFlight? inFlight = _inFlight;
      if (inFlight == null) {
        return;
      }
      await _guard(
        inFlight.future.then<void>((FetchResult _) {}, onError: (Object _) {}),
        null,
      );
    }
  }

  /// Queues a store of the realtime backoff after the ones handed over before it; completes with true
  /// when it was stored.
  ///
  /// After [close] nothing is queued; a write that already reached the store may still finish.
  Future<bool> _onRealtimeBackoff(RealtimeBackoffRecord record) {
    if (_closed) {
      return Future<bool>.value(false);
    }
    final Future<bool> result = _backoffTail.then(
      (void _) => _storeRealtimeBackoff(record),
    );
    _backoffTail = result.then<void>((bool _) {});
    return result;
  }

  /// Stores the realtime backoff, or removes the record when it holds nothing. Returns false without
  /// writing once the instance is closed, so a queued store never lands after [close]; a failed write
  /// is logged once and returns false, and the realtime client hands the state over again on its next
  /// change.
  Future<bool> _storeRealtimeBackoff(RealtimeBackoffRecord record) async {
    if (_closed) {
      return false;
    }
    try {
      await _store.write(
        _key('realtime'),
        record.isEmpty ? null : record.encode(),
      );
      return true;
    } catch (error) {
      _writeFailed('realtime');
      return false;
    }
  }

  /// Runs [task] after the hand-offs queued before it.
  Future<void> _serialExperiments(Future<void> Function() task) {
    final Future<void> result = _experimentsTail.then((void _) => task());
    _experimentsTail = result.then<void>((void _) {}, onError: (Object _) {});
    return result;
  }

  /// The A/B testing hand-off of an [activate] that made [active] the active record (A42). It never
  /// throws: a store or connector failure is logged. After a connector failure the stored set is the
  /// union of the current and the previous ids, so the next activate sends every current variant again
  /// and clears every id that is gone by then, and a connector that always fails (an id Analytics
  /// refuses) costs one attempt per activate, not a growing backlog. Nothing is sent or stored once the
  /// instance is closed or a reset has started since the activate began.
  Future<void> _handOffExperiments(
    TemplateRecord? active,
    int resetGeneration,
  ) {
    // The deadline starts when the hand-off is queued, so a queue behind a hung connector holds this
    // call for at most fetchTimeout in all.
    final DateTime deadline = _clock().add(fetchTimeout);
    return _serialExperiments(() async {
      final Map<String, String> current = activeExperiments(
        active,
        _reportDrop,
      );
      final ({Set<String> ids, bool corrupt})? stored =
          await _readExperiments();
      if (stored == null || _closed || resetGeneration != _resetGeneration) {
        return;
      }
      final Set<String> previous = stored.ids;
      final Map<String, String?> properties = experimentProperties(
        current,
        previous,
      );
      final bool sent =
          properties.isEmpty || await _sendExperiments(properties, deadline);
      if (_closed) {
        return;
      }
      final Set<String> ids = sent
          ? current.keys.toSet()
          : _keptExperiments(current.keys, previous);
      // A corrupt record is rewritten even when the set did not change, so it is repaired.
      if (!stored.corrupt &&
          const SetEquality<String>().equals(ids, previous)) {
        return;
      }
      try {
        await _store.write(
          _key('experiments'),
          ids.isEmpty ? null : ExperimentsRecord(ids).encode(),
        );
      } catch (error) {
        _writeFailed('experiments');
      }
    });
  }

  /// [current] followed by the ids of [previous], up to [maxStoredExperiments].
  static Set<String> _keptExperiments(
    Iterable<String> current,
    Set<String> previous,
  ) {
    final Set<String> result = <String>{};
    for (final String id in <String>[...current, ...previous]) {
      if (result.length >= maxStoredExperiments) {
        break;
      }
      result.add(id);
    }
    return result;
  }

  /// The reset step of A42: clears the experiments handed over before, then removes the stored set.
  /// A failed hand-off keeps the set. Throws `storage-error` when the store fails, and
  /// `remote-config-closed` when the instance closed.
  Future<void> _clearExperiments() {
    final DateTime deadline = _clock().add(fetchTimeout);
    return _serialExperiments(() async {
      _checkOpen();
      final Set<String> previous =
          _parseExperiments(
            await _storeCall(() => _store.read(_key('experiments'))),
          ) ??
          const <String>{};
      _checkOpen();
      if (previous.isNotEmpty &&
          !await _sendExperiments(
            experimentProperties(const <String, String>{}, previous),
            deadline,
          )) {
        return;
      }
      _checkOpen();
      await _storeCall(() async {
        await _store.write(_key('experiments'), null);
        return null;
      });
    });
  }

  /// The stored experiment ids, and whether the record was bad (its ids are then empty); null when the
  /// store fails.
  Future<({Set<String> ids, bool corrupt})?> _readExperiments() async {
    final String? text;
    try {
      text = await _store.read(_key('experiments'));
    } catch (error) {
      _logOnce(
        'read-experiments',
        'The experiments record could not be read; the A/B testing hand-off is skipped.',
      );
      return null;
    }
    final Set<String>? ids = _parseExperiments(text);
    return (ids: ids ?? const <String>{}, corrupt: ids == null);
  }

  /// The ids of a stored record: empty when there is none, null (logged once) for a bad one.
  Set<String>? _parseExperiments(String? text) {
    if (text == null) {
      return const <String>{};
    }
    final ExperimentsRecord? record = ExperimentsRecord.tryParse(text);
    if (record == null) {
      _logOnce(
        'load-experiments',
        'The stored experiments record could not be read; it is ignored.',
      );
      return null;
    }
    return record.ids;
  }

  /// Sends [properties] and the experiment state event to the connector. Returns false when the
  /// connector failed, the two calls did not complete before [deadline] (set to [fetchTimeout] after
  /// the hand-off was queued; `fetch-timeout`, the connector's futures are then abandoned, and a
  /// deadline already past sends nothing) or the instance closed meanwhile; true when both calls
  /// completed, and when there is no connector (a warning is logged once).
  Future<bool> _sendExperiments(
    Map<String, String?> properties,
    DateTime deadline,
  ) async {
    final RemoteConfigAnalytics? analytics = _analytics;
    if (analytics == null) {
      _logOnce(
        'no-analytics',
        'Experiments are active but no analytics was given; the A/B testing hand-off is skipped.',
      );
      return true;
    }
    // One deadline for both calls, set when the hand-off was queued: a hung connector holds activate
    // and reset for at most fetchTimeout, queue included.
    if (!deadline.isAfter(_clock())) {
      _logOnce(
        'analytics-queue-timeout',
        'An A/B testing hand-off waited past its deadline behind an earlier one; the next activate '
            'sends it again.',
      );
      return false;
    }
    try {
      await _guard(
        analytics.setUserProperties(
          Map<String, String?>.unmodifiable(properties),
        ),
        deadline,
      );
      await _guard(analytics.logEvent(experimentStateEvent), deadline);
      return true;
    } catch (error) {
      // Once per kind of failure: a connector that always refuses must not log on every activate.
      if (!_closed) {
        _logOnce(
          'analytics-${error.runtimeType}',
          'The A/B testing hand-off to analytics failed (${error.runtimeType}); '
              'the next activate sends it again.',
        );
      }
      return false;
    }
  }

  void _onRolloutsListen(
    MultiStreamController<Set<RolloutAssignment>> controller,
  ) {
    if (_closed) {
      controller.closeSync();
      return;
    }
    _rolloutListeners.add(controller);
    controller.onCancel = () {
      _rolloutListeners.remove(controller);
    };
    if (_initialized) {
      controller.add(_rollouts);
      return;
    }
    unawaited(
      _initialization.then<void>(
        (void _) {
          if (_rolloutListeners.contains(controller)) {
            controller.add(_rollouts);
          }
        },
        // A failed load has no current set to give.
        onError: (Object _) {},
      ),
    );
  }

  /// Recomputes the rollout assignments of the active record and emits them when they changed.
  void _updateRollouts() {
    final Set<RolloutAssignment> rollouts = _rolloutsOf(_active);
    if (const SetEquality<RolloutAssignment>().equals(rollouts, _rollouts)) {
      return;
    }
    _rollouts = rollouts;
    for (final MultiStreamController<Set<RolloutAssignment>> listener
        in _rolloutListeners.toList()) {
      listener.add(rollouts);
    }
  }

  /// Android's `RolloutsStateFactory.getActiveRolloutsState` (`AI:rollouts/RolloutsStateFactory.java`):
  /// one assignment per rollout of [active], for its first affected key, with the value `getString`
  /// would read for it and the record's template version (0 without one).
  Set<RolloutAssignment> _rolloutsOf(TemplateRecord? active) {
    if (active == null) {
      return const <RolloutAssignment>{};
    }
    final Set<RolloutAssignment> result = <RolloutAssignment>{};
    for (final Map<String, Object?> rollout in active.rolloutMetadata) {
      final Object? keys = rollout['affectedParameterKeys'];
      final String key = keys is List<String> && keys.isNotEmpty
          ? keys.first
          : '';
      result.add(
        RolloutAssignment(
          rolloutId: rollout['rolloutId']! as String,
          variantId: rollout['variantId']! as String,
          parameterKey: key,
          parameterValue: active.entries[key] ?? defaults[key]?.text ?? '',
          templateVersion: active.templateVersion ?? 0,
        ),
      );
    }
    return Set<RolloutAssignment>.unmodifiable(result);
  }

  void _onIdChange(String fid) {
    unawaited(_onIdChangeAsync(fid));
  }

  /// 5.9.5: an ID change makes the cache stale only when a successful fetch was made with another FID.
  /// The first FID of an installation (no successful fetch yet) and the FID of the last success change
  /// nothing. A change to the FID the in-flight request already carries is left to that request: its
  /// success records the FID, its failure marks the cache stale.
  Future<void> _onIdChangeAsync(String fid) async {
    if (_closed) {
      return;
    }
    try {
      await _initialization;
    } catch (error) {
      return;
    }
    // close() may have run while the records loaded: no meta write after close.
    if (_closed) {
      return;
    }
    _realtime.onInstallationIdChanged(fid);
    if (fid == _requestFid) {
      _staleIfRequestFails = _isOtherFid(_meta, fid);
      return;
    }
    await _updateMeta(
      (MetaRecord meta) =>
          _isOtherFid(meta, fid) ? meta.incrementStale() : meta,
    );
  }

  /// True when the last successful fetch was made with an installation id other than [fid]. A record
  /// with a successful fetch but no `fid` (written before the field existed, or with its `fid` dropped)
  /// counts as another id.
  static bool _isOtherFid(MetaRecord meta, String fid) {
    final String? stored = meta.fid;
    if (stored == null) {
      return meta.lastSuccessfulFetchTime != null;
    }
    return stored != fid;
  }

  /// Waits for [future], failing with `fetch-timeout` past [deadline] (when given) and with
  /// `remote-config-closed` when the instance closes first.
  Future<T> _guard<T>(Future<T> future, DateTime? deadline) async {
    final List<Future<T>> racers = <Future<T>>[
      future,
      _closedSignal.future.then<T>((void _) => throw closedException()),
    ];
    Timer? timer;
    if (deadline != null) {
      final Completer<T> timedOut = Completer<T>();
      final Duration left = deadline.difference(_clock());
      timer = Timer(left.isNegative ? Duration.zero : left, () {
        timedOut.completeError(_timeout());
      });
      racers.add(timedOut.future);
    }
    try {
      return await Future.any(racers);
    } finally {
      timer?.cancel();
    }
  }

  Future<String?> _storeCall(Future<String?> Function() call) async {
    try {
      return await call();
    } catch (error) {
      _logOnce(
        'store-call',
        'A store call failed; the operation changed nothing.',
      );
      throw FirebaseRemoteConfigException(
        code: 'storage-error',
        message: 'The store failed; nothing was changed.',
        cause: error,
      );
    }
  }

  void _writeFailed(String name) {
    _logOnce(
      'write-$name',
      'A write of the $name record failed; the client continues from memory.',
    );
  }

  void _reportDrop(String field) {
    _logOnce(
      'drop-$field',
      'A $field of the template had the wrong shape and was dropped.',
    );
  }

  RemoteConfigValue? _remote(String key) {
    final String? remote = _active?.entries[key];
    return remote == null
        ? null
        : RemoteConfigValue(remote, ValueSource.valueRemote);
  }

  T? _convert<T>(String key, T? Function(RemoteConfigValue value) convert) {
    final String? remote = _active?.entries[key];
    if (remote != null) {
      final T? value = convert(
        RemoteConfigValue(remote, ValueSource.valueRemote),
      );
      if (value != null) {
        return value;
      }
    }
    final RemoteConfigValue? fallback = defaults[key];
    return fallback == null ? null : convert(fallback);
  }

  String _key(String name) => '$_keyPrefix$name';

  void _log(RemoteConfigLogLevel level, String message) {
    _logger?.call(level, message);
  }

  void _checkOpen() {
    if (_closed) {
      throw closedException();
    }
  }

  FirebaseRemoteConfigException _timeout() =>
      const FirebaseRemoteConfigException(
        code: 'fetch-timeout',
        message: 'The fetch did not complete before its timeout.',
      );

  /// The newer of two fetched records: by template version when both have one, else by fetch time.
  static TemplateRecord? _newer(TemplateRecord? a, TemplateRecord? b) {
    if (a == null) {
      return b;
    }
    if (b == null) {
      return a;
    }
    if (_isHigherVersion(a, b)) {
      return a;
    }
    if (_isHigherVersion(b, a)) {
      return b;
    }
    return b.fetchTime.isAfter(a.fetchTime) ? b : a;
  }

  /// The `fetched` transform's rule: keep [stored] instead of [fetched] (the answer to a request sent at
  /// [sentAt]) only when another instance stored it while that request was in flight, and it is newer:
  /// a higher template version when both have one, else a later fetch time.
  ///
  /// A stored record received before [sentAt] cannot be newer than [fetched], because template versions
  /// only grow; one with a fetch time after [now] is impossible. Either is replaced, so a corrupt or
  /// tampered record (a huge version, a future time) cannot block later fetches.
  static bool _keepsStored(
    TemplateRecord stored,
    TemplateRecord fetched,
    DateTime sentAt,
    DateTime now,
  ) {
    if (stored.fetchTime.isBefore(sentAt) || stored.fetchTime.isAfter(now)) {
      return false;
    }
    final int? storedVersion = stored.templateVersion;
    final int? fetchedVersion = fetched.templateVersion;
    if (storedVersion != null && fetchedVersion != null) {
      return storedVersion > fetchedVersion;
    }
    return stored.fetchTime.isAfter(fetched.fetchTime);
  }

  /// True when both records have a template version and [a]'s is higher than [b]'s. A record without a
  /// version (`NO_TEMPLATE`, `EMPTY_CONFIG`) is never outranked.
  static bool _isHigherVersion(TemplateRecord a, TemplateRecord b) {
    final int? versionA = a.templateVersion;
    final int? versionB = b.templateVersion;
    return versionA != null && versionB != null && versionA > versionB;
  }

  /// How long an active record with a higher template version holds off a lower fetched one: longer
  /// than any lagging server answer, short enough that a tampered version cannot block activate for good.
  static const Duration _activeVersionTrust = Duration(hours: 24);

  /// The activate transform's rule (5.5, A14, with A21's guard): keep [active] when it is the same fetch
  /// as [fetched] (compared in UTC milliseconds, the active time clamped to [now] as [fetched]'s is), or
  /// when it outranks [fetched] by template version and was fetched at most [_activeVersionTrust] before
  /// it. An active record with a fetch time after [now] is impossible and is replaced, so a corrupt or
  /// tampered record cannot block activate.
  static bool _keepsActive(
    TemplateRecord active,
    TemplateRecord fetched,
    DateTime now,
  ) {
    final DateTime activeTime = active.fetchTime;
    final DateTime clamped = activeTime.isAfter(now) ? now : activeTime;
    if (clamped.millisecondsSinceEpoch ==
        fetched.fetchTime.millisecondsSinceEpoch) {
      return true;
    }
    if (activeTime.isAfter(now)) {
      return false;
    }
    return _isHigherVersion(active, fetched) &&
        !activeTime.isBefore(fetched.fetchTime.subtract(_activeVersionTrust));
  }

  static bool _sameMap(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) {
      return false;
    }
    for (final MapEntry<String, String> entry in a.entries) {
      if (b[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }

  static void _checkOptions(FirebaseOptions options) {
    final String? projectId = options.projectId;
    final List<String> missing = <String>[
      if (projectId == null || projectId.isEmpty) 'projectId',
      if (options.apiKey.isEmpty) 'apiKey',
      if (options.appId.isEmpty) 'appId',
    ];
    if (missing.isNotEmpty) {
      throw FirebaseRemoteConfigException(
        code: 'invalid-app-config',
        message: 'The app options lack ${missing.join(', ')}.',
      );
    }
  }

  /// The `language_code` to send (5.6): [given] when set, else the language of the process; an empty
  /// result is `en`.
  static String _language(String? given) {
    if (given == null) {
      return defaultLanguage();
    }
    return given.trim().isEmpty ? 'en' : given;
  }

  static void _checkDuration(Duration? duration, String name) {
    if (duration != null && duration.isNegative) {
      throw ArgumentError.value(duration, name, 'must not be negative');
    }
  }

  static Map<String, RemoteConfigValue> _checkDefaults(
    Map<String, Object> defaults,
  ) {
    final Map<String, RemoteConfigValue> result = <String, RemoteConfigValue>{};
    int position = 0;
    for (final MapEntry<String, Object> entry in defaults.entries) {
      if (entry.key.isEmpty) {
        throw ArgumentError(
          'The default at position $position has an empty key.',
        );
      }
      result[entry.key] = RemoteConfigValue(
        _defaultText(entry.value, position),
        ValueSource.valueDefault,
      );
      position++;
    }
    return Map<String, RemoteConfigValue>.unmodifiable(result);
  }

  static String _defaultText(Object value, int position) {
    if (value is String) {
      return value;
    }
    if (value is bool) {
      return '$value';
    }
    if (value is num && value.isFinite) {
      return renderNumber(value);
    }
    throw ArgumentError(
      'The default at position $position is not a String, bool, int or finite double.',
    );
  }
}

/// The request in flight, shared by the calls made meanwhile (5.5).
final class _InFlight {
  _InFlight(this.generation, {required this.etagAllowed});

  /// False for a request that must not send `If-None-Match` (auto-fetch attempts 2 and 3).
  final bool etagAllowed;

  /// The result of the request.
  late final Future<FetchResult> future;

  /// The stale generation the request is built with: first the one its cache check used, then null
  /// while it waits for Installations, then the one it read afterwards (A8).
  int? generation;
}
