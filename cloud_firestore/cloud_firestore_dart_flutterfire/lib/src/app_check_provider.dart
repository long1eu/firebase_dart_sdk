import 'dart:async';

import 'package:firebase_app_dart/firebase_app_dart.dart';

/// An App Check token provider for `cloud_firestore_dart` that takes the tokens from the official
/// `firebase_app_check` plugin, or from any source with the same two members.
///
/// This package does not depend on `firebase_app_check`, so that apps without App Check do not get the plugin
/// and its native SDKs. Pass the two members of `FirebaseAppCheck` yourself:
///
/// ```dart
/// final FirebaseAppCheck appCheck = FirebaseAppCheck.instance;
/// final FlutterFireAppCheckProvider provider = FlutterFireAppCheckProvider(
///   getToken: appCheck.getToken,
///   onTokenChange: appCheck.onTokenChange,
/// );
/// ```
///
/// Firestore sends the token in the `x-firebase-appcheck` header. Like the App Check SDKs, the provider never
/// fails a request: when the plugin throws or returns no token, [getToken] reports the error in the result with
/// the placeholder token ([AppCheckTokenResult.failure]), and Firestore sends the request with the placeholder and
/// logs a warning. The plugin decides how long a token it returns is still valid. An event of `onTokenChange`
/// without a token (null or empty) is not forwarded.
///
/// For limited-use tokens (a token for one request to a backend that consumes App Check tokens), use
/// [FlutterFireLimitedUseAppCheckProvider]. This class does not implement [LimitedUseAppCheckTokenProvider]: a
/// limited-use request then carries no App Check header, and never the session token.
class FlutterFireAppCheckProvider extends AppCheckTokenProvider {
  /// Creates the provider. [getToken] is called with `forceRefresh`; [onTokenChange] emits the new token (null
  /// when there is none; such an event is dropped).
  FlutterFireAppCheckProvider({
    required Future<String?> Function(bool forceRefresh) getToken,
    required Stream<String?> onTokenChange,
  }) : _getToken = getToken,
       _onTokenChange = onTokenChange;

  final Future<String?> Function(bool forceRefresh) _getToken;
  final Stream<String?> _onTokenChange;

  /// The token of the plugin. A failure (a throw, or no token) is an [AppCheckTokenResult.failure]: the
  /// placeholder token with the error.
  @override
  Future<AppCheckTokenResult> getToken({required bool forceRefresh}) async {
    try {
      final String? token = await _getToken(forceRefresh);
      if (token == null || token.isEmpty) {
        return AppCheckTokenResult.failure(
          StateError('firebase_app_check returned no token.'),
        );
      }
      return AppCheckTokenResult(token);
    } on Object catch (e) {
      return AppCheckTokenResult.failure(e);
    }
  }

  /// The tokens of `onTokenChange`. An event without a token (null or empty) is dropped: the stream carries new
  /// tokens only, never an error, and does not replay the last token to a new listener. Several listeners may
  /// listen (each Firestore instance of the app does), also when `onTokenChange` is a single-subscription stream.
  @override
  Stream<AppCheckTokenResult> get onTokenChanged => _changes;

  late final Stream<AppCheckTokenResult> _changes = () {
    final Stream<AppCheckTokenResult> mapped = _onTokenChange
        .where((String? token) => token != null && token.isNotEmpty)
        .map((String? token) => AppCheckTokenResult(token!));
    return mapped.isBroadcast ? mapped : mapped.asBroadcastStream();
  }();
}

/// A [FlutterFireAppCheckProvider] that also gives limited-use tokens: a token for one request to a backend that
/// consumes App Check tokens (replay protection). Pass the three members of `FirebaseAppCheck`:
///
/// ```dart
/// final FirebaseAppCheck appCheck = FirebaseAppCheck.instance;
/// final FlutterFireLimitedUseAppCheckProvider provider =
///     FlutterFireLimitedUseAppCheckProvider(
///       getToken: appCheck.getToken,
///       onTokenChange: appCheck.onTokenChange,
///       getLimitedUseToken: appCheck.getLimitedUseToken,
///     );
/// ```
///
/// Firestore asks for session tokens only; the limited-use tokens are for packages that ask a
/// [LimitedUseAppCheckTokenProvider] for them.
class FlutterFireLimitedUseAppCheckProvider extends FlutterFireAppCheckProvider
    implements LimitedUseAppCheckTokenProvider {
  /// Creates the provider. [getToken] and [onTokenChange] are those of [FlutterFireAppCheckProvider.new].
  /// [getLimitedUseToken] is called once for every limited-use token; it must return a new token each time, as
  /// `FirebaseAppCheck.getLimitedUseToken` does.
  FlutterFireLimitedUseAppCheckProvider({
    required super.getToken,
    required super.onTokenChange,
    required Future<String?> Function() getLimitedUseToken,
  }) : _getLimitedUseToken = getLimitedUseToken;

  final Future<String?> Function() _getLimitedUseToken;

  /// A limited-use token of the plugin, asked for on every call and never kept or emitted on [onTokenChanged].
  /// A failure (a throw, or no token) is an [AppCheckTokenResult.failure]: the placeholder token with the error.
  /// The session token of [getToken] is never returned instead.
  @override
  Future<AppCheckTokenResult> getLimitedUseToken() async {
    try {
      final String? token = await _getLimitedUseToken();
      if (token == null || token.isEmpty) {
        return AppCheckTokenResult.failure(
          StateError('firebase_app_check returned no limited-use token.'),
        );
      }
      return AppCheckTokenResult(token);
    } on Object catch (e) {
      return AppCheckTokenResult.failure(e);
    }
  }
}
