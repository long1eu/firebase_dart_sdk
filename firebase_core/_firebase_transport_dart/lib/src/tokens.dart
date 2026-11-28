import 'dart:async';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:_firebase_transport_dart/src/headers.dart';
import 'package:_firebase_transport_dart/src/hosts.dart';
import 'package:_firebase_transport_dart/src/log_once.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

/// The two kinds of token a request carries.
enum TokenKind {
  /// The Auth token of the signed-in user.
  auth,

  /// The App Check token of the app.
  appCheck,
}

/// What happened to the App Check token of one attempt.
enum AppCheckOutcome {
  /// The app has no App Check provider.
  none,

  /// A token without an error was sent.
  sent,

  /// Token text together with an error was sent: the placeholder, or an unexpired real token whose
  /// refresh failed.
  sentPlaceholder,

  /// The provider gave an empty token, or one that is not token text; no token was sent.
  empty,

  /// The provider threw; no token was sent.
  providerFailed,

  /// The provider did not answer within the wait; no token was sent.
  timedOut,

  /// The provider was not asked, because an earlier call to it is still stuck; no token was sent.
  skipped,

  /// A limited-use token was asked for and the provider does not implement
  /// [LimitedUseAppCheckTokenProvider]; no token was sent.
  unsupported,
}

/// Why [TokenSource.tokensFor] could not give tokens.
enum TokenFailure {
  /// The Auth provider threw, or gave a token that is not token text.
  authProviderFailed,

  /// The Auth provider did not answer within the wait, or is paused after doing so.
  authTimedOut,

  /// The Auth token is longer than [maxTokenLength].
  authTokenTooLong,

  /// The destination may not receive tokens.
  destinationRefused,
}

/// [TokenSource.tokensFor] could not give tokens for a reason that must fail the call.
///
/// A product catches it and throws its own exception; `rpcStatusOfFailure` gives the status.
final class TokenFetchException implements Exception {
  /// A failure of the kind [failure], caused by an error of the type named [causeType].
  const TokenFetchException(this.failure, {this.causeType});

  /// The reason.
  final TokenFailure failure;

  /// The runtime type name of the provider's error, for [TokenFailure.authProviderFailed] when the
  /// provider threw; null otherwise. The error itself is not kept: its text can hold a URL.
  final String? causeType;

  /// `TokenFetchException: <failure name>`.
  @override
  String toString() => 'TokenFetchException: ${failure.name}';
}

/// The tokens of one attempt, bound to the origin they were fetched for.
///
/// Created only by [TokenSource]. The token values are not readable; [headersFor] turns them into
/// headers once, so a retry that keeps the object fails instead of replaying a limited-use token or
/// the token of a user who signed out.
final class RequestTokens {
  RequestTokens._(
    this.origin,
    this._authToken,
    this._appCheckToken,
    this.appCheck,
  );

  /// For the tests of products: tokens for the origin of [origin].
  ///
  /// Throws an [ArgumentError] when a token is not token text (see [isTokenText]), or when
  /// [tokenOrigin] refuses [origin].
  @visibleForTesting
  factory RequestTokens.forTesting({
    required Uri origin,
    String? authToken,
    String? appCheckToken,
    AppCheckOutcome appCheck = AppCheckOutcome.none,
  }) {
    if (authToken != null && !isTokenText(authToken)) {
      throw ArgumentError('authToken is not token text');
    }
    if (appCheckToken != null && !isTokenText(appCheckToken)) {
      throw ArgumentError('appCheckToken is not token text');
    }
    return RequestTokens._(
      tokenOrigin(origin),
      authToken,
      appCheckToken,
      appCheck,
    );
  }

  /// The origin the tokens may go to, in the form of [tokenOrigin].
  final Uri origin;

  /// What happened to the App Check token.
  final AppCheckOutcome appCheck;

  final String? _authToken;
  final String? _appCheckToken;
  bool _used = false;

  /// Whether an Auth token is held.
  bool get hasAuthToken => _authToken != null;

  /// The token headers for a request to [destination], with the Auth token in the style [auth].
  ///
  /// The map holds the tokens as plain strings: put it on the request at once and never store it.
  ///
  /// Throws a [StateError] when the token origin of [destination] is not [origin], when
  /// [destination] has user info, or when it was called before on this object.
  Map<String, String> headersFor(
    Uri destination, {
    required AuthHeaderStyle auth,
  }) {
    if (!_isBoundTo(destination)) {
      throw StateError(
        'These tokens were fetched for another origin, or the destination has user info.',
      );
    }
    if (_used) {
      throw StateError(
        'These tokens were used before; each attempt fetches its own.',
      );
    }
    _used = true;
    final Map<String, String> headers = <String, String>{};
    final String? authToken = _authToken;
    if (authToken != null) {
      switch (auth) {
        case AuthHeaderStyle.bearer:
          headers[FirebaseHeaders.authorization] = 'Bearer $authToken';
        case AuthHeaderStyle.firebase:
          headers[FirebaseHeaders.authorization] = 'Firebase $authToken';
        case AuthHeaderStyle.firebaseAuthToken:
          headers[FirebaseHeaders.firebaseAuthToken] = authToken;
      }
    }
    final String? appCheckToken = _appCheckToken;
    if (appCheckToken != null) {
      headers[FirebaseHeaders.appCheck] = appCheckToken;
    }
    return headers;
  }

  bool _isBoundTo(Uri destination) {
    try {
      return destination.userInfo.isEmpty && tokenOrigin(destination) == origin;
    } on ArgumentError {
      return false;
    }
  }

  /// Whether [other] holds the same two token values. May be called after [headersFor].
  bool sameTokensAs(RequestTokens other) {
    return other._authToken == _authToken &&
        other._appCheckToken == _appCheckToken;
  }

  /// `RequestTokens(origin: <origin>, auth: present|absent, appCheck: <outcome name>)`.
  @override
  String toString() {
    final String auth = hasAuthToken ? 'present' : 'absent';
    return 'RequestTokens(origin: $origin, auth: $auth, appCheck: ${appCheck.name})';
  }
}

/// Sets `tokens.headersFor(request.url, auth: auth)` on [request].
///
/// Throws the [StateError] of [RequestTokens.headersFor], and a [StateError] when [request] was
/// already sent: its headers can no longer be set, and [tokens] is then left unused.
void applyTokens(
  http.BaseRequest request,
  RequestTokens tokens, {
  required AuthHeaderStyle auth,
}) {
  if (request.finalized) {
    throw StateError(
      'The request was already sent; its headers cannot be set.',
    );
  }
  request.headers.addAll(tokens.headersFor(request.url, auth: auth));
}

/// The only source of the Auth and App Check tokens of a product's requests.
///
/// It implements one failure rule for every product. A failed Auth provider fails the call, so a
/// signed-in call never silently becomes an anonymous one. A failed App Check provider never does:
/// the call goes out with what the provider gave, or without the header, and the product reads
/// what happened from [RequestTokens.appCheck]. Tokens go only to the origins the product declared,
/// to its emulator, or to a URL the application chose itself.
///
/// It holds no token and no subscription and needs no closing. Between calls it keeps only which
/// kinds owe a forced refresh, when Auth was last forced, and whether a provider is stuck; while
/// an App Check `getToken` call is pending it also keeps that call, for other requests to join.
///
/// A provider that never answers is called once every 70 s: a wait of 10 s, then a pause of 60 s
/// that starts at the timeout. Requests in between are not held up by it.
final class TokenSource {
  /// A source of the tokens of [app] for requests to [origins] and to [emulator].
  ///
  /// [onWarning] receives fixed text and type names, never a token, a URL or the text of an error;
  /// each warning is given once per key (the provider type, and the error type where the warning
  /// names one). [elapsed] is the monotonic clock the 60 s intervals are measured
  /// with; by default a stopwatch started here.
  ///
  /// Throws an [ArgumentError] when an entry of [origins] is a `ws` or `wss` URL without an
  /// explicit port, or fails the origin rule of [checkOrigin] once `ws` is read as `http` and
  /// `wss` as `https`.
  TokenSource(
    FirebaseApp app, {
    required Iterable<Uri> origins,
    EmulatorHost? emulator,
    void Function(String message)? onWarning,
    @visibleForTesting Duration Function()? elapsed,
  }) : _app = app,
       _origins = _checkedOrigins(origins),
       _emulator = emulator,
       _warnOnce = LogOnce(onWarning),
       _elapsed = elapsed ?? _stopwatchClock();

  /// How long [tokensFor] waits for each provider: [AppCheckTokenProvider.responseDeadline] plus a
  /// margin of 2 s, so a provider that keeps its deadline is never cut off.
  static const Duration providerWait = Duration(seconds: 10);

  /// The shortest time between two forced Auth refreshes of one source.
  static const Duration authForcedRefreshMinInterval = Duration(seconds: 60);

  /// How long a provider is not asked again after a call to it timed out and has not answered.
  static const Duration stuckProviderPause = Duration(seconds: 60);

  final FirebaseApp _app;
  final Set<Uri> _origins;
  final EmulatorHost? _emulator;
  final LogOnce _warnOnce;
  final Duration Function() _elapsed;

  final _KindState _auth = _KindState();
  final _KindState _appCheck = _KindState();
  Duration? _lastForcedAuthRefresh;
  _SharedSessionCall? _sharedSessionCall;

  static Set<Uri> _checkedOrigins(Iterable<Uri> origins) {
    final Set<Uri> checked = <Uri>{};
    for (final Uri entry in origins) {
      final Uri origin = tokenOrigin(entry);
      // Called for its ArgumentError: rule O sees the entry itself, with only the scheme mapped,
      // so a path or user info is refused before tokenOrigin's reduction can hide it.
      checkOrigin(entry.replace(scheme: origin.scheme));
      checked.add(origin);
    }
    return checked;
  }

  static Duration Function() _stopwatchClock() {
    final Stopwatch stopwatch = Stopwatch()..start();
    return () => stopwatch.elapsed;
  }

  /// The tokens for one attempt of a request to [url]. Each attempt, each retry and each reconnect
  /// of a stream calls it again.
  ///
  /// [limitedUseAppCheck] asks the App Check provider for a limited-use token, minted for this
  /// attempt; a provider that cannot mint one gives no App Check token, never its session token.
  /// [originChosenByApplication] allows a [url] outside the declared origins; a product passes it
  /// only for a URL the application itself supplied for this call, never for one a server handed
  /// back. [timeLeft] is what remains of the product's deadline for the call, null when it has
  /// none.
  ///
  /// After it completes, the product checks its own cancel signal and closed flag before it sends
  /// anything.
  ///
  /// Throws, through the returned future:
  /// - a [StateError] when the app was deleted, before or during the wait; a deleted app is
  ///   reported before anything else is checked;
  /// - an [ArgumentError] when [timeLeft] is zero or negative;
  /// - a [TokenFetchException] when [url] may not receive tokens (no provider is asked then), or
  ///   when the Auth provider failed, did not answer in [providerWait] or gave a token that is
  ///   too long;
  /// - a [TimeoutException] when [timeLeft] ran out while a provider had not answered.
  Future<RequestTokens> tokensFor(
    Uri url, {
    bool limitedUseAppCheck = false,
    bool originChosenByApplication = false,
    Duration? timeLeft,
  }) async {
    _throwIfDeleted();
    if (timeLeft != null && timeLeft <= Duration.zero) {
      throw ArgumentError.value(timeLeft, 'timeLeft', 'must be positive');
    }
    final Uri origin = _allowedOrigin(
      url,
      originChosenByApplication: originChosenByApplication,
    );
    final AuthTokenProvider authProvider = _app.authProvider;
    final AppCheckTokenProvider? appCheckProvider = _app.appCheckProvider;

    final _ProviderCall<GetTokenResult>? authCall = _askAuth(authProvider);
    final _AppCheckAsk appCheckAsk = _askAppCheck(
      appCheckProvider,
      limitedUse: limitedUseAppCheck,
    );
    await _settled(<_ProviderCall<Object>>[
      ?authCall,
      ?appCheckAsk.call,
    ], timeLeft);
    _throwIfDeleted();

    // App Check first: its warning is logged also when the Auth result then fails the call.
    final (String? appCheckToken, AppCheckOutcome outcome) = await _appCheckOf(
      appCheckAsk,
    );
    final String? authToken = _authTokenOf(await authCall?.answer);
    if (authToken != null || appCheckToken != null) {
      _warnOfRemoteEmulator(url);
    }
    return RequestTokens._(origin, authToken, appCheckToken, outcome);
  }

  /// The backend refused the token of [kind]: the next [tokensFor] forces a refresh of that kind.
  ///
  /// A product calls it for [TokenKind.auth] when the transport itself answered 401 or
  /// `UNAUTHENTICATED` and the attempt carried an Auth token, and for [TokenKind.appCheck] only
  /// when the backend's answer names App Check as the reason. Forced Auth refreshes are at least
  /// [authForcedRefreshMinInterval] apart; how often a forced App Check refresh leads to a new
  /// token is the provider's decision.
  void invalidate(TokenKind kind) {
    switch (kind) {
      case TokenKind.auth:
        _auth.owesRefresh = true;
      case TokenKind.appCheck:
        _appCheck.owesRefresh = true;
    }
  }

  /// Reading the name of a deleted app throws the [StateError] this lets through.
  void _throwIfDeleted() {
    _app.name;
  }

  Uri _allowedOrigin(Uri url, {required bool originChosenByApplication}) {
    const TokenFetchException refused = TokenFetchException(
      TokenFailure.destinationRefused,
    );
    if (!mayCarryTokens(url, emulator: _emulator)) {
      throw refused;
    }
    final Uri origin;
    try {
      origin = tokenOrigin(url);
    } on ArgumentError {
      throw refused;
    }
    final bool ownedByEmulator = _emulator?.owns(url) ?? false;
    if (!originChosenByApplication &&
        !ownedByEmulator &&
        !_origins.contains(origin)) {
      throw refused;
    }
    return origin;
  }

  bool _isPaused(_KindState state) {
    final Duration? pausedAt = state.pausedAt;
    return pausedAt != null && _elapsed() - pausedAt < stuckProviderPause;
  }

  /// Calls a provider. A call that outlives [providerWait] starts the pause of its kind, and any
  /// answer ends it. A call made after a pause ran out restarts the pause until it answers, so one
  /// call is made per pause, not one per request.
  _ProviderCall<T> _startCall<T extends Object>(
    _KindState state,
    Future<T> Function() ask,
  ) {
    if (state.pausedAt != null) {
      state.pausedAt = _elapsed();
    }
    return _ProviderCall<T>(
      ask,
      wait: providerWait,
      onAnswer: () => state.pausedAt = null,
      onTimeout: () => state.pausedAt = _elapsed(),
    );
  }

  /// Null when the app has no Auth provider: the app then answers as its own provider.
  _ProviderCall<GetTokenResult>? _askAuth(AuthTokenProvider provider) {
    if (identical(provider, _app)) {
      return null;
    }
    if (_isPaused(_auth)) {
      throw const TokenFetchException(TokenFailure.authTimedOut);
    }
    final bool forceRefresh = _takeAuthForcedRefresh();
    return _startCall(
      _auth,
      () => provider.getAccessToken(forceRefresh: forceRefresh),
    );
  }

  /// Whether this fetch forces: Auth owes a refresh and the last forced one is far enough back.
  /// The debt stays otherwise.
  bool _takeAuthForcedRefresh() {
    if (!_auth.owesRefresh) {
      return false;
    }
    final Duration now = _elapsed();
    final Duration? last = _lastForcedAuthRefresh;
    if (last != null && now - last < authForcedRefreshMinInterval) {
      return false;
    }
    _auth.owesRefresh = false;
    _lastForcedAuthRefresh = now;
    return true;
  }

  String? _authTokenOf(_Answer<GetTokenResult>? answer) {
    switch (answer) {
      case null:
        return null;
      case _TimedOut<GetTokenResult>():
        throw const TokenFetchException(TokenFailure.authTimedOut);
      case _Threw<GetTokenResult>(:final Object error):
        if (error is FirebaseNoSignedInUserException ||
            error is FirebaseApiNotAvailableException) {
          return null;
        }
        throw TokenFetchException(
          TokenFailure.authProviderFailed,
          causeType: '${error.runtimeType}',
        );
      case _Value<GetTokenResult>(:final GetTokenResult value):
        return _checkedAuthToken(value.token);
    }
  }

  String? _checkedAuthToken(String token) {
    if (token.isEmpty) {
      return null;
    }
    if (token.length > maxTokenLength) {
      throw const TokenFetchException(TokenFailure.authTokenTooLong);
    }
    if (!isTokenText(token)) {
      throw const TokenFetchException(TokenFailure.authProviderFailed);
    }
    return token;
  }

  /// Starts the App Check step. Nothing is logged here: [_appCheckOf] logs every outcome, once
  /// the request is known to go on.
  _AppCheckAsk _askAppCheck(
    AppCheckTokenProvider? provider, {
    required bool limitedUse,
  }) {
    if (provider == null) {
      return const _AppCheckSettled(AppCheckOutcome.none);
    }
    if (!limitedUse) {
      return _isPaused(_appCheck)
          ? const _AppCheckSettled(AppCheckOutcome.skipped)
          : _AppCheckPending(provider, _sessionCall(provider));
    }
    // The second interface is not a subtype of the first, so the test needs a plain Object to
    // promote.
    final Object minter = provider;
    if (minter is! LimitedUseAppCheckTokenProvider) {
      return _AppCheckUnsupported(provider);
    }
    if (_isPaused(_appCheck)) {
      return const _AppCheckSettled(AppCheckOutcome.skipped);
    }
    return _AppCheckPending(
      provider,
      _startCall(_appCheck, minter.getLimitedUseToken),
    );
  }

  /// The `getToken` call of a session-token request: a pending call of this source on the same
  /// provider object, or a new one. A request that owes a forced refresh never joins: it makes its
  /// own forced call, and making it is what clears the debt.
  _ProviderCall<AppCheckTokenResult> _sessionCall(
    AppCheckTokenProvider provider,
  ) {
    final bool forceRefresh = _appCheck.owesRefresh;
    final _SharedSessionCall? shared = _sharedSessionCall;
    if (!forceRefresh &&
        shared != null &&
        identical(shared.provider, provider) &&
        shared.call.isWaiting) {
      return shared.call..join();
    }
    _appCheck.owesRefresh = false;
    final _ProviderCall<AppCheckTokenResult> call = _startCall(
      _appCheck,
      () => provider.getToken(forceRefresh: forceRefresh),
    );
    _sharedSessionCall = (provider: provider, call: call);
    call.answer.then<void>((_) {
      if (identical(_sharedSessionCall?.call, call)) {
        _sharedSessionCall = null;
      }
    });
    return call;
  }

  /// The token and the outcome of the App Check step, with the warning of the outcome.
  Future<(String?, AppCheckOutcome)> _appCheckOf(_AppCheckAsk ask) async {
    switch (ask) {
      case _AppCheckSettled(:final AppCheckOutcome outcome):
        return (null, outcome);
      case _AppCheckUnsupported(:final AppCheckTokenProvider provider):
        final Type type = provider.runtimeType;
        _warnOnce(
          'app-check-unsupported:$type',
          'App Check: $type cannot mint limited-use tokens; $_sentWithoutAppCheck',
        );
        return (null, AppCheckOutcome.unsupported);
      case _AppCheckPending(
        :final AppCheckTokenProvider provider,
        :final _ProviderCall<AppCheckTokenResult> call,
      ):
        return _appCheckOfAnswer(provider.runtimeType, await call.answer);
    }
  }

  (String?, AppCheckOutcome) _appCheckOfAnswer(
    Type type,
    _Answer<AppCheckTokenResult> answer,
  ) {
    switch (answer) {
      case _TimedOut<AppCheckTokenResult>():
        _warnOnce(
          'app-check-timed-out:$type',
          'App Check: $type did not answer in 10 s; $_sentWithoutAppCheck',
        );
        return (null, AppCheckOutcome.timedOut);
      case _Threw<AppCheckTokenResult>(:final Object error):
        if (error is FirebaseApiNotAvailableException) {
          return (null, AppCheckOutcome.none);
        }
        final Type errorType = error.runtimeType;
        _warnOnce(
          'app-check-threw:$type:$errorType',
          'App Check: $type threw $errorType; $_sentWithoutAppCheck',
        );
        return (null, AppCheckOutcome.providerFailed);
      case _Value<AppCheckTokenResult>(:final AppCheckTokenResult value):
        return _appCheckOfResult(type, value);
    }
  }

  (String?, AppCheckOutcome) _appCheckOfResult(
    Type type,
    AppCheckTokenResult result,
  ) {
    if (!isTokenText(result.token)) {
      _warnOnce(
        'app-check-empty:$type',
        'App Check: $type gave no usable token; $_sentWithoutAppCheck',
      );
      return (null, AppCheckOutcome.empty);
    }
    final Object? error = result.error;
    if (error == null) {
      return (result.token, AppCheckOutcome.sent);
    }
    final Type errorType = error.runtimeType;
    _warnOnce(
      'app-check-placeholder:$type:$errorType',
      'App Check: $type reported $errorType together with a token; that token was sent.',
    );
    return (result.token, AppCheckOutcome.sentPlaceholder);
  }

  void _warnOfRemoteEmulator(Uri url) {
    final EmulatorHost? emulator = _emulator;
    if (emulator != null && emulator.owns(url) && !emulator.isLoopback) {
      _warnOnce('remote-emulator', _remoteEmulatorWarning);
    }
  }

  /// Completes when every call of [calls] has answered or timed out.
  ///
  /// When [timeLeft] is shorter than [providerWait] and runs out first, the calls are abandoned and
  /// the future fails with a [TimeoutException]. No pause starts then: the provider was not given
  /// its full wait.
  Future<void> _settled(List<_ProviderCall<Object>> calls, Duration? timeLeft) {
    final Future<void> all = Future.wait<void>(<Future<void>>[
      for (final _ProviderCall<Object> call in calls) call.answer,
    ]);
    if (timeLeft == null || timeLeft >= providerWait) {
      return all;
    }
    final Completer<void> done = Completer<void>();
    final Timer deadline = Timer(timeLeft, () {
      for (final _ProviderCall<Object> call in calls) {
        call.abandon();
      }
      done.completeError(
        TimeoutException(
          'The call ran out of time while waiting for a token.',
          timeLeft,
        ),
      );
    });
    all.then<void>((_) {
      deadline.cancel();
      if (!done.isCompleted) {
        done.complete();
      }
    });
    return done.future;
  }
}

/// What a [TokenSource] remembers about one kind of token between calls.
final class _KindState {
  /// The backend refused a token of this kind and no forced refresh was made since.
  bool owesRefresh = false;

  /// When the pause of this kind started; null when the provider is not known to be stuck.
  Duration? pausedAt;
}

typedef _SharedSessionCall = ({
  AppCheckTokenProvider provider,
  _ProviderCall<AppCheckTokenResult> call,
});

const String _sentWithoutAppCheck =
    'the request was sent without an App Check token.';
const String _remoteEmulatorWarning =
    'Tokens are sent in clear text to the emulator host, which is not this machine.';

/// The App Check step of one request: a call to wait for, or an outcome known without one.
sealed class _AppCheckAsk {
  const _AppCheckAsk();

  /// The provider call the request waits for, when there is one.
  _ProviderCall<AppCheckTokenResult>? get call => null;
}

final class _AppCheckPending extends _AppCheckAsk {
  const _AppCheckPending(this.provider, this.call);

  final AppCheckTokenProvider provider;

  @override
  final _ProviderCall<AppCheckTokenResult> call;
}

/// No call was made and nothing is logged: no provider, or a paused one.
final class _AppCheckSettled extends _AppCheckAsk {
  const _AppCheckSettled(this.outcome);

  final AppCheckOutcome outcome;
}

/// A limited-use token was asked of a [provider] that cannot mint one; it was not called.
final class _AppCheckUnsupported extends _AppCheckAsk {
  const _AppCheckUnsupported(this.provider);

  final AppCheckTokenProvider provider;
}

sealed class _Answer<T> {
  const _Answer();
}

final class _Value<T> extends _Answer<T> {
  const _Value(this.value);

  final T value;
}

final class _Threw<T> extends _Answer<T> {
  const _Threw(this.error);

  final Object error;
}

final class _TimedOut<T> extends _Answer<T> {
  const _TimedOut();
}

/// One call to a provider, under a wait.
///
/// [answer] never fails and completes at the end of the wait at the latest. What the provider
/// gives after that is dropped, and its late error is handled, so it never becomes an unhandled
/// one. The timer is cancelled as soon as the provider answers.
final class _ProviderCall<T extends Object> {
  _ProviderCall(
    Future<T> Function() ask, {
    required Duration wait,
    required void Function() onAnswer,
    required void Function() onTimeout,
  }) : _onAnswer = onAnswer,
       _onTimeout = onTimeout {
    _timer = Timer(wait, _timedOut);
    final Future<T> result;
    try {
      result = ask();
    } catch (error) {
      _answered(_Threw<T>(error));
      return;
    }
    result.then<void>(
      (T value) => _answered(_Value<T>(value)),
      onError: (Object error) => _answered(_Threw<T>(error)),
    );
  }

  final void Function() _onAnswer;
  final void Function() _onTimeout;
  final Completer<_Answer<T>> _completer = Completer<_Answer<T>>();
  late final Timer _timer;
  int _waiters = 1;

  Future<_Answer<T>> get answer => _completer.future;

  /// Whether the provider has neither answered nor run out of its wait.
  bool get isWaiting => !_completer.isCompleted;

  /// One more request waits for [answer].
  void join() {
    _waiters++;
  }

  /// A request stopped waiting because its own time ran out. When it was the last one, the wait
  /// ends without counting as a timeout of the provider.
  void abandon() {
    _waiters--;
    if (_waiters > 0 || _completer.isCompleted) {
      return;
    }
    _timer.cancel();
    _completer.complete(_TimedOut<T>());
  }

  void _answered(_Answer<T> answer) {
    _timer.cancel();
    _onAnswer();
    if (!_completer.isCompleted) {
      _completer.complete(answer);
    }
  }

  void _timedOut() {
    if (_completer.isCompleted) {
      return;
    }
    _completer.complete(_TimedOut<T>());
    _onTimeout();
  }
}
