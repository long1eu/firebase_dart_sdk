import 'dart:async';
import 'dart:convert';

import 'package:firebase_app_dart/firebase_app_dart.dart' as dart_app;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_installations_dart/firebase_installations_dart.dart'
    as fis;
import 'package:firebase_remote_config_dart/firebase_remote_config_dart.dart'
    as rc;
import 'package:firebase_remote_config_dart_platform/src/app.dart';
import 'package:firebase_remote_config_dart_platform/src/default_store.dart';
import 'package:firebase_remote_config_dart_platform/src/errors.dart';
import 'package:firebase_remote_config_dart_platform/src/value.dart';
import 'package:firebase_remote_config_platform_interface/firebase_remote_config_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// What `FirebaseRemoteConfigDart.use` configures; read when a per-app
/// instance creates its clients.
class DartRemoteConfigConfig {
  /// A configuration; null values take the defaults.
  const DartRemoteConfigConfig({
    this.store,
    this.httpClient,
    this.languageCode,
  });

  /// The store of Installations and Remote Config; the default store
  /// ([defaultStore]) when null.
  final fis.KeyValueStore? store;

  /// The HTTP client of both clients; each creates and closes its own when
  /// null.
  final http.Client? httpClient;

  /// The `language_code` of the fetches; the platform's locale when null.
  final String? languageCode;
}

/// The implementation of [FirebaseRemoteConfigPlatform] on top of
/// `firebase_remote_config_dart`: one instance per FlutterFire app.
///
/// The instance registered as [FirebaseRemoteConfigPlatform.instance] has no
/// app; the official `firebase_remote_config` asks it for the instance of each
/// app ([delegateFor]). A per-app instance creates, on first use, one
/// `FirebaseInstallations` and one `FirebaseRemoteConfig` for the
/// `firebase_app_dart` app of the same name. Settings and defaults are kept
/// here, because the client takes them as constructor arguments: the settings
/// are passed to each fetch, and the defaults answer the reads the client
/// answers without a remote value.
///
/// The clients belong to the FlutterFire app of that name and the options it
/// had when they were created. Deleting that app closes them, on every
/// platform; trying to delete the default app off the web, which throws,
/// leaves them open. While a delete runs, no clients are created (when this
/// instance itself is first created during that delete, the clients it
/// creates then are closed at the first use after the delete). At each
/// use, when the app of that name no longer exists, or exists with other
/// options (it was deleted and created again), the clients are closed, and
/// new ones are created for the app's current options. The
/// `firebase_app_dart` app of that name is shared with the other platform
/// packages of this repository, so this class never deletes it: when one
/// with the old options is left (the native and web cores keep it), the new
/// clients cannot be created until the app restarts (see [client]).
///
/// Every error of these calls is a [FirebaseException] of the plugin
/// `firebase_remote_config` (see `convertError`).
///
/// The reads ([getValue] and the typed getters, [getAll], [lastFetchTime],
/// [lastFetchStatus]) never throw: while the clients cannot be created they
/// answer from the defaults of [setDefaults] (else static values), the epoch
/// and [RemoteConfigFetchStatus.noFetchYet], and log the cause once.
class DartFirebaseRemoteConfig extends FirebaseRemoteConfigPlatform {
  /// The instance without an app, for
  /// [FirebaseRemoteConfigPlatform.instance].
  DartFirebaseRemoteConfig() : super();

  DartFirebaseRemoteConfig._(FirebaseApp app) : super(appInstance: app);

  /// The configuration of the clients created from now on.
  static DartRemoteConfigConfig config = const DartRemoteConfigConfig();

  static final Map<String, DartFirebaseRemoteConfig> _instances =
      <String, DartFirebaseRemoteConfig>{};

  static bool _anyStarted = false;

  /// Whether a per-app instance has created its clients, after which [config]
  /// is no longer read.
  static bool get anyStarted => _anyStarted;

  /// The instance of [app], created on first use with its deletion service
  /// registered on [app], so that a delete that starts before the clients
  /// are created stops their creation.
  static DartFirebaseRemoteConfig forApp(FirebaseApp app) =>
      _instances.putIfAbsent(
        app.name,
        () => DartFirebaseRemoteConfig._(app).._registerService(app),
      );

  RemoteConfigSettings _settings = RemoteConfigSettings(
    fetchTimeout: const Duration(seconds: 60),
    minimumFetchInterval: const Duration(hours: 12),
  );

  Map<String, String> _defaults = const <String, String>{};

  rc.FirebaseRemoteConfig? _client;

  /// The deletion service this instance registered last.
  _RemoteConfigClients? _service;

  fis.FirebaseInstallations? _installations;

  /// The options of the FlutterFire app [_client] was created for.
  FirebaseOptions? _clientOptions;

  /// Whether a read logged that the clients cannot be created, since the
  /// last time they could.
  bool _readFailureLogged = false;

  /// The `firebase_remote_config_dart` client of this instance's app, created
  /// on first use with [config], for the FlutterFire app that has the name of
  /// [app] now.
  ///
  /// When that app no longer exists, or has other options than the ones the
  /// client was created for, the clients are closed first; with other
  /// options, new ones are created. The `firebase_app_dart` app of that name
  /// is reused when it has the app's options, as the other platform packages
  /// of this repository reuse it, and is never deleted here.
  ///
  /// Throws a [FirebaseException] of the plugin `firebase_remote_config`:
  /// `internal` on the registered instance, which has no app; when the app
  /// was deleted and not created again; while the app is being deleted, or
  /// after its delete failed; and when a `firebase_app_dart` app of that name
  /// has other options (the app was deleted and created again with other
  /// options on a core that keeps that app). The client's code when the app's
  /// options are not enough for Remote Config.
  rc.FirebaseRemoteConfig get client => guardSync(_currentClient);

  rc.FirebaseRemoteConfig _currentClient() {
    final FirebaseApp? stored = appInstance;
    if (stored == null) {
      throw internalError(
        'This is the registered instance of '
        'firebase_remote_config_dart_platform, which has no app: use '
        'FirebaseRemoteConfig.instanceFor(app: ...).',
      );
    }
    final FirebaseApp current;
    try {
      current = Firebase.app(stored.name);
    } on FirebaseException {
      unawaited(_dropClients());
      throw internalError(
        'The Firebase app "${stored.name}" was deleted: initialize it again, '
        'or use another app.',
      );
    }
    final _RemoteConfigClients? service = current
        .getService<_RemoteConfigClients>();
    final rc.FirebaseRemoteConfig? existing = _client;
    if (existing != null) {
      if (identical(service, _service) &&
          _clientOptions == current.options &&
          _isListed(existing.app)) {
        return existing;
      }
      unawaited(_dropClients());
    }
    if (service?.disposed ?? false) {
      throw _beingDeleted(current.name);
    }
    return _createClients(current);
  }

  /// The error of [client] while the app named [appName] is being deleted:
  /// `firebase_core` disposed its services (this one's clients), and the
  /// clients created then would outlive the delete, because the delete
  /// forgets the services without disposing them again.
  static FirebaseException _beingDeleted(String appName) => internalError(
    'The Firebase app "$appName" was deleted (its delete is running, or '
    'failed): Remote Config creates no clients for it until the delete is '
    'done.',
  );

  /// The error of [client] when the `firebase_app_dart` app named [appName]
  /// has other options than the FlutterFire app.
  static FirebaseException _staleDartApp(String appName) => internalError(
    'The Firebase app "$appName" has other options than when Remote Config '
    'first used that name (it was deleted and initialized again), and the '
    'pure-Dart app with the old options is still in this process, possibly '
    'shared with other plugins. Remote Config cannot use the new options '
    'under this name: initialize the app under another name, or restart the '
    'app.',
  );

  rc.FirebaseRemoteConfig _createClients(FirebaseApp current) {
    final dart_app.FirebaseApp dartApp;
    try {
      dartApp = dartAppFor(current);
    } on StateError {
      throw _staleDartApp(current.name);
    }
    final fis.FirebaseInstallations installations = fis.FirebaseInstallations(
      dartApp,
      store: config.store ?? defaultStore(),
      httpClient: config.httpClient,
    );
    final rc.FirebaseRemoteConfig created;
    try {
      created = rc.FirebaseRemoteConfig(
        dartApp,
        installations: installations,
        httpClient: config.httpClient,
        languageCode: config.languageCode,
      );
    } catch (_) {
      unawaited(installations.close());
      rethrow;
    }
    _anyStarted = true;
    if (!identical(current.getService<_RemoteConfigClients>(), _service)) {
      _registerService(current);
    }
    _installations = installations;
    _clientOptions = current.options;
    return _client = created;
  }

  /// Registers a new deletion service on [app] and remembers it.
  ///
  /// A delete disposes only the services registered when it starts, then
  /// forgets the app's services. A service registered while the delete runs
  /// (this instance was created then) is forgotten without being disposed;
  /// the clients created with it stay open until the next use, which sees
  /// that the app's service is no longer [_service] and closes them.
  void _registerService(FirebaseApp app) {
    final _RemoteConfigClients service = _RemoteConfigClients(this, app.name);
    app.registerService<_RemoteConfigClients>(
      service,
      dispose: (_RemoteConfigClients clients) => clients.close(),
    );
    _service = service;
  }

  static bool _isListed(dart_app.FirebaseApp app) => dart_app.Firebase.apps.any(
    (dart_app.FirebaseApp candidate) => identical(candidate, app),
  );

  /// Forgets the clients, then closes them.
  Future<void> _dropClients() async {
    final rc.FirebaseRemoteConfig? client = _client;
    final fis.FirebaseInstallations? installations = _installations;
    _client = null;
    _installations = null;
    _clientOptions = null;
    await client?.close();
    await installations?.close();
  }

  /// The client, or null when it cannot be created: the cause is logged
  /// once, until a later use creates it.
  rc.FirebaseRemoteConfig? get _clientForRead {
    try {
      final rc.FirebaseRemoteConfig remoteConfig = client;
      _readFailureLogged = false;
      return remoteConfig;
    } on Object catch (error) {
      if (!_readFailureLogged) {
        _readFailureLogged = true;
        debugPrint(
          '[firebase_remote_config] The Remote Config client cannot be '
          'created, so reads answer from the defaults: $error',
        );
      }
      return null;
    }
  }

  @override
  FirebaseRemoteConfigPlatform delegateFor({required FirebaseApp app}) =>
      forApp(app);

  /// The map is ignored: there are no values from a native side.
  @override
  FirebaseRemoteConfigPlatform setInitialValues({
    required Map<dynamic, dynamic> remoteConfigValues,
  }) => this;

  /// The time of the last successful fetch, or the epoch (UTC) before one or
  /// while the client cannot be created.
  @override
  DateTime get lastFetchTime =>
      _clientForRead?.info.lastSuccessfulFetchTime ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  /// The status of the last fetch; [RemoteConfigFetchStatus.noFetchYet] while
  /// the client cannot be created.
  @override
  RemoteConfigFetchStatus get lastFetchStatus {
    final rc.FirebaseRemoteConfig? remoteConfig = _clientForRead;
    if (remoteConfig == null) {
      return RemoteConfigFetchStatus.noFetchYet;
    }
    return switch (remoteConfig.info.lastFetchStatus) {
      rc.RemoteConfigFetchStatus.noFetchYet =>
        RemoteConfigFetchStatus.noFetchYet,
      rc.RemoteConfigFetchStatus.success => RemoteConfigFetchStatus.success,
      rc.RemoteConfigFetchStatus.failure => RemoteConfigFetchStatus.failure,
      rc.RemoteConfigFetchStatus.throttled => RemoteConfigFetchStatus.throttle,
    };
  }

  /// A copy of the settings of [setConfigSettings]; a fetch timeout of 60
  /// seconds and a minimum fetch interval of 12 hours before it is called.
  @override
  RemoteConfigSettings get settings => RemoteConfigSettings(
    fetchTimeout: _settings.fetchTimeout,
    minimumFetchInterval: _settings.minimumFetchInterval,
  );

  @override
  Future<bool> activate() => guard(() => client.activate());

  @override
  Future<void> ensureInitialized() => guard(() => client.ensureInitialized());

  /// Fetches with the timeout and minimum fetch interval of [settings].
  @override
  Future<void> fetch() => guard(() async {
    await client.fetch(
      minimumFetchInterval: _settings.minimumFetchInterval,
      timeout: _settings.fetchTimeout,
    );
  });

  /// Fetches with the timeout and minimum fetch interval of [settings], then
  /// activates.
  @override
  Future<bool> fetchAndActivate() => guard(
    () => client.fetchAndActivate(
      minimumFetchInterval: _settings.minimumFetchInterval,
      timeout: _settings.fetchTimeout,
    ),
  );

  /// The active keys and the keys of [setDefaults], each as [getValue].
  @override
  Map<String, RemoteConfigValue> getAll() {
    final rc.FirebaseRemoteConfig? remoteConfig = _clientForRead;
    final Set<String> keys = <String>{
      ...?remoteConfig?.getAll().keys,
      ..._defaults.keys,
    };
    return <String, RemoteConfigValue>{
      for (final String key in keys) key: _valueOf(remoteConfig, key),
    };
  }

  @override
  bool getBool(String key) => getValue(key).asBool();

  @override
  int getInt(String key) => getValue(key).asInt();

  @override
  double getDouble(String key) => getValue(key).asDouble();

  @override
  String getString(String key) => getValue(key).asString();

  /// The active value of [key]; else its default from [setDefaults]; else an
  /// empty static value.
  @override
  RemoteConfigValue getValue(String key) => _valueOf(_clientForRead, key);

  RemoteConfigValue _valueOf(
    rc.FirebaseRemoteConfig? remoteConfig,
    String key,
  ) {
    final rc.RemoteConfigValue? value = remoteConfig?.getValue(key);
    if (value != null && value.source == rc.ValueSource.valueRemote) {
      return DartRemoteConfigValue(value.text, ValueSource.valueRemote);
    }
    final String? defaultValue = _defaults[key];
    if (defaultValue != null) {
      return DartRemoteConfigValue(defaultValue, ValueSource.valueDefault);
    }
    return DartRemoteConfigValue('', ValueSource.valueStatic);
  }

  /// Keeps a copy of [remoteConfigSettings] for the next fetches.
  ///
  /// A fetch timeout of zero is kept, as the client accepts it.
  ///
  /// Throws a [FirebaseException] with the code `invalid-argument`, and keeps
  /// the settings it had, when the fetch timeout or the minimum fetch
  /// interval is negative.
  @override
  Future<void> setConfigSettings(
    RemoteConfigSettings remoteConfigSettings,
  ) async {
    final Duration timeout = remoteConfigSettings.fetchTimeout;
    final Duration interval = remoteConfigSettings.minimumFetchInterval;
    if (timeout.isNegative) {
      throw _invalidSetting('fetchTimeout must not be negative, got $timeout.');
    }
    if (interval.isNegative) {
      throw _invalidSetting(
        'minimumFetchInterval must not be negative, got $interval.',
      );
    }
    _settings = RemoteConfigSettings(
      fetchTimeout: timeout,
      minimumFetchInterval: interval,
    );
  }

  static FirebaseException _invalidSetting(String message) => FirebaseException(
    plugin: remoteConfigPlugin,
    code: 'invalid-argument',
    message: message,
  );

  /// Replaces the defaults. A value of null is left out; a `List<int>` is
  /// kept as the text of its bytes decoded as UTF-8 (malformed bytes become
  /// U+FFFD), as Android decodes a byte array; any other value as its
  /// `toString()`, as Android does.
  @override
  Future<void> setDefaults(Map<String, dynamic> defaultParameters) async {
    _defaults = Map<String, String>.unmodifiable(<String, String>{
      for (final MapEntry<String, dynamic> entry in defaultParameters.entries)
        if (entry.value != null) entry.key: _defaultText(entry.value as Object),
    });
  }

  static String _defaultText(Object value) => value is List<int>
      ? utf8.decode(value, allowMalformed: true)
      : value.toString();

  /// The client's updates; listening opens the realtime connection.
  @override
  Stream<RemoteConfigUpdate> get onConfigUpdated {
    final rc.FirebaseRemoteConfig remoteConfig;
    try {
      remoteConfig = client;
    } catch (error, stackTrace) {
      return Stream<RemoteConfigUpdate>.error(error, stackTrace);
    }
    return guardStream(
      remoteConfig.onConfigUpdated.map(
        (rc.RemoteConfigUpdate update) =>
            RemoteConfigUpdate(update.updatedKeys),
      ),
    );
  }

  /// Merges [customSignals] into the stored signals; a value of null removes
  /// a signal. A signal that breaks a limit throws a [FirebaseException] with
  /// the code `invalid-argument`, and nothing is stored.
  @override
  Future<void> setCustomSignals(Map<String, Object?> customSignals) =>
      guard(() async {
        try {
          await client.setCustomSignals(customSignals);
        } on ArgumentError catch (error) {
          throw invalidArgument(error);
        }
      });
}

/// The `firebase_core` service that closes the clients of one app when that
/// app is deleted, on every platform (on Linux the Dart core also deletes the
/// `firebase_app_dart` app, which closes them; elsewhere nothing else does).
///
/// It is registered when the per-app instance is created, and again when the
/// clients are created for an app that no longer has it (the app was deleted
/// and created again). `firebase_core` disposes the services before the
/// delete, and forgets them only when the delete succeeds. So while
/// [disposed] is true and the service is still registered, the delete runs
/// (or failed), and [DartFirebaseRemoteConfig.client] creates no clients;
/// once it is forgotten, the next use closes the clients created with it.
final class _RemoteConfigClients implements FirebaseService {
  _RemoteConfigClients(this.instance, this.appName);

  final DartFirebaseRemoteConfig instance;

  /// The name of the app this service is registered on.
  final String appName;

  /// Whether `firebase_core` disposed this service for a delete.
  bool disposed = false;

  /// Closes the clients, except for the default app off the web: there the
  /// core throws for its delete after the services are disposed (the web one
  /// deletes it), and the clients would close for an app that stays. A
  /// service that is no longer the instance's last one closes nothing: the
  /// clients belong to the newer one.
  Future<void> close() async {
    if (!kIsWeb && appName == defaultFirebaseAppName) {
      return;
    }
    disposed = true;
    if (identical(instance._service, this)) {
      await instance._dropClients();
    }
  }
}
