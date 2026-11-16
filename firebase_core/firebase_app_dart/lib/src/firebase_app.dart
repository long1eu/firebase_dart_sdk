// File created by
// Lung Razvan <long1eu>
// on 16/09/2018

import 'dart:async';
import 'dart:convert';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_app_dart/internal.dart';
import 'package:firebase_app_dart/src/platform_dependencies.dart';
import 'package:meta/meta.dart';
import 'package:rxdart/rxdart.dart';

/// The name of the default app, `[DEFAULT]`.
const String defaultFirebaseAppName = '[DEFAULT]';

/// The FlutterFire entry point: creates and finds [FirebaseApp]s by name.
///
/// [initializeApp] is the asynchronous twin of [FirebaseApp.withOptions], with the shape of
/// FlutterFire's `Firebase.initializeApp`; [app] and [apps] look the apps up.
///
/// ```dart
/// import 'package:firebase_app_dart/firebase_app_dart.dart';
///
/// Future<void> main() async {
///   final FirebaseApp app = await Firebase.initializeApp(
///     options: const FirebaseOptions(
///       apiKey: '<YOUR_API_KEY>',
///       appId: '1:1234567890:dart:example',
///       projectId: 'my-project',
///     ),
///   );
///   print(identical(Firebase.app(), app)); // true
/// }
/// ```
abstract final class Firebase {
  /// Creates the app called [name] (default: the default app) with [options] and
  /// [dependencies], like [FirebaseApp.withOptions].
  ///
  /// When an app with this name exists, it is returned if [options] is null or equal to its
  /// options; otherwise this throws a [FirebaseException] with the code `duplicate-app`. A new app
  /// needs [options]: without them this throws a [FirebaseException] with the code `no-options`
  /// (FlutterFire reads them from the platform files there; these packages have no such files).
  static Future<FirebaseApp> initializeApp({
    String? name,
    FirebaseOptions? options,
    PlatformDependencies? dependencies,
  }) async {
    final String appName = FirebaseApp._normalize(
      name ?? defaultFirebaseAppName,
    );
    final FirebaseApp? existing = FirebaseApp._instances[appName];
    if (existing != null) {
      if (options == null || options == existing.options) {
        return existing;
      }
      throw FirebaseException(
        plugin: 'core',
        code: 'duplicate-app',
        message:
            'A Firebase App named "$appName" already exists with other options.',
      );
    }
    if (options == null) {
      throw FirebaseException(
        plugin: 'core',
        code: 'no-options',
        message:
            'Firebase.initializeApp needs options to create the app "$appName".',
      );
    }
    return FirebaseApp.withOptions(
      options,
      name: appName,
      dependencies: dependencies,
    );
  }

  /// The app called [name] (leading and trailing white space is ignored); the default app when
  /// [name] is omitted.
  ///
  /// Throws a [FirebaseException] with the code `no-app`, whose message lists the names of the
  /// existing apps, if there is no app with this name (it was not created, or it was deleted).
  static FirebaseApp app([String name = defaultFirebaseAppName]) {
    final FirebaseApp? firebaseApp =
        FirebaseApp._instances[FirebaseApp._normalize(name)];
    if (firebaseApp != null) {
      return firebaseApp;
    }
    final List<String> availableAppNames = FirebaseApp._getAllAppNames();
    final String availableAppNamesMessage = availableAppNames.isNotEmpty
        ? ' Available app names: ${availableAppNames.join(', ')}.'
        : '';
    throw FirebaseException(
      plugin: 'core',
      code: 'no-app',
      message: 'No Firebase App named "$name" exists.$availableAppNamesMessage',
    );
  }

  /// The apps that exist now (created and not deleted), in the order they were created.
  ///
  /// The list is a copy: changing it does not create or delete apps.
  static List<FirebaseApp> get apps =>
      List<FirebaseApp>.from(FirebaseApp._instances.values);
}

/// The entry point of the Firebase SDKs: a named set of [FirebaseOptions] shared by the Firebase
/// services of one project.
///
/// Create one with [FirebaseApp.withOptions]. The app created without a name is the default app,
/// returned by [FirebaseApp.instance]; apps created with a `name` are returned by `Firebase.app`.
/// Each name can be used by one app at a time: [delete] an app to free its name.
///
/// The app also connects the services to the platform they run on. It implements
/// `PlatformDependencies`: every member ([onNetworkConnected], [storage], [authProvider],
/// [appCheckProvider], ...) answers with the value of the `dependencies` passed to
/// [FirebaseApp.withOptions], or with a default when there are none. A service reads them when it
/// is created, so set [authProvider] and [appCheckProvider] before you create the Firestore
/// instance of the app.
///
/// ```dart
/// import 'package:firebase_app_dart/firebase_app_dart.dart';
///
/// void main() {
///   final FirebaseApp app = FirebaseApp.withOptions(
///     const FirebaseOptions(
///       apiKey: '<YOUR_API_KEY>',
///       appId: '1:1234567890:dart:example',
///       projectId: 'my-project',
///     ),
///   );
///   print(app.name); // [DEFAULT]
///   print(identical(FirebaseApp.instance, app)); // true
///
///   final FirebaseApp other = FirebaseApp.withOptions(
///     const FirebaseOptions(
///       apiKey: '<YOUR_API_KEY>',
///       appId: '1:1234567890:dart:other',
///       projectId: 'other-project',
///     ),
///     name: 'other',
///   );
///   print(identical(Firebase.app('other'), other)); // true
/// }
/// ```
class FirebaseApp with _PlatformDependenciesMixin {
  FirebaseApp._(
    this._name,
    this._options,
    this._dependencies,
    this._dataCollectionDefaultEnabled,
  );

  /// Creates the app called [name] with [options] and registers it, so that `Firebase.app` (and,
  /// for the default app, [instance]) returns it. `Firebase.initializeApp` does the same, with the
  /// shape of FlutterFire.
  ///
  /// * [name] defaults to [defaultFirebaseAppName], which makes this the default app. Leading and trailing
  ///   white space is removed, so `' tool '` and `'tool'` are the same app.
  /// * [dependencies] connect the app to its platform (storage, connectivity, token providers).
  ///   Without them the app keeps its data in memory, reports the network as connected and the
  ///   app as in the foreground, and has no token providers. They are read once, here.
  /// * The value of [isAutomaticDataCollectionEnabled] is read from the storage of [dependencies]
  ///   (default `true`).
  ///
  /// Throws an [ArgumentError] if `options.appId` is empty, and a [StateError] if an app
  /// with this name exists (and was not deleted).
  factory FirebaseApp.withOptions(
    FirebaseOptions options, {
    PlatformDependencies? dependencies,
    String name = defaultFirebaseAppName,
  }) {
    final String normalizedName = _normalize(name);

    // The const constructor of [FirebaseOptions] only checks this with an
    // assert, which a release build skips.
    if (options.appId.isEmpty) {
      throw ArgumentError.value(
        options.appId,
        'options.appId',
        'appId must be set.',
      );
    }
    Preconditions.checkState(
      !_instances.containsKey(normalizedName),
      'FirebaseApp name $normalizedName already exists!',
    );

    final LocalStorage? storage = dependencies?.storage;
    final String dataCollectionDefaultEnabled =
        storage?.get(_dataCollectionDefaultEnabledPreferenceKey) ?? 'true';
    final FirebaseApp firebaseApp = FirebaseApp._(
      normalizedName,
      options,
      dependencies,
      dataCollectionDefaultEnabled == 'true',
    ).._initPlatformDependencies();
    _instances[normalizedName] = firebaseApp;
    return firebaseApp;
  }

  /// The default app: the one created by [FirebaseApp.withOptions] without a name.
  ///
  /// Throws a [StateError] if there is none (it was not created, or it was deleted).
  static FirebaseApp get instance {
    final FirebaseApp? defaultApp = _instances[defaultFirebaseAppName];
    if (defaultApp == null) {
      throw StateError(
        'Default FirebaseApp is not initialized. Make sure to call Firebase.initializeApp() or FirebaseApp.withOptions() first.',
      );
    }

    return defaultApp;
  }

  static final Map<String, FirebaseApp> _instances = <String, FirebaseApp>{};
  static const String _dataCollectionDefaultEnabledPreferenceKey =
      'firebase_data_collection_default_enabled';

  final String _name;
  final FirebaseOptions _options;
  @override
  final PlatformDependencies? _dependencies;

  final StreamController<bool> _dataCollectionChangeSink =
      StreamController<bool>.broadcast();
  final StreamController<String> _deleteSink =
      StreamController<String>.broadcast();

  bool _automaticResourceManagementEnabled = false;
  bool _deleted = false;
  bool _dataCollectionDefaultEnabled;

  /// Emits the new value every time [setAutomaticDataCollectionEnabled] changes it. A broadcast
  /// stream; it does not emit the current value when you listen.
  Stream<bool> get onDataCollectionChange => _dataCollectionChangeSink.stream;

  /// Emits the [name] of this app when [delete] is called (once). A broadcast stream.
  ///
  /// `cloud_firestore_dart` listens to it and shuts down the Firestore instances of the app.
  Stream<String> get onDeleteApp => _deleteSink.stream;

  /// The name of this app: [defaultFirebaseAppName] for the default app.
  ///
  /// Throws a [StateError] after [delete].
  String get name {
    _checkNotDeleted();
    return _name;
  }

  /// The options this app was created with.
  ///
  /// Throws a [StateError] after [delete].
  FirebaseOptions get options {
    _checkNotDeleted();
    return _options;
  }

  /// Deletes this app: it is removed from `Firebase.apps`, [onDeleteApp] emits its name, and reading its
  /// [name] or [options] afterwards throws a [StateError]. Deleting twice is a no-op.
  ///
  /// The name is free again: [FirebaseApp.withOptions] can create a new app with it.
  /// `cloud_firestore_dart` shuts down the Firestore instances of a deleted app; it does not wait
  /// for that, so call `terminate()` on them yourself when you need to know when they are done.
  ///
  /// The app is deleted when the call returns; the future completes right away.
  Future<void> delete() {
    if (!_deleted) {
      _deleted = true;
      _instances.remove(_name);
      _deleteSink.add(_name);
    }
    return Future<void>.value();
  }

  /// Kept from the original project; no service of this repository reads it. Disabled by default.
  ///
  /// When the setting changes while [onBackgroundChanged] says the app is in the background,
  /// [onBackgroundChanged] emits again (`true` when [enabled], `false` otherwise).
  ///
  /// Throws a [StateError] after [delete]. The setting changes before the call returns; the future
  /// completes right away.
  Future<void> setAutomaticResourceManagementEnabled(bool enabled) {
    _checkNotDeleted();

    if (_automaticResourceManagementEnabled != enabled) {
      _automaticResourceManagementEnabled = enabled;

      final bool inBackground = onBackgroundChanged.value;
      if (enabled && inBackground) {
        onBackgroundChanged.add(true);
      } else if (!enabled && inBackground) {
        onBackgroundChanged.add(false);
      }
    }
    return Future<void>.value();
  }

  /// Whether automatic data collection is enabled. Stored, not used: no service of this repository
  /// collects data.
  ///
  /// The initial value is the one stored by [setAutomaticDataCollectionEnabled] in the [storage] of
  /// the platform dependencies, or `true`. It does not come from
  /// [FirebaseOptions.dataCollectionEnabled].
  ///
  /// Throws a [StateError] after [delete].
  bool get isAutomaticDataCollectionEnabled {
    _checkNotDeleted();
    return _dataCollectionDefaultEnabled;
  }

  /// Enables or disables automatic data collection (see [isAutomaticDataCollectionEnabled]).
  ///
  /// A change is written to [storage] under the key `firebase_data_collection_default_enabled`
  /// and emitted by [onDataCollectionChange]; setting the current value does nothing.
  ///
  /// Throws a [StateError] after [delete]. The future completes when the value is stored.
  Future<void> setAutomaticDataCollectionEnabled(bool enabled) {
    _checkNotDeleted();
    if (_dataCollectionDefaultEnabled != enabled) {
      _dataCollectionDefaultEnabled = enabled;
      final Future<void> stored = storage.set(
        _dataCollectionDefaultEnabledPreferenceKey,
        '$enabled',
      );
      _dataCollectionChangeSink.add(enabled);
      return stored;
    }
    return Future<void>.value();
  }

  void _checkNotDeleted() {
    Preconditions.checkState(!_deleted, 'FirebaseApp was deleted');
  }

  /// Whether this is the default app (its name is [defaultFirebaseAppName]).
  @visibleForTesting
  bool get isDefaultApp => defaultFirebaseAppName == name;

  /// A key derived from the [name] and the application id of this app, for data that a service
  /// stores per app. Same as [getPersistenceKeyFor].
  ///
  /// Throws a [StateError] after [delete].
  String get persistenceKey {
    return getPersistenceKeyFor(name, options.appId);
  }

  /// Forgets every app without deleting it. For tests only.
  @visibleForTesting
  static void clearInstancesForTest() {
    // TODO(long1eu): also delete, once functionality is implemented.
    _instances.clear();
  }

  /// The [persistenceKey] of the app called [name] with [applicationId]: both, base64url encoded
  /// without padding, joined by `+`. Works for an app that was deleted.
  static String getPersistenceKeyFor(String name, String applicationId) {
    final String encodedName = base64Url
        .encode(utf8.encode(name))
        .replaceAll('=', '');
    final String encodedApplicationId = base64Url
        .encode(utf8.encode(applicationId))
        .replaceAll('=', '');

    return '$encodedName+$encodedApplicationId';
  }

  static List<String> _getAllAppNames() {
    final List<String> allAppNames = <String>[];
    for (FirebaseApp app in _instances.values) {
      allAppNames.add(app.name);
    }

    allAppNames.sort();
    return allAppNames;
  }

  /// Normalizes the app name.
  static String _normalize(String name) {
    return name.trim();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FirebaseApp &&
          runtimeType == other.runtimeType &&
          _name == other._name;

  @override
  int get hashCode => _name.hashCode * 31;

  @override
  String toString() {
    return (ToStringHelper(runtimeType) //
          ..add('name', name)
          ..add('options', options))
        .toString();
  }
}

// ignore_for_file: close_sinks
mixin _PlatformDependenciesMixin
    implements PlatformDependencies, LocalStorage, AuthTokenProvider {
  final Map<String, String> _map = <String, String>{};

  PlatformDependencies? get _dependencies;

  BehaviorSubject<bool>? _onBackgroundChanged;
  BehaviorSubject<bool>? _onNetworkConnected;
  HeaderBuilder? _headersBuilder;
  LocalStorage? _storage;
  AuthTokenProvider? _authProvider;
  AppCheckTokenProvider? _appCheckProvider;

  void _initPlatformDependencies() {
    // Without platform dependencies the defaults are created once, so that
    // everything that listens (or adds) works on the same subject.
    _onBackgroundChanged =
        _dependencies?.onBackgroundChanged ??
        BehaviorSubject<bool>.seeded(false);
    _onNetworkConnected =
        _dependencies?.onNetworkConnected ?? BehaviorSubject<bool>.seeded(true);
    _headersBuilder = _dependencies?.headersBuilder;
    _storage = _dependencies?.storage;
    _authProvider = _dependencies?.authProvider;
    _appCheckProvider = _dependencies?.appCheckProvider;
  }

  /// Emits `true` when the app goes to the background and `false` when it comes back.
  ///
  /// The subject of the platform dependencies, read once when the app was created; without
  /// dependencies a subject of its own, seeded with `false`. No service of this repository reads
  /// it.
  @override
  BehaviorSubject<bool> get onBackgroundChanged {
    return _onBackgroundChanged!;
  }

  /// Emits `true` when the device has a network connection and `false` when it lost it.
  ///
  /// The subject of the platform dependencies, read once when the app was created; without
  /// dependencies a subject of its own, seeded with `true`. `cloud_firestore_dart` listens to it
  /// (skipping the current value): a `true` restarts failed streams at once instead of after their
  /// backoff.
  @override
  BehaviorSubject<bool> get onNetworkConnected {
    return _onNetworkConnected!;
  }

  /// The `headersBuilder` of the platform dependencies, or one that returns no headers. No
  /// service of this repository calls it.
  @override
  // ignore: prefer_function_declarations_over_variables
  HeaderBuilder get headersBuilder {
    return _headersBuilder ?? () async => <String, String>{};
  }

  /// The storage of the platform dependencies, or this app itself, which keeps the values in
  /// memory ([get] and [set]).
  @override
  LocalStorage get storage {
    return _storage ?? this;
  }

  /// Where Firestore gets the token it sends with each request: the provider set with the
  /// [authProvider] setter or by the platform dependencies, else this app itself, which has no
  /// user ([getAccessToken] throws). Firestore recognises the app and sends its requests without a
  /// token.
  @override
  AuthTokenProvider get authProvider {
    return _authProvider ?? this;
  }

  /// Replaces the token provider, for example with a `FirebaseUserAuth` or an
  /// `OAuthTokenProvider` of `package:firebase_auth_providers_dart`.
  ///
  /// Set it before the Firestore instance of this app is created: Firestore reads it once. The
  /// setter asks [provider] for a token right away (`forceRefresh: true`) to warm it up; an error
  /// of that request is ignored here, and surfaces when a service asks for a token.
  set authProvider(AuthTokenProvider provider) {
    _authProvider = provider;
    // Warm up the token; a failing provider must not become an unhandled
    // asynchronous error here, callers see it when they ask for a token.
    provider
        .getAccessToken(forceRefresh: true)
        .then<void>((GetTokenResult _) {}, onError: (Object _) {});
  }

  /// The App Check token source, or null when the app has none (the default).
  ///
  /// Firestore sends its token in the `x-firebase-appcheck` header of every request, and
  /// `FirebaseUserAuth` of `package:firebase_auth_providers_dart` in `X-Firebase-AppCheck`.
  @override
  AppCheckTokenProvider? get appCheckProvider => _appCheckProvider;

  /// Replaces the App Check token source; null removes it. Set it before the Firestore instance of
  /// this app (and a `FirebaseUserAuth.forApp`) is created: they read it once.
  set appCheckProvider(AppCheckTokenProvider? provider) {
    _appCheckProvider = provider;
  }

  // LocalStorage implementation

  /// The value stored in memory under [key], or null. Used when the app has no platform
  /// dependencies with a storage of their own; read [storage] instead of calling this.
  @override
  String? get(String key) {
    return _map[key];
  }

  /// Stores [value] in memory under [key]; null removes it. Used when the app has no platform
  /// dependencies with a storage of their own; use [storage] instead of calling this.
  @override
  Future<void> set(String key, String? value) async {
    if (value == null) {
      _map.remove(key);
    } else {
      _map[key] = value;
    }
  }

  // InternalTokenProvider implementation

  /// Always throws a [StateError]: the app is the token provider of last resort, which has no
  /// user. Call `authProvider.getAccessToken` instead.
  @override
  Future<GetTokenResult> getAccessToken({required bool forceRefresh}) async {
    throw StateError('No InternalTokenProvider has been set on this app.');
  }

  /// Always throws a [StateError] (see [getAccessToken]). Read `authProvider.uid` instead.
  @override
  String get uid =>
      throw StateError('No InternalTokenProvider has been set on this app.');

  /// An empty stream (see [getAccessToken]). Listen to `authProvider.onTokenChanged` instead.
  @override
  Stream<AuthTokenChange> get onTokenChanged =>
      const Stream<AuthTokenChange>.empty();
}
