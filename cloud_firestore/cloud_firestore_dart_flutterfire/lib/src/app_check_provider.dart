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
/// fails a request: when the plugin throws or returns no token, [getToken] reports the error in the result with an
/// empty token, and Firestore sends the request without the header and logs a warning.
class FlutterFireAppCheckProvider extends InternalAppCheckTokenProvider {
  /// Creates the provider. [getToken] is called with `forceRefresh`; [onTokenChange] emits the new token (null
  /// when there is none).
  FlutterFireAppCheckProvider({
    required Future<String?> Function(bool forceRefresh) getToken,
    required Stream<String?> onTokenChange,
  }) : _getToken = getToken,
       _onTokenChange = onTokenChange;

  final Future<String?> Function(bool forceRefresh) _getToken;
  final Stream<String?> _onTokenChange;

  /// The token of the plugin. A failure is reported in [AppCheckTokenResult.error], with an empty token.
  @override
  Future<AppCheckTokenResult> getToken({required bool forceRefresh}) async {
    try {
      final String? token = await _getToken(forceRefresh);
      if (token == null || token.isEmpty) {
        return AppCheckTokenResult(
          '',
          error: StateError('firebase_app_check returned no token.'),
        );
      }
      return AppCheckTokenResult(token);
    } on Object catch (e) {
      return AppCheckTokenResult('', error: e);
    }
  }

  /// The tokens of `onTokenChange`; null becomes an empty token. Several listeners may listen (each Firestore
  /// instance of the app does), also when `onTokenChange` is a single-subscription stream.
  @override
  Stream<AppCheckTokenResult> get onTokenChanged => _changes;

  late final Stream<AppCheckTokenResult> _changes = () {
    final Stream<AppCheckTokenResult> mapped = _onTokenChange.map(
      (String? token) => AppCheckTokenResult(token ?? ''),
    );
    return mapped.isBroadcast ? mapped : mapped.asBroadcastStream();
  }();
}
