// File created by
// Lung Razvan <long1eu>
// on 16/09/2018

import 'dart:async';

import 'package:firebase_common/src/annotations.dart';
import 'package:firebase_common/src/data_collection_default_change.dart';
import 'package:firebase_common/src/firebase_options.dart';
import 'package:firebase_common/src/internal/internal_token_provider.dart';
import 'package:firebase_common/src/internal/shared_preferences.dart';
import 'package:firebase_common/src/util/base64_utils.dart';
import 'package:firebase_common/src/util/log.dart';
import 'package:firebase_common/src/util/preconditions.dart';
import 'package:firebase_common/src/util/to_string_helper.dart';
import 'package:meta/meta.dart';

typedef InitializeApis = void Function(FirebaseApp firebaseApp);

/// The signature that gets called when [FirebaseApp] gets deleted. This is
/// triggered when [FirebaseApp.delete] is called. [FirebaseApp] public
/// methods start throwing after delete is called, so name and options are
/// passed in to be able to identify the instance.
typedef OnFirebaseAppDelete = void Function(
    String firebaseAppName, FirebaseOptions options);

/// Used to deliver notifications about whether the app is in the background.
/// The first callback is invoked inline if the app is in the background.
///
/// [isInBackground] is true, if the app is in the background and automatic
/// resource management is enabled.
@keepForSdk
typedef OnBackgroundStateChanged = void Function(
    {@required bool isInBackground});

typedef IsBackground = bool Function();

@publicApi
class FirebaseApp {
  static const String logTag = 'FirebaseApp';
  static const String defaultAppName = '[DEFAULT]';

  static const String firebaseAppPrefs = 'com.google.firebase.common.prefs';
  @visibleForTesting
  static const String _dataCollectionDefaultEnabledPreferenceKey =
      'firebase_data_collection_default_enabled';

  static final Map<String, FirebaseApp> instances = <String, FirebaseApp>{};

  final String _name;
  final FirebaseOptions _options;
  final InitializeApis initializeApis;
  final SharedPreferences _prefs;
  final InternalTokenProvider getAuthProvider;

  final StreamController<dynamic> _events =
      StreamController<dynamic>.broadcast();
  final List<OnBackgroundStateChanged> backgroundStateChangeObservers =
      <OnBackgroundStateChanged>[];
  final List<OnFirebaseAppDelete> _onDeleteObservers = <OnFirebaseAppDelete>[];

  IsBackground isInBackground;

  // Default disabled. We released Firebase publicly without this feature, so
  // making it default enabled is a backwards incompatible change.
  bool automaticResourceManagementEnabled = false;
  bool deleted = false;
  bool _dataCollectionDefaultEnabled;

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
    InternalTokenProvider tokenProvider,
    InitializeApis appInit,
    SharedPreferences prefs, [
    IsBackground lifecycleHandler,
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

    return FirebaseApp.withOptions(firebaseOptions, tokenProvider, appInit,
        prefs, defaultAppName, lifecycleHandler);
  }

  FirebaseApp._(this._name, this._options, this.getAuthProvider, this._prefs,
      this.initializeApis,
      [this.isInBackground]);

  /// Initializes the default [FirebaseApp] instance. Same as
  /// [initializeApp], but it uses [FirebaseApp.defaultAppName] as
  /// name.
  /// [options] represents the global [FirebaseOptions]
  /// [name] unique name for the app. It is an error to initialize an app with
  /// an already existing name. Starting and ending whitespace characters in the
  /// name are ignored (trimmed).
  /// Returns an instance of [FirebaseApp]
  factory FirebaseApp.withOptions(
    FirebaseOptions options,
    InternalTokenProvider tokenProvider,
    InitializeApis appInit,
    SharedPreferences prefs, [
    String name = defaultAppName,
    IsBackground lifecycleHandler,
  ]) {
    final String normalizedName = _normalize(name);

    Preconditions.checkState(!instances.containsKey(normalizedName),
        'FirebaseApp name $normalizedName already exists!');

    final FirebaseApp firebaseApp = FirebaseApp._(normalizedName, options,
        tokenProvider, prefs, appInit, lifecycleHandler);
    instances[normalizedName] = firebaseApp;
    firebaseApp.initializeApp();

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
    final String availableAppNamesMessage = availableAppNames.isNotEmpty
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
  void setAutomaticResourceManagementEnabled({bool enabled}) {
    _checkNotDeleted();

    if (automaticResourceManagementEnabled != enabled) {
      automaticResourceManagementEnabled = enabled;

      final bool inBackground = isInBackground();
      if (enabled && inBackground) {
        // Automatic resource management has been enabled while the app is in
        // the background, notify the listeners of the app being in the
        // background.
        notifyBackgroundStateChangeObservers(background: true);
      } else if (!enabled && inBackground) {
        // Automatic resource management has been disabled while the app is in
        // the background, act as if we were in the foreground.
        notifyBackgroundStateChangeObservers(background: false);
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
  void setDataCollectionDefaultEnabled({bool enabled = false}) {
    _checkNotDeleted();
    if (_dataCollectionDefaultEnabled != enabled) {
      _dataCollectionDefaultEnabled = enabled;

      _prefs.edit()
        ..putBool(_dataCollectionDefaultEnabledPreferenceKey, enabled)
        ..apply();

      _events.add(DataCollectionDefaultChange(enabled: enabled));
    }
  }

  bool _readAutoDataCollectionEnabled() {
    if (_prefs.contains(_dataCollectionDefaultEnabledPreferenceKey)) {
      return _prefs.getBool(_dataCollectionDefaultEnabledPreferenceKey,
          defValue: true);
    }

    return options.dataCollectionEnabled ?? true;
  }

  void _checkNotDeleted() {
    Preconditions.checkState(!deleted, 'FirebaseApp was deleted');
  }

  @keepForSdk
  @visibleForTesting
  bool get isDefaultApp => defaultAppName == name;

  void notifyBackgroundStateChangeObservers({bool background}) {
    Log.d(logTag, 'Notifying background state change observers.');
    for (OnBackgroundStateChanged observer in backgroundStateChangeObservers) {
      observer(isInBackground: background);
    }
  }

  /// Registers a background state change observer. Make sure to call
  /// [removeBackgroundStateChangeObserver] as appropriate to avoid memory
  /// leaks.
  ///
  /// * If automatic resource management is enabled and the app is in the
  /// background a callback is triggered immediately.
  /// see [OnBackgroundStateChanged]
  @keepForSdk
  void addBackgroundStateChangeObserver(OnBackgroundStateChanged observer) {
    _checkNotDeleted();
    if (automaticResourceManagementEnabled && isInBackground()) {
      observer(isInBackground: true);
    }
    backgroundStateChangeObservers.add(observer);
  }

  /// Unregisters the background state change listener.
  @keepForSdk
  void removeBackgroundStateChangeObserver(OnBackgroundStateChanged observer) {
    _checkNotDeleted();
    backgroundStateChangeObservers.remove(observer);
  }

  /// Use this key to store data per FirebaseApp.
  @keepForSdk
  String get persistenceKey {
    final String encodedName =
        Base64Utils.encodeUrlSafeNoPadding(name.codeUnits);
    final String encodedApplicationId =
        Base64Utils.encodeUrlSafeNoPadding(options.applicationId.codeUnits);

    return '$encodedName+$encodedApplicationId';
  }

  /// If an API has locally stored data it must register lifecycle listeners at
  /// initialization time.
  @keepForSdk
  void addLifecycleEventListener(OnFirebaseAppDelete observer) {
    _checkNotDeleted();
    Preconditions.checkNotNull(observer);
    _onDeleteObservers.add(observer);
  }

  @keepForSdk
  void removeLifecycleEventListener(OnFirebaseAppDelete observer) {
    _checkNotDeleted();
    Preconditions.checkNotNull(observer);
    _onDeleteObservers.remove(observer);
  }

  /// Notifies all observers with the name and options of the deleted
  /// [FirebaseApp] instance.
  void _notifyOnAppDeleted() {
    for (OnFirebaseAppDelete observer in _onDeleteObservers) {
      observer(name, options);
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
    final String encodedName =
        Base64Utils.encodeUrlSafeNoPadding(name.codeUnits);
    final String encodedApplicationId =
        Base64Utils.encodeUrlSafeNoPadding(options.applicationId.codeUnits);

    return '$encodedName+$encodedApplicationId';
  }

  static List<String> _getAllAppNames() {
    final List<String> allAppNames = <String>[];
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

  void initializeApp() {
    initializeApis(this);
    /* Initialize this(call getInstance()):
      private static final String MEASUREMENT_CLASSNAME =
       "com.google.android.gms.measurement.AppMeasurement";
      private static final String AUTH_CLASSNAME = 
      "com.google.firebase.auth.FirebaseAuth";
      private static final String IID_CLASSNAME =
      "com.google.firebase.iid.FirebaseInstanceId";
      private static final String CRASH_CLASSNAME = 
      "com.google.firebase.crash.FirebaseCrash";
    */
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
    return (ToStringHelper(runtimeType)
          ..add('name', name)
          ..add('options', options))
        .toString();
  }
}
