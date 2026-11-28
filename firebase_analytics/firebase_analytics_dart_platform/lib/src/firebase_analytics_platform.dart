import 'dart:async';

import 'package:firebase_analytics_dart/firebase_analytics_dart.dart' as fa;
import 'package:firebase_analytics_dart_platform/src/app.dart';
import 'package:firebase_analytics_dart_platform/src/default_store.dart';
import 'package:firebase_analytics_dart_platform/src/errors.dart';
import 'package:firebase_analytics_dart_platform/src/lifecycle.dart';
import 'package:firebase_analytics_platform_interface/firebase_analytics_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// What `FirebaseAnalyticsDart.configure` sets; read when a per-app instance
/// creates its client.
class DartAnalyticsConfig {
  /// A configuration; null values take the defaults of the client.
  const DartAnalyticsConfig({
    this.measurementId,
    this.transport,
    this.store,
    this.httpClient,
    this.tokenProviderFor,
    this.appCheckProviderFor,
    this.region = fa.AnalyticsRegion.global,
    this.sessionTimeout = const Duration(minutes: 30),
    this.collectionEnabledByDefault = true,
    this.batchDelay = const Duration(seconds: 5),
    this.maxQueuedEvents = 1000,
    this.device,
    this.userLocation,
    this.onWarning,
  });

  /// The `G-…` id of the GA4 web data stream; the app's
  /// `FirebaseOptions.measurementId` when null.
  final String? measurementId;

  /// How events reach Google Analytics. There is no default: creating a client
  /// without one throws a [StateError].
  final fa.AnalyticsTransport? transport;

  /// Where the state and the queue are kept; [defaultStore] when null.
  final fa.AnalyticsStore? store;

  /// The HTTP client of the requests; each client creates and closes its own
  /// when null.
  final http.Client? httpClient;

  /// The user whose ID token a relay request carries.
  final TokenProviderFactory? tokenProviderFor;

  /// The App Check token a relay request carries.
  final AppCheckProviderFactory? appCheckProviderFor;

  /// The collection endpoint of a direct transport.
  final fa.AnalyticsRegion region;

  /// The session timeout until `setSessionTimeoutDuration` sets another.
  final Duration sessionTimeout;

  /// Whether events are collected before `setAnalyticsCollectionEnabled` is
  /// first called.
  final bool collectionEnabledByDefault;

  /// How long the first event of a batch waits for others.
  final Duration batchDelay;

  /// The most events kept unsent.
  final int maxQueuedEvents;

  /// The `device` block of every request, when set.
  final fa.AnalyticsDevice? device;

  /// The `user_location` block of every request, when set.
  final fa.AnalyticsUserLocation? userLocation;

  /// Receives what the client cannot throw; the client's default when null.
  final void Function(String message)? onWarning;
}

/// The implementation of [FirebaseAnalyticsPlatform] on top of
/// `firebase_analytics_dart`: one instance, and one client, per FlutterFire
/// app.
///
/// The instance registered as [FirebaseAnalyticsPlatform.instance] has no app;
/// the official `firebase_analytics` asks it for the instance of each app
/// ([delegateFor]). A per-app instance creates its client on first use, with
/// [config], for the `firebase_app_dart` app of the same name (shared with the
/// other platform packages of this repository).
///
/// Every rule the client enforces (an event name, a parameter, a user
/// property, the user id) is reported as a [FirebaseException] of
/// `firebase_core` with the plugin `firebase_analytics` and the client's code,
/// for example `reserved-name` for `ad_impression` and `in_app_purchase`,
/// which the Measurement Protocol allows for app streams only.
class DartFirebaseAnalytics extends FirebaseAnalyticsPlatform {
  /// The instance without an app, for [FirebaseAnalyticsPlatform.instance].
  DartFirebaseAnalytics() : super();

  DartFirebaseAnalytics._(FirebaseApp app) : super(appInstance: app);

  /// The configuration of the clients created from now on.
  static DartAnalyticsConfig config = const DartAnalyticsConfig();

  static final Map<String, DartFirebaseAnalytics> _instances =
      <String, DartFirebaseAnalytics>{};

  /// Whether a per-app instance has created its client, after which [config]
  /// is no longer read.
  static bool get anyStarted => _instances.values.any(
    (DartFirebaseAnalytics instance) => instance._started,
  );

  /// The instance of [app], created on first use.
  static DartFirebaseAnalytics forApp(FirebaseApp app) =>
      _instances.putIfAbsent(app.name, () => DartFirebaseAnalytics._(app));

  /// Closes every client and forgets the state of every instance, so that
  /// the next call creates a client from [config] again. For tests.
  @visibleForTesting
  static Future<void> debugReset() async {
    for (final DartFirebaseAnalytics instance in _instances.values) {
      await instance._closing;
      final fa.FirebaseAnalytics? client = instance._client;
      instance
        .._client = null
        .._started = false
        .._eventLogged = false
        .._sessionTimeout = null
        .._store = null
        .._listening = false;
      await client?.close();
    }
    AppActivity.instance.reset();
  }

  fa.FirebaseAnalytics? _client;

  /// Whether this instance created a client.
  bool _started = false;

  /// Set when a client is being closed to create another; no client is
  /// created until it completes.
  Future<void>? _closing;

  /// The store of this instance's clients, chosen when the first is created,
  /// so that a client created again by [setSessionTimeoutDuration] finds the
  /// state of the first.
  fa.AnalyticsStore? _store;

  /// Set by [setSessionTimeoutDuration]; [DartAnalyticsConfig.sessionTimeout]
  /// while null.
  Duration? _sessionTimeout;

  /// Whether an event was logged through this instance in this process.
  bool _eventLogged = false;

  bool _listening = false;

  /// The client of this instance's app, created on first use.
  Future<fa.FirebaseAnalytics> client() async {
    AppActivity.instance.attach();
    while (_closing != null) {
      await _closing;
    }
    return _client ?? _createClient();
  }

  fa.FirebaseAnalytics _createClient() {
    final FirebaseApp? app = appInstance;
    if (app == null) {
      throw StateError(
        'This is the registered instance of firebase_analytics_dart_platform, '
        'which has no app: use FirebaseAnalytics.instanceFor(app: ...).',
      );
    }
    final DartAnalyticsConfig settings = config;
    final fa.AnalyticsTransport? transport = settings.transport;
    if (transport == null) {
      throw StateError(
        'firebase_analytics_dart_platform has no transport: call '
        'FirebaseAnalyticsDart.configure(transport: ...) at the start of '
        'main, before Firebase.initializeApp. Events go to a relay you run '
        '(AnalyticsTransport.relay) or, for internal tools only, to Google '
        'Analytics with the API secret (AnalyticsTransport.direct).',
      );
    }
    final fa.FirebaseAnalytics created = fa.FirebaseAnalytics(
      dartAppFor(
        app,
        tokenProviderFor: settings.tokenProviderFor,
        appCheckProviderFor: settings.appCheckProviderFor,
      ),
      measurementId: settings.measurementId,
      transport: transport,
      store: _store ??= settings.store ?? defaultStore(),
      region: settings.region,
      sessionTimeout: _sessionTimeout ?? settings.sessionTimeout,
      collectionEnabledByDefault: settings.collectionEnabledByDefault,
      batchDelay: settings.batchDelay,
      maxQueuedEvents: settings.maxQueuedEvents,
      device: settings.device,
      userLocation: settings.userLocation,
      onWarning: settings.onWarning,
      httpClient: settings.httpClient,
    );
    _client = created;
    _started = true;
    if (!_listening) {
      _listening = true;
      AppActivity.instance.addListener(_onAppActive);
    }
    final bool? active = AppActivity.instance.active;
    if (active != null) {
      created.setAppActive(active);
    }
    return created;
  }

  void _onAppActive(bool active) => _client?.setAppActive(active);

  @override
  FirebaseAnalyticsPlatform delegateFor({
    required FirebaseApp app,
    Map<String, dynamic>? webOptions,
  }) => forApp(app);

  /// Always true: the client works wherever `package:http` does.
  @override
  Future<bool> isSupported() async => true;

  /// The client id of this installation; null while analytics storage is
  /// denied.
  @override
  Future<String?> getAppInstanceId() =>
      guard(() async => (await client()).appInstanceId);

  /// The start time of the current session in seconds; null when there is
  /// none.
  @override
  Future<int?> getSessionId() => guard(() async => (await client()).sessionId);

  /// Logs the event through the client's `logEvent`. `screen_view`, which
  /// `FirebaseAnalytics.logScreenView` sends, goes through the client's
  /// `logScreenView` and is sent as `page_view`; it needs a `screen_name`.
  /// [callOptions] (web only) is ignored.
  @override
  Future<void> logEvent({
    required String name,
    Map<String, Object?>? parameters,
    AnalyticsCallOptions? callOptions,
  }) {
    _eventLogged = true;
    if (name == 'screen_view') {
      return _logScreenView(parameters);
    }
    return guard(
      () async => (await client()).logEvent(name: name, parameters: parameters),
    );
  }

  Future<void> _logScreenView(Map<String, Object?>? parameters) {
    final Map<String, Object?> rest = Map<String, Object?>.of(
      parameters ?? const <String, Object?>{},
    );
    final Object? screenName = rest.remove('screen_name');
    final Object? screenClass = rest.remove('screen_class');
    if (screenName is! String) {
      return Future<void>.error(
        FirebaseException(
          plugin: analyticsPlugin,
          code: 'invalid-parameter',
          message:
              'logScreenView needs a screenName here: the screen is sent as '
              'page_view, whose page_title and page_location are made from '
              'it.',
        ),
      );
    }
    if (screenClass != null && screenClass is! String) {
      return Future<void>.error(
        FirebaseException(
          plugin: analyticsPlugin,
          code: 'invalid-parameter',
          message: 'The screen class must be a String.',
        ),
      );
    }
    return guard(
      () async => (await client()).logScreenView(
        screenName: screenName,
        screenClass: screenClass as String?,
        parameters: rest.isEmpty ? null : rest,
      ),
    );
  }

  @override
  Future<void> setAnalyticsCollectionEnabled(bool enabled) => guard(
    () async => (await client()).setAnalyticsCollectionEnabled(enabled),
  );

  /// [callOptions] (web only) is ignored.
  @override
  Future<void> setUserId({String? id, AnalyticsCallOptions? callOptions}) =>
      guard(() async => (await client()).setUserId(id));

  /// [callOptions] (web only) is ignored.
  @override
  Future<void> setUserProperty({
    required String name,
    required String? value,
    AnalyticsCallOptions? callOptions,
  }) => guard(
    () async => (await client()).setUserProperty(name: name, value: value),
  );

  @override
  Future<void> resetAnalyticsData() =>
      guard(() async => (await client()).resetAnalyticsData());

  /// Sets the session timeout of the client. The client takes it as
  /// configuration, so this works only before the first event this app logs
  /// in this process: the client is created again with the new timeout. After
  /// that event it throws a [StateError]; a timeout that is not positive
  /// throws an [ArgumentError].
  @override
  Future<void> setSessionTimeoutDuration(Duration timeout) async {
    if (_eventLogged) {
      throw StateError(
        'setSessionTimeoutDuration was called after the first event: '
        'firebase_analytics_dart takes the session timeout as configuration, '
        'and this app has already logged an event in this process. Call it '
        'at start-up, before the first logEvent or logScreenView, or pass '
        'FirebaseAnalyticsDart.configure(sessionTimeout: ...).',
      );
    }
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'Must be positive');
    }
    _sessionTimeout = timeout;
    final fa.FirebaseAnalytics? old = _client;
    if (old == null) {
      return;
    }
    _client = null;
    final Future<void> closing = old.close().catchError((Object _) {});
    _closing = closing;
    try {
      await closing;
    } finally {
      if (identical(_closing, closing)) {
        _closing = null;
      }
    }
  }

  /// Maps the four consent types the client knows:
  /// [adUserDataConsentGranted] and [adPersonalizationSignalsConsentGranted]
  /// are sent as the `consent` of later requests; while
  /// [analyticsStorageConsentGranted] is false nothing is collected or sent;
  /// [adStorageConsentGranted] is kept and changes nothing. The three web
  /// storage types ([functionalityStorageConsentGranted],
  /// [personalizationStorageConsentGranted],
  /// [securityStorageConsentGranted]) are accepted and ignored.
  @override
  Future<void> setConsent({
    bool? adStorageConsentGranted,
    bool? analyticsStorageConsentGranted,
    bool? adPersonalizationSignalsConsentGranted,
    bool? adUserDataConsentGranted,
    bool? functionalityStorageConsentGranted,
    bool? personalizationStorageConsentGranted,
    bool? securityStorageConsentGranted,
  }) => guard(
    () async => (await client()).setConsent(
      adUserData: adUserDataConsentGranted,
      adPersonalization: adPersonalizationSignalsConsentGranted,
      analyticsStorage: analyticsStorageConsentGranted,
      adStorage: adStorageConsentGranted,
    ),
  );

  @override
  Future<void> setDefaultEventParameters(
    Map<String, Object?>? defaultParameters,
  ) => guard(
    () async => (await client()).setDefaultEventParameters(defaultParameters),
  );

  /// Throws an [UnimplementedError]: on-device conversion measurement is an
  /// ads attribution feature of the native iOS SDK, with no Measurement
  /// Protocol counterpart.
  @override
  Future<void> initiateOnDeviceConversionMeasurement({
    String? emailAddress,
    String? phoneNumber,
    String? hashedEmailAddress,
    String? hashedPhoneNumber,
  }) async {
    throw UnimplementedError(
      'initiateOnDeviceConversionMeasurement is not available in '
      'firebase_analytics_dart_platform: on-device conversion measurement is '
      'an ads attribution feature of the native iOS SDK, and the Measurement '
      'Protocol has no counterpart.',
    );
  }

  /// Throws an [UnimplementedError]: it reports StoreKit 2 transactions,
  /// which only the native SDK on iOS and macOS can read.
  @override
  Future<void> logTransaction({required String transactionId}) async {
    throw UnimplementedError(
      'logTransaction is not available in firebase_analytics_dart_platform: '
      'it reports StoreKit 2 transactions, which only the native SDK on '
      'iOS and macOS can read and which need an app stream.',
    );
  }
}
