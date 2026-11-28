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
/// For limited-use tokens (a token for one request to a backend that consumes App Check tokens), also pass
/// `getLimitedUseToken: appCheck.getLimitedUseToken`. Without it, [getLimitedUseToken] gives no token.
///
/// Firestore sends the token in the `x-firebase-appcheck` header. Like the App Check SDKs, the provider never
/// fails a request: when the plugin throws or returns no token, [getToken] reports the error in the result with
/// the placeholder token ([AppCheckTokenResult.failure]), and Firestore sends the request with the placeholder and
/// logs a warning. The plugin decides how long a token it returns is still valid.
class FlutterFireAppCheckProvider extends AppCheckTokenProvider {
  /// Creates the provider. [getToken] is called with `forceRefresh`; [onTokenChange] emits the new token (null
  /// when there is none; such an event is dropped). [getLimitedUseToken], when given, is called once for every limited-use token; it must
  /// return a new token each time, as `FirebaseAppCheck.getLimitedUseToken` does.
  FlutterFireAppCheckProvider({
    required Future<String?> Function(bool forceRefresh) getToken,
    required Stream<String?> onTokenChange,
    Future<String?> Function()? getLimitedUseToken,
  }) : _getToken = getToken,
       _onTokenChange = onTokenChange,
       _getLimitedUseToken = getLimitedUseToken;

  final Future<String?> Function(bool forceRefresh) _getToken;
  final Stream<String?> _onTokenChange;
  final Future<String?> Function()? _getLimitedUseToken;

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

  /// A limited-use token of the plugin, asked for on every call and never kept or emitted on [onTokenChanged].
  /// A failure (a throw, or no token) is an [AppCheckTokenResult.failure]: the placeholder token with the error.
  /// Without the `getLimitedUseToken` argument of the constructor the result is the inherited one: an empty token
  /// with an [UnsupportedError]. The session token of [getToken] is never returned instead.
  @override
  Future<AppCheckTokenResult> getLimitedUseToken() async {
    final Future<String?> Function()? getLimitedUseToken = _getLimitedUseToken;
    if (getLimitedUseToken == null) {
      return super.getLimitedUseToken();
    }
    try {
      final String? token = await getLimitedUseToken();
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
