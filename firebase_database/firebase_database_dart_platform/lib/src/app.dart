import 'package:firebase_app_dart/firebase_app_dart.dart' as dart_app;
import 'package:firebase_core/firebase_core.dart' as core;
import 'package:flutter/foundation.dart';

/// Returns the token provider that the Realtime Database connection of the
/// FlutterFire [app] authenticates with, or null for a connection without a
/// user.
///
/// See `FirebaseDatabaseDart.use` for how it is called.
typedef TokenProviderFactory =
    dart_app.AuthTokenProvider? Function(core.FirebaseApp app);

/// Returns the App Check token provider of the Realtime Database connection of
/// the FlutterFire [app], or null for a connection without an App Check token.
///
/// See `FirebaseDatabaseDart.use` for how it is called.
typedef AppCheckProviderFactory =
    dart_app.AppCheckTokenProvider? Function(core.FirebaseApp app);

/// The `firebase_app_dart` options for the FlutterFire [options].
///
/// The same mapping as `dartOptionsOf` of `cloud_firestore_dart_platform`, so
/// that the two packages agree on the `firebase_app_dart` app of a FlutterFire
/// app and can share it. An empty optional value becomes null;
/// `recaptchaSiteKey` has no counterpart and is dropped.
dart_app.FirebaseOptions dartOptionsOf(core.FirebaseOptions options) {
  String? optional(String? value) =>
      value == null || value.isEmpty ? null : value;
  return dart_app.FirebaseOptions(
    apiKey: options.apiKey,
    appId: options.appId,
    messagingSenderId: optional(options.messagingSenderId),
    projectId: optional(options.projectId),
    authDomain: optional(options.authDomain),
    databaseURL: optional(options.databaseURL),
    storageBucket: optional(options.storageBucket),
    measurementId: optional(options.measurementId),
    trackingId: optional(options.trackingId),
    deepLinkURLScheme: optional(options.deepLinkURLScheme),
    androidClientId: optional(options.androidClientId),
    iosClientId: optional(options.iosClientId),
    iosBundleId: optional(options.iosBundleId),
    appGroupId: optional(options.appGroupId),
  );
}

/// The `firebase_app_dart` app with the name of the FlutterFire [app].
///
/// An existing app of that name (one that the Firestore or Storage platform
/// package or `cloud_firestore_dart_flutterfire` set up) keeps the providers
/// it has; when it has no token provider it gets the one of
/// [tokenProviderFor], and when it has no App Check provider the one of
/// [appCheckProviderFor], as `FlutterFireBridge` of
/// `cloud_firestore_dart_flutterfire` does for App Check. Otherwise the app
/// is created with the mapped options and the providers that
/// [tokenProviderFor] and [appCheckProviderFor] return. The token provider of
/// [tokenProviderFor] is installed as a [TokenOnChangeProvider], so that its
/// change events carry the token. Throws a [StateError] when an existing app
/// has other options.
dart_app.FirebaseApp dartAppFor(
  core.FirebaseApp app, {
  TokenProviderFactory? tokenProviderFor,
  AppCheckProviderFactory? appCheckProviderFor,
}) {
  final dart_app.FirebaseOptions options = dartOptionsOf(app.options);
  // Firebase.app(name) of firebase_app_dart throws when there is no app, and
  // Firebase.initializeApp is asynchronous: look the app up in the list.
  final dart_app.FirebaseApp? existing = dart_app.Firebase.apps
      .where((dart_app.FirebaseApp candidate) => candidate.name == app.name)
      .firstOrNull;
  if (existing != null) {
    if (existing.options != options) {
      throw StateError(
        'A firebase_app_dart app named "${app.name}" exists with other '
        'options than the FlutterFire app.',
      );
    }
    // An app without a token provider answers authProvider with itself.
    if (identical(existing.authProvider, existing)) {
      _setTokenProvider(existing, tokenProviderFor?.call(app));
    }
    existing.appCheckProvider ??= appCheckProviderFor?.call(app);
    return existing;
  }
  final dart_app.FirebaseApp created = dart_app.FirebaseApp.withOptions(
    options,
    name: app.name,
  );
  _setTokenProvider(created, tokenProviderFor?.call(app));
  created.appCheckProvider = appCheckProviderFor?.call(app);
  return created;
}

void _setTokenProvider(
  dart_app.FirebaseApp app,
  dart_app.AuthTokenProvider? provider,
) {
  if (provider != null) {
    app.authProvider = provider is TokenOnChangeProvider
        ? provider
        : TokenOnChangeProvider(provider);
  }
}

/// [provider] with change events that carry the token itself.
///
/// The contract of `AuthTokenChange` in `firebase_app_dart`: an empty token
/// means signed out; any other event means the token or the user changed,
/// and the token is the one [dart_app.AuthTokenProvider.getAccessToken]
/// returns now. Providers differ in what a non-empty event holds:
/// `FirebaseAuthDart.userAuthFor` emits the new ID token,
/// `FlutterFireAuthTokenProvider` of `cloud_firestore_dart_flutterfire` a
/// fixed marker (its source reports the change without the token). The
/// Realtime Database connection sends the event's token to the server at
/// once, so this class answers each non-empty event with the token of
/// [provider]'s `getAccessToken(forceRefresh: false)`, in event order; an
/// empty event passes as it is. When that call says nobody is signed in the
/// event becomes a sign-out; when it fails otherwise the event is dropped
/// with a `debugPrint`, and the connection fetches the token itself at its
/// next connect.
///
/// [uid] and [getAccessToken] are those of [provider].
class TokenOnChangeProvider extends dart_app.AuthTokenProvider {
  /// The provider that answers the change events of [provider] with its
  /// token.
  TokenOnChangeProvider(this.provider);

  /// The provider of the user and the tokens.
  final dart_app.AuthTokenProvider provider;

  @override
  Future<dart_app.GetTokenResult> getAccessToken({
    required bool forceRefresh,
  }) => provider.getAccessToken(forceRefresh: forceRefresh);

  @override
  String? get uid => provider.uid;

  /// The events of [provider], each non-empty one replaced by the current
  /// token (see the class documentation).
  @override
  Stream<dart_app.AuthTokenChange> get onTokenChanged =>
      provider.onTokenChanged.asyncExpand(_withToken);

  Stream<dart_app.AuthTokenChange> _withToken(
    dart_app.AuthTokenChange change,
  ) async* {
    if (change.token.isEmpty) {
      yield change;
      return;
    }
    try {
      final dart_app.GetTokenResult result = await provider.getAccessToken(
        forceRefresh: false,
      );
      yield dart_app.AuthTokenChange(result.token);
    } on dart_app.FirebaseNoSignedInUserException {
      yield const dart_app.AuthTokenChange('');
    } on Object catch (error) {
      debugPrint(
        'firebase_database_dart_platform: the token provider failed after a '
        'token change (${error.runtimeType}); the Realtime Database '
        'connection fetches the token again when it reconnects.',
      );
    }
  }
}
