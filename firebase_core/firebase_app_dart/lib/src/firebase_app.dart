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

/// The entry point of the Firebase SDKs: a named set of [FirebaseOptions] shared by the Firebase
/// services of one project.
///
/// Create one with [FirebaseApp.withOptions]. The app created without a name is the default app,
/// returned by [FirebaseApp.instance].
class FirebaseApp with _PlatformDependenciesMixin {
  FirebaseApp._(this._name, this._options, this._dependencies,
      this._dataCollectionDefaultEnabled);

  /// Initializes a [FirebaseApp] instance with [options] and [name].
  ///
  /// If the name is not provided the default app (named `[DEFAULT]`) will be created. It is an
  /// error to initialize an app with an already existing name.
  factory FirebaseApp.withOptions(
    FirebaseOptions options, {
    PlatformDependencies? dependencies,
    String name = defaultAppName,
  }) {
    final String normalizedName = _normalize(name);

    // The const constructor of [FirebaseOptions] only checks this with an
    // assert, which a release build skips.
    if (options.applicationId.isEmpty) {
      throw ArgumentError.value(options.applicationId,
          'options.applicationId', 'ApplicationId must be set.');
    }
    Preconditions.checkState(!_instances.containsKey(normalizedName),
        'FirebaseApp name $normalizedName already exists!');

    final LocalStorage? storage = dependencies?.storage;
    final String _dataCollectionDefaultEnabled =
        storage?.get(_dataCollectionDefaultEnabledPreferenceKey) ?? 'true';
    final FirebaseApp firebaseApp = FirebaseApp._(
      normalizedName,
      options,
      dependencies,
      _dataCollectionDefaultEnabled == 'true',
    ).._initPlatformDependencies();
    _instances[normalizedName] = firebaseApp;
    return firebaseApp;
  }

  /// Returns the default (first initialized) instance of the [FirebaseApp].
  /// Throws StateError if the default app was not initialized.
  static FirebaseApp get instance {
    final FirebaseApp? defaultApp = _instances[defaultAppName];
    if (defaultApp == null) {
      throw StateError(
          'Default FirebaseApp is not initialized. Make sure to call [FirebaseApp()] or [FirebaseApp.withOptions()] first.');
    }

    return defaultApp;
  }

  /// Returns the instance identified by the unique name, or throws if it does
  /// not exist.
  ///
  /// [name] represents the name of the [FirebaseApp] instance.
  static FirebaseApp getInstance(String name) {
    final FirebaseApp? firebaseApp = _instances[_normalize(name)];
    if (firebaseApp != null) {
      return firebaseApp;
    }

    final List<String> availableAppNames = _getAllAppNames();
    final String availableAppNamesMessage = availableAppNames.isNotEmpty
        ? 'Available app names: ${availableAppNames.join(', ')}.'
        : '';

    throw StateError(
        'FirebaseApp with name $name doesn\'t exist. $availableAppNamesMessage');
  }

  /// The name of the default app.
  static const String defaultAppName = '[DEFAULT]';

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

  /// Emits the new value every time [setDataCollectionDefaultEnabled] changes it.
  Stream<bool> get onDataCollectionChange => _dataCollectionChangeSink.stream;

  /// An event is emitted when [FirebaseApp.delete] is called.
  Stream<String> get onDeleteApp => _deleteSink.stream;

  /// Returns the unique name of this app.
  String get name {
    _checkNotDeleted();
    return _name;
  }

  /// Returns the specified [FirebaseOptions].
  FirebaseOptions get options {
    _checkNotDeleted();
    return _options;
  }

  /// Returns a mutable list of all FirebaseApps.
  static List<FirebaseApp> get apps {
    return List<FirebaseApp>.from(_instances.values);
  }

  /// Deletes this app: it is removed from [apps], [onDeleteApp] emits its name, and reading its
  /// [name] or [options] afterwards throws a [StateError]. Deleting twice is a no-op.
  void delete() {
    if (_deleted) {
      return;
    }

    _deleted = true;
    _instances.remove(_name);
    _deleteSink.add(_name);
  }

  /// If set to true it indicates that Firebase should close database
  /// connections automatically when the app is in the background.
  /// Disabled by default.
  void setAutomaticResourceManagementEnabled({required bool enabled}) {
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
  }

  /// Determine whether automatic data collection is enabled or disabled by
  /// default in all SDKs. Returns true if automatic data collection is enabled
  /// by default and false otherwise
  ///
  /// Note: this value is respected by all SDKs unless overridden by the
  /// developer via SDK specific mechanisms.
  bool get dataCollectionDefaultEnabled {
    _checkNotDeleted();
    return _dataCollectionDefaultEnabled;
  }

  /// Enable or disable automatic data collection across all SDKs.
  ///
  /// Note: this value is respected by all SDKs unless overridden by the
  /// developer via SDK specific mechanisms.
  void setDataCollectionDefaultEnabled({required bool enabled}) {
    _checkNotDeleted();
    if (_dataCollectionDefaultEnabled != enabled) {
      _dataCollectionDefaultEnabled = enabled;
      storage.set(_dataCollectionDefaultEnabledPreferenceKey, '$enabled');
      _dataCollectionChangeSink.add(enabled);
    }
  }

  void _checkNotDeleted() {
    Preconditions.checkState(!_deleted, 'FirebaseApp was deleted');
  }

  /// Whether this is the default app (its name is [defaultAppName]).
  @visibleForTesting
  bool get isDefaultApp => defaultAppName == name;

  /// Use this key to store data per FirebaseApp.
  String get persistenceKey {
    return getPersistenceKeyFor(name, options.applicationId);
  }

  /// Forgets every app without deleting it. For tests only.
  @visibleForTesting
  static void clearInstancesForTest() {
    // TODO(long1eu): also delete, once functionality is implemented.
    _instances.clear();
  }

  /// Returns persistence key. Exists to support getting [FirebaseApp]
  /// persistence key after the app has been deleted.
  static String getPersistenceKeyFor(String name, String applicationId) {
    final String encodedName =
        base64Url.encode(utf8.encode(name)).replaceAll('=', '');
    final String encodedApplicationId =
        base64Url.encode(utf8.encode(applicationId)).replaceAll('=', '');

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
    implements PlatformDependencies, LocalStorage, InternalTokenProvider {
  final Map<String, String> _map = <String, String>{};

  PlatformDependencies? get _dependencies;

  BehaviorSubject<bool>? _onBackgroundChanged;
  BehaviorSubject<bool>? _onNetworkConnected;
  HeaderBuilder? _headersBuilder;
  LocalStorage? _storage;
  InternalTokenProvider? _authProvider;
  InternalAppCheckTokenProvider? _appCheckProvider;

  void _initPlatformDependencies() {
    // Without platform dependencies the defaults are created once, so that
    // everything that listens (or adds) works on the same subject.
    _onBackgroundChanged = _dependencies?.onBackgroundChanged ??
        BehaviorSubject<bool>.seeded(false);
    _onNetworkConnected =
        _dependencies?.onNetworkConnected ?? BehaviorSubject<bool>.seeded(true);
    _headersBuilder = _dependencies?.headersBuilder;
    _storage = _dependencies?.storage;
    _authProvider = _dependencies?.authProvider;
    _appCheckProvider = _dependencies?.appCheckProvider;
  }

  /// This stream should emit true then the app enters in background and false otherwise
  @override
  BehaviorSubject<bool> get onBackgroundChanged {
    return _onBackgroundChanged!;
  }

  /// This stream should emit true when there is an internet connection and false otherwise
  @override
  BehaviorSubject<bool> get onNetworkConnected {
    return _onNetworkConnected!;
  }

  @override
  // ignore: prefer_function_declarations_over_variables
  HeaderBuilder get headersBuilder {
    return _headersBuilder ?? () async => <String, String>{};
  }

  @override
  LocalStorage get storage {
    return _storage ?? this;
  }

  @override
  InternalTokenProvider get authProvider {
    return _authProvider ?? this;
  }

  // FirebaseAuth can set it self to be the InternalTokenProvider if the user hasn't set one already
  set authProvider(InternalTokenProvider provider) {
    _authProvider = provider;
    // Warm up the token; a failing provider must not become an unhandled
    // asynchronous error here, callers see it when they ask for a token.
    provider
        .getAccessToken(forceRefresh: true)
        .then<void>((GetTokenResult _) {}, onError: (Object _) {});
  }

  /// The App Check token source, or null when the app has none.
  @override
  InternalAppCheckTokenProvider? get appCheckProvider => _appCheckProvider;

  set appCheckProvider(InternalAppCheckTokenProvider? provider) {
    _appCheckProvider = provider;
  }

  // LocalStorage implementation

  @override
  String? get(String key) {
    return _map[key];
  }

  @override
  Future<void> set(String key, String? value) async {
    if (value == null) {
      _map.remove(key);
    } else {
      _map[key] = value;
    }
  }

  // InternalTokenProvider implementation

  @override
  Future<GetTokenResult> getAccessToken({required bool forceRefresh}) async {
    throw StateError('No InternalTokenProvider has been set on this app.');
  }

  @override
  String get uid =>
      throw StateError('No InternalTokenProvider has been set on this app.');

  @override
  Stream<InternalTokenResult> get onTokenChanged =>
      const Stream<InternalTokenResult>.empty();
}
