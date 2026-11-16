// File created by
// Lung Razvan <long1eu>
// on 25/11/2019

import 'dart:async';

import 'package:firebase_app_dart/internal.dart';
import 'package:rxdart/rxdart.dart';

/// The services a `FirebaseApp` needs from the platform it runs on: storage, connectivity and
/// background events, and the auth and App Check token providers.
///
/// Subclass it, override the members you can supply, and pass an instance as `dependencies:` to
/// `FirebaseApp.withOptions`. The app reads each member **once**, when it is created, so a member
/// that returns a stream must return the same object every time: keep it in a field. Every member
/// has a default:
///
/// | Member | Default | Who reads it |
/// | --- | --- | --- |
/// | [onNetworkConnected] | always connected | Firestore: `true` restarts failed streams at once |
/// | [onBackgroundChanged] | never in the background | nobody in this repository |
/// | [storage] | this object, in memory | `FirebaseApp.setAutomaticDataCollectionEnabled` |
/// | [authProvider] | none: requests carry no token | Firestore |
/// | [appCheckProvider] | none: no App Check header | Firestore, `FirebaseUserAuth` |
/// | [headersBuilder] | none | nobody in this repository |
///
/// ```dart
/// import 'package:firebase_app_dart/firebase_app_dart.dart';
/// import 'package:firebase_app_dart/platform_dependencies.dart';
/// import 'package:rxdart/rxdart.dart';
///
/// class AppDependencies extends PlatformDependencies {
///   /// Fed by a connectivity plugin, for example `connectivity_plus`.
///   final BehaviorSubject<bool> connectivity = BehaviorSubject<bool>.seeded(true);
///
///   @override
///   BehaviorSubject<bool> get onNetworkConnected => connectivity;
/// }
///
/// void main() {
///   final AppDependencies dependencies = AppDependencies();
///   FirebaseApp.withOptions(
///     const FirebaseOptions(
///       apiKey: '<YOUR_API_KEY>',
///       appId: '1:1234567890:dart:example',
///       projectId: 'my-project',
///     ),
///     dependencies: dependencies,
///   );
///   dependencies.connectivity.add(false); // the device went offline
/// }
/// ```
class PlatformDependencies extends LocalStorage {
  /// Creates the default dependencies: an in-memory [LocalStorage], always connected, never in the
  /// background, and no token providers.
  PlatformDependencies();

  final Map<String, String> _map = <String, String>{};

  /// Emits `true` when the app goes to the background and `false` when it comes back.
  ///
  /// The default returns a new subject seeded with `false` on every call. No service of this
  /// repository reads it.
  BehaviorSubject<bool> get onBackgroundChanged {
    return BehaviorSubject<bool>.seeded(false);
  }

  /// Emits `true` when the device has a network connection and `false` when it lost it.
  ///
  /// The default returns a new subject seeded with `true` on every call. Override it with a field
  /// that your connectivity source feeds. Firestore skips the current value; every later `true`
  /// restarts the streams that failed, without waiting for their backoff, and the first event
  /// switches off the built-in connectivity detector of `cloud_firestore_dart` for good.
  BehaviorSubject<bool> get onNetworkConnected {
    return BehaviorSubject<bool>.seeded(true);
  }

  /// Extra headers for the requests of Firebase services. Default null.
  ///
  /// Kept from the original project: no service of this repository calls it.
  HeaderBuilder? get headersBuilder => null;

  /// Key/value storage that survives a restart of the app. The default is this object, which keeps
  /// the values in memory ([get] and [set]).
  ///
  /// `FirebaseApp` keeps the data collection setting in it. Firebase Auth sessions are not kept
  /// here: `FirebaseUserAuth` has an `AuthStorage` of its own.
  LocalStorage get storage => this;

  /// The source of the token that Firestore sends with each request. Default null: requests carry
  /// no token, and the security rules see no user.
  ///
  /// You can also leave it null and set `FirebaseApp.authProvider` later, before the Firestore
  /// instance is created; `FirebaseUserAuth.forApp` of `package:firebase_auth_providers_dart` does
  /// that.
  AuthTokenProvider? get authProvider => null;

  /// Firestore sends the token of this provider in the `x-firebase-appcheck` header of every
  /// request. Default null: no App Check header is sent.
  AppCheckTokenProvider? get appCheckProvider => null;

  /// The value stored in memory under [key], or null.
  @override
  String? get(String key) {
    return _map[key];
  }

  /// Stores [value] in memory under [key]; null removes it.
  @override
  Future<void> set(String key, String? value) async {
    if (value == null) {
      _map.remove(key);
    } else {
      _map[key] = value;
    }
  }
}

/// Key/value storage of strings, the type of [PlatformDependencies.storage].
///
/// [get] is synchronous: an implementation on top of an asynchronous store loads the values before
/// the app is created.
///
/// ```dart
/// import 'package:firebase_app_dart/platform_dependencies.dart';
///
/// class MapStorage extends LocalStorage {
///   final Map<String, String> values = <String, String>{};
///
///   @override
///   String? get(String key) => values[key];
///
///   @override
///   Future<void> set(String key, String? value) async {
///     if (value == null) {
///       values.remove(key);
///     } else {
///       values[key] = value;
///     }
///   }
/// }
/// ```
abstract class LocalStorage {
  /// Constructor for subclasses.
  LocalStorage();

  /// Gets the values at [key], or null if none found.
  String? get(String key);

  /// Saves the value at [key].
  ///
  /// When a null value is provided the implementation should remove the value.
  Future<void> set(String key, String? value);
}

/// Returns extra headers for a request (see [PlatformDependencies.headersBuilder], which no
/// service of this repository calls).
typedef HeaderBuilder = Future<Map<String, String>> Function();
