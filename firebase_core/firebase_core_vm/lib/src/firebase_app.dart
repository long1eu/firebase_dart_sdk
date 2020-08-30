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

class FirebaseApp extends _PlatformDependencies {
  FirebaseApp._(
    this._name,
    this._options,
    this._dependencies,
  )   : assert(_name != null && _name.trim().isNotEmpty),
        assert(_options != null),
        assert(_dependencies != null);

  /// Initializes a [FirebaseApp] instance with [options] and [name].
  ///
  /// If the name is not provided the [DEFAULT] app will be created. It is an error to initialize an app with an already
  /// existing name.
  factory FirebaseApp.withOptions(
    FirebaseOptions options, {
    PlatformDependencies dependencies,
    String name = defaultAppName,
  }) {
    if (kIsWeb) {
      throw UnimplementedError("This library doesn't work on the web. Try the official Firebase Web SDK.");
    }
    final String normalizedName = _normalize(name);
    Preconditions.checkState(
      !_instances.containsKey(normalizedName),
      'FirebaseApp name $normalizedName already exists!',
    );
    Preconditions.checkState(
      normalizedName.trim().isNotEmpty,
      'FirebaseApp name must not be an empty string!',
    );

    final FirebaseApp firebaseApp = FirebaseApp._(normalizedName, options, dependencies) //
      .._initPlatformDependencies();
    _instances[normalizedName] = firebaseApp;
    return firebaseApp;
  }

  /// Returns the default instance of the [FirebaseApp].
  ///
  /// Throws StateError if the default app was not initialized.
  static FirebaseApp get instance {
    final FirebaseApp defaultApp = _instances[defaultAppName];
    if (defaultApp == null) {
      throw StateError('Default FirebaseApp is not initialized. Make sure to call [FirebaseApp.withOptions()] first.');
    }

    return defaultApp;
  }

  /// Returns the instance identified by the unique name, or throws if it does
  /// not exist.
  static FirebaseApp getInstance(String name) {
    final FirebaseApp firebaseApp = _instances[_normalize(name)];
    if (firebaseApp != null) {
      return firebaseApp;
    }

    final List<String> availableAppNames = _getAllAppNames();
    final String availableAppNamesMessage =
        availableAppNames.isNotEmpty ? 'Available app names: ${availableAppNames.join(', ')}.' : '';

    throw StateError('FirebaseApp with name $name does\'t exist. $availableAppNamesMessage');
  }

  static const String defaultAppName = '[DEFAULT]';

  static final Map<String, FirebaseApp> _instances = <String, FirebaseApp>{};
  static const String _dataCollectionKey = 'firebase_data_collection_default_enabled';

  final String _name;
  final FirebaseOptions _options;
  @override
  final PlatformDependencies _dependencies;

  final StreamController<bool> _dataCollectionChangeSink = StreamController<bool>.broadcast();
  final StreamController<String> _deleteSink = StreamController<String>.broadcast();

  bool _automaticResourceManagementEnabled = false;
  bool _deleted = false;

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
  bool get dataCollectionEnabled {
    _checkNotDeleted();

    final String storeValue = get(_dataCollectionKey);
    if (storeValue == null) {
      return options.dataCollectionEnabled;
    } else {
      return storeValue == 'true';
    }
  }

  /// Enable or disable automatic data collection across all SDKs.
  ///
  /// Note: this value is respected by all SDKs unless overridden by the
  /// developer via SDK specific mechanisms.
  set dataCollectionEnabled(bool enabled) {
    _checkNotDeleted();
    if (dataCollectionEnabled != enabled) {
      storage.set(_dataCollectionKey, '$enabled');
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
    return getPersistenceKeyFor(name, options.appId);
  }

  @visibleForTesting
  static void clearInstancesForTest() {
    // TODO(long1eu): also delete, once functionality is implemented.
    _instances.clear();
  }

  /// Returns persistence key. Exists to support getting [FirebaseApp]
  /// persistence key after the app has been deleted.
  static String getPersistenceKeyFor(String name, String applicationId) {
    final String encodedName = base64Encode(utf8.encode(name)).replaceAll('=', '');
    final String encodedApplicationId = base64Encode(utf8.encode(applicationId)).replaceAll('=', '');

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
      other is FirebaseApp && //
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
abstract class _PlatformDependencies extends PlatformDependencies implements InternalTokenProvider {
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
  HeaderBuilder get headersBuilder {
    return _headersBuilder ?? () => Future<Map<String, String>>.value(<String, String>{});
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

  @override
  Future<GetTokenResult> getAccessToken({@required bool forceRefresh}) {
    return Future<GetTokenResult>.value();
  }

  @override
  String get uid => null;

  @override
  Stream<InternalTokenResult> get onTokenChanged => const Stream<InternalTokenResult>.empty();
}
