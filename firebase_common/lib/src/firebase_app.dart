// File created by
// Lung Razvan <long1eu>
// on 16/09/2018

import 'dart:async';

import 'package:firebase_common/src/annotations.dart';
import 'package:firebase_common/src/auth/get_token_result.dart';
import 'package:firebase_common/src/data_collection_default_change.dart';
import 'package:firebase_common/src/errors/firebase_api_not_available_error.dart';
import 'package:firebase_common/src/firebase_app_lifecycle_observer.dart';
import 'package:firebase_common/src/firebase_options.dart';
import 'package:firebase_common/src/flutter/lifecycle_handler.dart';
import 'package:firebase_common/src/internal/internal_token_provider.dart';
import 'package:firebase_common/src/internal/internal_token_result.dart';
import 'package:firebase_common/src/util/base64_utils.dart';
import 'package:firebase_common/src/util/log.dart';
import 'package:firebase_common/src/util/preconditions.dart';
import 'package:firebase_common/src/util/prefs.dart';
import 'package:firebase_common/src/util/to_string_helper.dart';
import 'package:meta/meta.dart';

typedef void InitializeApis(FirebaseApp firebaseApp);

@publicApi
class FirebaseApp {
  static const String logTag = 'FirebaseApp';
  static const String defaultAppName = '[DEFAULT]';

  static const String firebaseAppPrefs = 'com.google.firebase.common.prefs';
  @visibleForTesting
  static const String _dataCollectionDefaultEnabledPreferenceKey =
      "firebase_data_collection_default_enabled";

  static final Map<String, FirebaseApp> instances = <String, FirebaseApp>{};

  final String _name;
  final FirebaseOptions _options;
  final InitializeApis initializeApis;
  final Prefs _prefs;
  final LifecycleHandler lifecycleHandler;

  final StreamController<dynamic> _events =
      StreamController<dynamic>.broadcast();
  final List<IdTokenObserver> _idTokenObservers = <IdTokenObserver>[];
  final List<BackgroundStateChangeObserver> backgroundStateChangeObservers =
      <BackgroundStateChangeObserver>[];
  final List<FirebaseAppLifecycleObserver> _lifecycleObservers =
      <FirebaseAppLifecycleObserver>[];

  // Default disabled. We released Firebase publicly without this feature, so
  // making it default enabled is a backwards incompatible change.
  bool automaticResourceManagementEnabled = false;
  bool deleted = false;
  bool _dataCollectionDefaultEnabled;

  InternalTokenProvider _tokenProvider;
  IdTokenObserversCountChangedObserver _idTokenObserversCountChangedObserver;

  FirebaseApp._(this._name, this._options, this._prefs, this.initializeApis,
      [this.lifecycleHandler]);

  /// Initializes the default FirebaseApp instance using string resource values
  /// populated from the map you provide. It also initializes Firebase
  /// Analytics. Returns the default FirebaseApp, if either it has been
  /// initialized previously, or Firebase API keys are present in string
  /// resources. Returns null otherwise.
  ///
  /// * This method should be called at app startup.
  /// * The [FirebaseOptions] values used by the default app instance are read
  /// from string resources.
  @publicApi
  factory FirebaseApp(
    Map<String, String> json,
    InitializeApis appInit,
    Prefs prefs, [
    LifecycleHandler lifecycleHandler,
  ]) {
    if (instances.containsKey(defaultAppName)) {
      return instance;
    }

    final FirebaseOptions firebaseOptions = FirebaseOptions.fromJson(json);
    if (firebaseOptions == null) {
      Log.d(
          logTag,
          'Default FirebaseApp failed to initialize because no default options '
          'were found. This usually means that you don\'t have the '
          'google-services.json into you assets folder or you didn\'t add'
          'it to your pubspec.yaml file. \n We tried $json.');
    }

    return FirebaseApp.withOptions(
        firebaseOptions, appInit, prefs, defaultAppName, lifecycleHandler);
  }

  /**
   * Initializes the default {@link FirebaseApp} instance. Same as {@link #initializeApp(Context,
   * FirebaseOptions, String)}, but it uses {@link #DEFAULT_APP_NAME} as name.
   *
   * <p>It's only required to call this to initialize Firebase if it's <strong>not possible</strong>
   * to do so automatically in {@link com.google.firebase.provider.FirebaseInitProvider}. Automatic
   * initialization that way is the expected situation.
   * A factory method to initialize a {@link FirebaseApp}.
   *
   * @param context represents the {@link Context}
   * @param options represents the global {@link FirebaseOptions}
   * @param name unique name for the app. It is an error to initialize an app with an already
   *     existing name. Starting and ending whitespace characters in the name are ignored (trimmed).
   * @throws IllegalStateException if an app with the same name has already been initialized.
   * @return an instance of {@link FirebaseApp}
   */
  factory FirebaseApp.withOptions(
    FirebaseOptions options,
    InitializeApis appInit,
    Prefs prefs, [
    String name = defaultAppName,
    LifecycleHandler lifecycleHandler,
  ]) {
    final String normalizedName = _normalize(name);

    Preconditions.checkState(!instances.containsKey(normalizedName),
        'FirebaseApp name $normalizedName already exists!');

    final FirebaseApp firebaseApp = FirebaseApp._(
        normalizedName, options, prefs, appInit, lifecycleHandler);
    instances[normalizedName] = firebaseApp;
    firebaseApp.initializeAllApis();

    return firebaseApp;
  }

  /// Returns the default (first initialized) instance of the [FirebaseApp].
  /// Throws StateError if the default app was not initialized.
  @publicApi
  static FirebaseApp get instance {
    final FirebaseApp defaultApp = instances[defaultAppName];
    if (defaultApp == null) {
      throw StateError(
          'Default FirebaseApp is not initialized. Make sure to call '
          '[FirebaseApp.initializeApp()] first.');
    }

    return defaultApp;
  }

  /// Returns the instance identified by the unique name, or throws if it does
  /// not exist.
  ///
  /// [name] represents the name of the [FirebaseApp] instance. It throws
  /// [StateError] if the [FirebaseApp] was not initialized, via [initializeApp]
  @publicApi
  static FirebaseApp getInstance(String name) {
    final FirebaseApp firebaseApp = instances[_normalize(name)];
    if (firebaseApp != null) {
      return firebaseApp;
    }

    final List<String> availableAppNames = _getAllAppNames();
    String availableAppNamesMessage = availableAppNames.isNotEmpty
        ? 'Available app names: ${availableAppNames.join(', ')}.'
        : '';

    throw StateError(
        'FirebaseApp with name $name does\'t exist. $availableAppNamesMessage');
  }

  /// Returns the unique name of this app.
  @publicApi
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
  List<FirebaseApp> get apps => List<FirebaseApp>.from(instances.values);

  @deprecated
  @keepForSdk
  set tokenProvider(InternalTokenProvider tokenProvider) {
    _tokenProvider = Preconditions.checkNotNull(tokenProvider);
  }

  set idTokenObserversCountChangedObserver(
      IdTokenObserversCountChangedObserver observer) {
    _idTokenObserversCountChangedObserver =
        Preconditions.checkNotNull(observer);
    // Immediately trigger so that the observer observer can properly decide if
    // it needs to start out as active.
    _idTokenObserversCountChangedObserver
        .onObserversCountChanged(_idTokenObservers.length);
  }

  /// (deprecated, use [InternalAuthProvider.getToken] from firebase_auth)
  ///
  /// Fetch a valid STS Token.
  ///
  /// [forceRefresh] force refreshes the token. Should only be set to true if
  /// the token is invalidated out of band.
  @deprecated
  @keepForSdk
  Future<GetTokenResult> getToken(bool forceRefresh) {
    _checkNotDeleted();

    if (_tokenProvider == null) {
      return Future.error(
          FirebaseApiNotAvailableError('firebase_auth is not linked,'
              ' please fall back to unauthenticated mode.'));
    } else {
      return _tokenProvider.getAccessToken(forceRefresh);
    }
  }

  /// (deprecated, use [InternalAuthProvider.uid] from firebase_auth)
  ///
  /// Fetch the UID of the currently logged-in user.
  @deprecated
  @keepForSdk
  String get uid {
    _checkNotDeleted();
    if (_tokenProvider == null) {
      throw FirebaseApiNotAvailableError('firebase_auth is not linked,'
          ' please fall back to unauthenticated mode.');
    } else {
      return _tokenProvider.uid;
    }
  }

  @publicApi
  void delete() {
    if (deleted) {
      return;
    }

    deleted = true;
    instances.remove(this);
    _notifyOnAppDeleted();
  }

  @keepForSdk
  Stream<dynamic> get events => _events.stream;

  /// If set to true it indicates that Firebase should close database
  /// connections automatically when the app is in the background.
  /// Disabled by default.
  @publicApi
  void setAutomaticResourceManagementEnabled(bool enabled) {
    _checkNotDeleted();

    if (automaticResourceManagementEnabled != enabled) {
      automaticResourceManagementEnabled = enabled;

      bool inBackground = lifecycleHandler.isBackground;
      if (enabled && inBackground) {
        // Automatic resource management has been enabled while the app is in the
        // background, notify the listeners of the app being in the background.
        notifyBackgroundStateChangeObservers(true);
      } else if (!enabled && inBackground) {
        // Automatic resource management has been disabled while the app is in the
        // background, act as if we were in the foreground.
        notifyBackgroundStateChangeObservers(false);
      }
    }
  }

  /// Determine whether automatic data collection is enabled or disabled by
  /// default in all SDKs. Returns true if automatic data collection is enabled
  /// by default and false otherwise
  ///
  /// * Note: this value is respected by all SDKs unless overridden by the
  /// developer via SDK specific mechanisms.
  @keepForSdk
  bool get dataCollectionDefaultEnabled {
    _checkNotDeleted();
    return _dataCollectionDefaultEnabled;
  }

  /// Enable or disable automatic data collection across all SDKs.
  ///
  /// * Note: this value is respected by all SDKs unless overridden by the
  /// developer via SDK specific mechanisms.
  @keepForSdk
  void setDataCollectionDefaultEnabled(bool enabled) {
    _checkNotDeleted();
    if (_dataCollectionDefaultEnabled != enabled) {
      _dataCollectionDefaultEnabled = enabled;

      _prefs.setBool(_dataCollectionDefaultEnabledPreferenceKey, enabled);

      _events.add(DataCollectionDefaultChange(enabled));
    }
  }

  bool _readAutoDataCollectionEnabled() {
    if (_prefs.contains(_dataCollectionDefaultEnabledPreferenceKey)) {
      return _prefs.getBool(_dataCollectionDefaultEnabledPreferenceKey) ?? true;
    }

    return options.dataCollectionEnabled ?? true;
  }

  void _checkNotDeleted() {
    Preconditions.checkState(!deleted, 'FirebaseApp was deleted');
  }

  @deprecated
  @keepForSdk
  List<IdTokenObserver> get observers {
    _checkNotDeleted();
    return _idTokenObservers;
  }

  @keepForSdk
  @visibleForTesting
  bool get isDefaultApp => defaultAppName == name;

  @deprecated
  @keepForSdk
  void notifyIdTokenListeners(InternalTokenResult tokenResult) {
    Log.d(logTag, "Notifying auth state observers.");
    int size = 0;
    for (IdTokenObserver observer in _idTokenObservers) {
      observer.onIdTokenChanged(tokenResult);
      size++;
    }
    Log.d(logTag, 'Notified $size auth state listeners.');
  }

  void notifyBackgroundStateChangeObservers(bool background) {
    Log.d(logTag, "Notifying background state change observers.");
    for (BackgroundStateChangeObserver observer
        in backgroundStateChangeObservers) {
      observer.onBackgroundStateChanged(background);
    }
  }

  /// (Deprecated, use [InternalAuthProvider.addIdTokenListener]) from
  /// firebase_auth)
  ///
  /// Adds a [IdTokenListener] to the list of interested observers. [observer]
  /// represents the [IdTokenListener] that needs to be notified when we have
  /// changes in user state.
  @deprecated
  @keepForSdk
  void addIdTokenObserver(IdTokenObserver observer) {
    _checkNotDeleted();
    Preconditions.checkNotNull(observer);
    _idTokenObservers.add(observer);
    _idTokenObserversCountChangedObserver
        .onObserversCountChanged(_idTokenObservers.length);
  }

  /// (Deprecated, use [InternalAuthProvider.removeIdTokenListener]) from
  /// firebase_auth)
  ///
  /// Removes a [IdTokenListener] from the list of interested observers.
  /// [observerToRemove] represents the instance of [IdTokenListener] to be
  /// removed.
  @deprecated
  @keepForSdk
  void removeIdTokenObserver(IdTokenObserver observerToRemove) {
    _checkNotDeleted();
    Preconditions.checkNotNull(observerToRemove);
    _idTokenObservers.remove(observerToRemove);
    _idTokenObserversCountChangedObserver
        .onObserversCountChanged(_idTokenObservers.length);
  }

  /// Registers a background state change observer. Make sure to call
  /// [removeBackgroundStateChangeListener] as appropriate to avoid memory
  /// leaks.
  ///
  /// * If automatic resource management is enabled and the app is in the
  /// background a callback is triggered immediately.
  /// see [BackgroundStateChangeListener]
  @keepForSdk
  void addBackgroundStateChangeObserver(
      BackgroundStateChangeObserver observer) {
    _checkNotDeleted();
    if (automaticResourceManagementEnabled && lifecycleHandler.isBackground) {
      observer.onBackgroundStateChanged(true /* isInBackground */);
    }
    backgroundStateChangeObservers.add(observer);
  }

  /// Unregisters the background state change listener.
  @keepForSdk
  void removeBackgroundStateChangeObserver(
      BackgroundStateChangeObserver observer) {
    _checkNotDeleted();
    backgroundStateChangeObservers.remove(observer);
  }

  /// Use this key to store data per FirebaseApp.
  @keepForSdk
  String get persistenceKey {
    return '${Base64Utils.encodeUrlSafeNoPadding(name.codeUnits)}+'
        '${Base64Utils.encodeUrlSafeNoPadding(options.applicationId.codeUnits)}';
  }

  /// If an API has locally stored data it must register lifecycle listeners at
  /// initialization time.
  @keepForSdk
  void addLifecycleEventListener(FirebaseAppLifecycleObserver observer) {
    _checkNotDeleted();
    Preconditions.checkNotNull(observer);
    _lifecycleObservers.add(observer);
  }

  @keepForSdk
  void removeLifecycleEventListener(FirebaseAppLifecycleObserver observer) {
    _checkNotDeleted();
    Preconditions.checkNotNull(observer);
    _lifecycleObservers.remove(observer);
  }

  /// Notifies all observers with the name and options of the deleted
  /// [FirebaseApp] instance.
  void _notifyOnAppDeleted() {
    for (FirebaseAppLifecycleObserver observer in _lifecycleObservers) {
      observer.onDeleted(name, options);
    }
  }

  @visibleForTesting
  static void clearInstancesForTest() {
    // TODO: also delete, once functionality is implemented.
    instances.clear();
  }

  /// Returns persistence key. Exists to support getting [FirebaseApp]
  /// persistence key after the app has been deleted.
  @keepForSdk
  static String getPersistenceKeyFor(String name, FirebaseOptions options) {
    return '${Base64Utils.encodeUrlSafeNoPadding(name.codeUnits)}+'
        '${Base64Utils.encodeUrlSafeNoPadding(options.applicationId.codeUnits)}';
  }

  static List<String> _getAllAppNames() {
    List<String> allAppNames = <String>[];
    for (FirebaseApp app in instances.values) {
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

  void initializeAllApis() {
    initializeApis(this);
    /* Initialize this(call getInstance()):
      private static final String MEASUREMENT_CLASSNAME = "com.google.android.gms.measurement.AppMeasurement";
      private static final String AUTH_CLASSNAME = "com.google.firebase.auth.FirebaseAuth";
      private static final String IID_CLASSNAME = "com.google.firebase.iid.FirebaseInstanceId";
      private static final String CRASH_CLASSNAME = "com.google.firebase.crash.FirebaseCrash";
    */
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FirebaseApp &&
          runtimeType == other.runtimeType &&
          _name == other._name;

  @override
  int get hashCode => _name.hashCode;

  @override
  String toString() {
    return (ToStringHelper(runtimeType)
          ..add('name', name)
          ..add('options', options))
        .toString();
  }
}

/// (deprecated, use [IdTokenObserver] in firebase-auth)
///
/// Used to deliver notifications when authentication state changes.
@deprecated
@keepForSdk
abstract class IdTokenObserver {
  /// The method which gets invoked authentication state has changed.
  ///
  /// [tokenResult] represents the [InternalTokenResult], which can be used to
  /// obtain a cached access token.
  @keepForSdk
  void onIdTokenChanged(InternalTokenResult tokenResult);
}

/// Used to signal to FirebaseAuth when there are internal observers, so that we
/// know whether or not to do proactive token refreshing.
@deprecated
@keepForSdk
abstract class IdTokenObserversCountChangedObserver {
  /// To be called with the new number of auth state observers on any events
  /// which change the number of observers. Also triggered when
  /// [FirebaseApp.idTokenObserversCountChangedObserver] is called.
  @keepForSdk
  void onObserversCountChanged(int numObservers);
}

/// Used to deliver notifications about whether the app is in the background.
/// The first callback is invoked inline if the app is in the background.
///
/// * If the app is in the background and
/// [FirebaseApp.setAutomaticResourceManagementEnabled] is set to false.
@keepForSdk
abstract class BackgroundStateChangeObserver {
  /// [background] is true, if the app is in the background and automatic
  /// resource management is enabled.
  @keepForSdk
  void onBackgroundStateChanged(bool background);
}
