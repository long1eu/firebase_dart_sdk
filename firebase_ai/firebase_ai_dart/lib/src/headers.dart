import 'package:_firebase_transport_dart/_firebase_transport_dart.dart';
import 'package:firebase_ai_dart/src/logger.dart';
import 'package:firebase_ai_dart/src/version.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:http/http.dart' as http;

/// Carries the app id of the Firebase options, while the app allows data collection.
const String _appIdHeader = 'X-Firebase-AppId';

const String _contentTypeHeader = 'Content-Type';
const String _jsonContentType = 'application/json';

const String _noAppCheckProvider =
    'No App Check provider: requests carry no App Check token; with App Check enforced for '
    'AI Logic they will be refused.';

/// The headers of every request of one `FirebaseAI`, and the tokens among them.
///
/// It owns the instance's one [TokenSource]. The Auth and App Check providers, the API key, the
/// app id and the data-collection setting are read from the app at every request, so a change on
/// the app applies from the next request.
///
/// Nothing here logs or stores a token or the API key.
final class AiHeaders {
  /// The headers of requests of [app] to [serverOrigin].
  ///
  /// With [useLimitedUseAppCheckTokens], every request asks the App Check provider for a
  /// limited-use token of its own. [logger] receives the warnings of the token step and one info
  /// line when the app has no App Check provider.
  ///
  /// Throws an [ArgumentError] when [serverOrigin] is not an origin tokens may go to.
  AiHeaders({
    required FirebaseApp app,
    required Uri serverOrigin,
    required bool useLimitedUseAppCheckTokens,
    AILogger? logger,
  }) : _app = app,
       _useLimitedUseAppCheckTokens = useLimitedUseAppCheckTokens,
       _logger = logger,
       _apiClient = apiClientHeader(sdkVersion: packageVersion),
       _tokens = TokenSource(
         app,
         origins: <Uri>[serverOrigin],
         onWarning: logger == null
             ? null
             : (String message) => logger(AILogLevel.warning, message),
       );

  final FirebaseApp _app;
  final bool _useLimitedUseAppCheckTokens;
  final AILogger? _logger;
  final String _apiClient;
  final TokenSource _tokens;
  bool _loggedNoAppCheckProvider = false;

  /// Whether the app was deleted: its getters throw then, and no request may be built.
  bool get isAppDeleted {
    try {
      _app.name;
      return false;
    } on StateError {
      return true;
    }
  }

  /// The tokens of one attempt of a request to [url]; every request and every chat send asks once.
  ///
  /// [timeLeft] is what remains of the call's deadline and must be positive. After it completes,
  /// the caller checks its own cancel signal and closed flag before it sends anything.
  ///
  /// Throws, through the returned future:
  /// - a [StateError] when the app was deleted, or when its options hold no API key (no provider
  ///   is asked then, so no limited-use token is minted for a request that cannot be sent);
  /// - a [TokenFetchException] when the Auth provider failed, did not answer in time or gave a
  ///   token that is too long. An App Check failure never fails the call;
  /// - a `TimeoutException` when [timeLeft] ran out while a provider had not answered.
  Future<RequestTokens> tokensFor(Uri url, {required Duration timeLeft}) async {
    _apiKey();
    _logMissingAppCheckProviderOnce();
    return _tokens.tokensFor(
      url,
      limitedUseAppCheck: _useLimitedUseAppCheckTokens,
      timeLeft: timeLeft,
    );
  }

  /// Sets every header of a request on [request]: the content type, the API key, the client
  /// description, the app id while the app allows data collection, and the headers of [tokens].
  ///
  /// [tokens] can be applied once; each attempt fetches its own.
  ///
  /// Throws a [StateError] when the app was deleted, when its options hold no API key, when they
  /// hold no app id while data collection is on, or when [tokens] were used before or were fetched
  /// for another origin. Throws an [ArgumentError] when the API key is not a header value; the
  /// message never holds the key.
  void apply(http.BaseRequest request, RequestTokens tokens) {
    final String apiKey = _apiKey();
    final String? appId = _appIdToSend();
    request.headers[_contentTypeHeader] = _jsonContentType;
    request.headers[FirebaseHeaders.apiKey] = apiKey;
    request.headers[FirebaseHeaders.apiClient] = _apiClient;
    if (appId != null) {
      request.headers[_appIdHeader] = appId;
    }
    applyTokens(request, tokens, auth: AuthHeaderStyle.firebase);
  }

  /// Tells the token source what the server answered to the attempt that carried [tokens].
  ///
  /// After an HTTP 401, the next request forces a refresh of the Auth token, and only when this
  /// attempt carried one. App Check is never invalidated: no answer is read for an App Check
  /// reason. The call is not sent again.
  void afterAnswer(int statusCode, RequestTokens tokens) {
    if (statusCode == 401 && tokens.hasAuthToken) {
      _tokens.invalidate(TokenKind.auth);
    }
  }

  /// The API key of the app's options, read now.
  String _apiKey() {
    final String apiKey = _app.options.apiKey;
    if (apiKey.isEmpty) {
      throw StateError(
        'FirebaseOptions.apiKey is empty: Firebase AI Logic sends the API key with every '
        'request.',
      );
    }
    if (!isHeaderValue(apiKey)) {
      throw ArgumentError(
        'FirebaseOptions.apiKey is not a valid value for the ${FirebaseHeaders.apiKey} header.',
      );
    }
    return apiKey;
  }

  /// The app id to send now: null while the app does not allow data collection, and for an id
  /// that is not token text.
  String? _appIdToSend() {
    if (!_app.isAutomaticDataCollectionEnabled) {
      return null;
    }
    final String appId = _app.options.appId;
    if (appId.isEmpty) {
      throw StateError(
        'FirebaseOptions.appId is empty: Firebase AI Logic sends the app id while automatic '
        'data collection is enabled.',
      );
    }
    return isTokenText(appId) ? appId : null;
  }

  void _logMissingAppCheckProviderOnce() {
    final AILogger? logger = _logger;
    if (logger == null ||
        _loggedNoAppCheckProvider ||
        _app.appCheckProvider != null) {
      return;
    }
    _loggedNoAppCheckProvider = true;
    logger(AILogLevel.info, _noAppCheckProvider);
  }
}
