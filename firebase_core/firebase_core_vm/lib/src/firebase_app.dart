// File created by
// Lung Razvan <long1eu>
// on 16/09/2018

import 'dart:async';
import 'dart:convert';

import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:firebase_core_vm/firebase_core_vm.dart';
import 'package:firebase_core_vm/src/firebase_options.dart';
import 'package:firebase_core_vm/src/platform_dependencies.dart';
import 'package:meta/meta.dart';
import 'package:rxdart/rxdart.dart';

class FirebaseApp with _PlatformDependenciesMixin {
  FirebaseApp._(this._name, this._options, this._dependencies,
      this._dataCollectionDefaultEnabled);

  /// Initializes a [FirebaseApp] instance with [options] and [name].
  ///
  /// If the name is not provided the [DEFAULT] app will be created. It is an
  /// error to initialize an app with an already existing name.
  factory FirebaseApp.withOptions(
    FirebaseOptions options, {
    PlatformDependencies dependencies,
    String name = defaultAppName,
  }) {
    if (isWeb) {
      throw UnimplementedError(
          'This library doesn\'t work on the web. Try the official Firebase Web SDK.');
    }
    final String normalizedName = _normalize(name);

    Preconditions.checkState(!_instances.containsKey(normalizedName),
        'FirebaseApp name $normalizedName already exists!');

    final LocalStorage storage = dependencies?.storage;
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
    final FirebaseApp defaultApp = _instances[defaultAppName];
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
    final FirebaseApp firebaseApp = _instances[_normalize(name)];
    if (firebaseApp != null) {
      return firebaseApp;
    }

    final List<String> availableAppNames = _getAllAppNames();
    final String availableAppNamesMessage = availableAppNames.isNotEmpty
        ? 'Available app names: ${availableAppNames.join(', ')}.'
        : '';

    throw StateError(
        'FirebaseApp with name $name does\'t exist. $availableAppNamesMessage');
  }

  static const String defaultAppName = '[DEFAULT]';

  static final Map<String, FirebaseApp> _instances = <String, FirebaseApp>{};
  static const String _dataCollectionDefaultEnabledPreferenceKey =
      'firebase_data_collection_default_enabled';

  final String _name;
  final FirebaseOptions _options;
  @override
  final PlatformDependencies _dependencies;

  final StreamController<bool> _dataCollectionChangeSink =
      StreamController<bool>.broadcast();
  final StreamController<String> _deleteSink =
      StreamController<String>.broadcast();

  bool _automaticResourceManagementEnabled = false;
  bool _deleted = false;
  bool _dataCollectionDefaultEnabled;

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

  void delete() {
    if (_deleted) {
      return;
    }

    _deleted = true;
    _instances.remove(this);
    _deleteSink.add(_name);
  }

  /// If set to true it indicates that Firebase should close database
  /// connections automatically when the app is in the background.
  /// Disabled by default.
  void setAutomaticResourceManagementEnabled({bool enabled}) {
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
  void setDataCollectionDefaultEnabled({bool enabled = false}) {
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

  @visibleForTesting
  bool get isDefaultApp => defaultAppName == name;

  /// Use this key to store data per FirebaseApp.
  String get persistenceKey {
    return getPersistenceKeyFor(name, options.applicationId);
  }

  @visibleForTesting
  static void clearInstancesForTest() {
    // TODO(long1eu): also delete, once functionality is implemented.
    _instances.clear();
  }

  /// Returns persistence key. Exists to support getting [FirebaseApp]
  /// persistence key after the app has been deleted.
  static String getPersistenceKeyFor(String name, String applicationId) {
    final String encodedName =
        base64Encode(utf8.encode(name)).replaceAll('=', '');
    final String encodedApplicationId =
        base64Encode(utf8.encode(applicationId)).replaceAll('=', '');

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
    assert(name != null);
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

  PlatformDependencies get _dependencies;

  BehaviorSubject<bool> _onBackgroundChanged;
  BehaviorSubject<bool> _onNetworkConnected;
  HeaderBuilder _headersBuilder;
  LocalStorage _storage;
  InternalTokenProvider _authProvider;

  void _initPlatformDependencies() {
    _onBackgroundChanged = _dependencies?.onBackgroundChanged;
    _onNetworkConnected = _dependencies?.onNetworkConnected;
    _headersBuilder = _dependencies?.headersBuilder;
    _storage = _dependencies?.storage;
    _authProvider = _dependencies?.authProvider;
  }

  /// This stream should emit true then the app enters in background and false otherwise
  @override
  BehaviorSubject<bool> get onBackgroundChanged {
    return _onBackgroundChanged ?? BehaviorSubject<bool>.seeded(false);
  }

  /// This stream should emit true when there is an internet connection and false otherwise
  @override
  BehaviorSubject<bool> get onNetworkConnected {
    return _onNetworkConnected ?? BehaviorSubject<bool>.seeded(true);
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
    this
      .._authProvider = provider
      .._authProvider.getAccessToken(forceRefresh: true);
  }

  // LocalStorage implementation

  @override
  String get(String key) {
    return _map[key];
  }

  @override
  Future<void> set(String key, String value) async {
    if (value == null) {
      _map.remove(key);
    } else {
      _map[key] = value;
    }
  }

  // InternalTokenProvider implementation

  @override
  Future<GetTokenResult> getAccessToken({@required bool forceRefresh}) async {
    return null;
  }

  @override
  String get uid => null;

  @override
  Stream<InternalTokenResult> get onTokenChanged =>
      BehaviorSubject<InternalTokenResult>.seeded(null);
}
