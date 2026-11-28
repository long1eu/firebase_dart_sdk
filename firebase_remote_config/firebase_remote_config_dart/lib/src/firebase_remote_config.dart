import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_installations_dart/firebase_installations_dart.dart';
import 'package:firebase_remote_config_dart/src/custom_signals.dart';
import 'package:firebase_remote_config_dart/src/exception.dart';
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
  FirebaseRemoteConfig(
    this.app, {
    required this.installations,
    Map<String, Object> defaults = const <String, Object>{},
    this.minimumFetchInterval = const Duration(hours: 12),
    this.fetchTimeout = const Duration(seconds: 60),
    String? languageCode,
    http.Client? httpClient,
    RemoteConfigLogger? logger,
    @visibleForTesting Uri? serverOrigin,
    @visibleForTesting Uri? realtimeOrigin,
    @visibleForTesting DateTime Function()? clock,
    @visibleForTesting double Function()? random,
    @visibleForTesting Future<void> Function(Duration duration)? delay,
  }) : defaults = _checkDefaults(defaults),
       _ownsClient = httpClient == null,
       _client = httpClient ?? http.Client(),
       _logger = logger,
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
    );
    _initialization = _load();
    // A failed load is reported by ensureInitialized and the calls that wait for it.
    _initialization.ignore();
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
  final DateTime Function() _clock;
  final double Function() _random;
  final String _languageCode;
  final String _keyPrefix;
  final Completer<void> _closedSignal = Completer<void>();
  final List<StreamSubscription<Object?>> _subscriptions =
      <StreamSubscription<Object?>>[];
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
  /// Throws `storage-error` when the store fails; memory is then unchanged.
  Future<bool> activate() async {
    _checkOpen();
    await _guard(_initialization, null);
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
    _active = TemplateRecord.tryParse(result, onDrop: _reportDrop, now: now);
    // A fetch that completed during the update stored a newer record; keep it.
    if (identical(_fetched, fetchedBefore)) {
      _fetched = fetched;
    }
    return wrote;
  }

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
  RemoteConfigValue getValue(String key) {
    final String? remote = _active?.entries[key];
    if (remote != null) {
      return RemoteConfigValue(remote, ValueSource.valueRemote);
    }
    return defaults[key] ?? staticValue;
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
