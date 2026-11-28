import 'dart:async';

import 'package:_firebase_transport_dart/_firebase_transport_dart.dart';
import 'package:firebase_app_check_dart/src/app_check_token.dart';
import 'package:firebase_app_check_dart/src/clocks.dart';
import 'package:firebase_app_check_dart/src/exception.dart';
import 'package:firebase_app_check_dart/src/exchange_client.dart';
import 'package:firebase_app_check_dart/src/gate.dart';
import 'package:firebase_app_check_dart/src/logger.dart';
import 'package:firebase_app_check_dart/src/provider.dart';
import 'package:firebase_app_check_dart/src/token_store.dart';
import 'package:meta/meta.dart';

/// How long the calls that arrive during the first load of the stored record wait for it.
const Duration _loadLimit = Duration(milliseconds: 500);

/// The forced floor: a forced call gets the cached token while it is younger than this.
const Duration _forcedFloor = Duration(seconds: 30);

/// The shortest and the longest lifetime of a custom provider's token.
const Duration _minCustomLife = Duration(seconds: 60);
const Duration _maxCustomLife = Duration(days: 7);

/// The ids of the two "requests are paused" lines, one per gate.
const String _sessionPause = 'session';
const String _limitedUsePause = 'limited-use';

/// How a request for the session token ended: a [token], a [token] together with a [failure], or
/// a [failure].
///
/// With both set, the exchange failed and the cached token has not expired. The token may still
/// be usable (a forced call that could not replace it) or be in its last minutes: the reader
/// checks `isUsable`.
@internal
final class Outcome {
  /// The session token, with nothing to report.
  const Outcome.token(SessionToken this.token) : failure = null;

  /// The exchange failed with [failure]; [token] is the cached token when it has not expired.
  const Outcome.failed(FirebaseAppCheckException this.failure, {this.token});

  /// The session token to hand out, if there is one.
  final SessionToken? token;

  /// Why no new token could be had, if an exchange failed or was refused.
  final FirebaseAppCheckException? failure;
}

/// One session exchange in flight.
final class _Flight {
  _Flight(this.future, {required this.forced});

  final Future<SessionToken> future;

  /// True when the call that started the exchange was forced.
  final bool forced;
}

/// Owns the cached session token of one instance, the one session exchange in flight, the two
/// gates and the first load of the stored record. It runs the provider.
///
/// Three controls bound how often it exchanges: a cached token is handed out while it is usable;
/// a forced call gets the cached token while it is younger than 30 s; and after a failure a gate
/// refuses exchanges for a while.
@internal
final class TokenManager {
  /// A manager for [provider]. [exchangeClient] is needed with a debug provider only, and
  /// [tokenStore] only when the token is persisted. [random] returns a number in [0, 1) and is
  /// the jitter of the gates. [appName] is used in log lines only.
  TokenManager({
    required AppCheckProvider provider,
    required ExchangeClient? exchangeClient,
    required TokenStore? tokenStore,
    required Clocks clocks,
    required double Function() random,
    required AppCheckLogger? logger,
    required String appName,
  }) : _provider = provider,
       _exchangeClient = exchangeClient,
       _tokenStore = tokenStore,
       _clocks = clocks,
       _logger = logger,
       _appName = appName,
       _sessionGate = ExchangeGate(clocks: clocks, random: random),
       _limitedUseGate = ExchangeGate(clocks: clocks, random: random),
       _paused = logOnceAt(logger, AppCheckLogLevel.warning);

  final AppCheckProvider _provider;
  final ExchangeClient? _exchangeClient;
  final TokenStore? _tokenStore;
  final Clocks _clocks;
  final AppCheckLogger? _logger;
  final String _appName;
  final ExchangeGate _sessionGate;
  final ExchangeGate _limitedUseGate;
  final LogOnce _paused;

  final StreamController<TokenEvent> _events =
      StreamController<TokenEvent>.broadcast();

  /// What ends each pending wait when [close] runs.
  final Set<void Function()> _closers = <void Function()>{};

  SessionToken? _current;
  _Flight? _flight;
  Completer<void>? _loadWait;
  Timer? _loadTimer;
  StreamSubscription<void>? _storeChanges;
  bool _closed = false;

  /// The cached session token, usable or not, or null when there is none.
  SessionToken? get current => _current;

  /// One event each time the cached token is replaced, also by the same string. Broadcast, no
  /// replay; done after [close].
  Stream<TokenEvent> get events => _events.stream;

  /// The time left in the session gate's window; zero while the gate is open.
  Duration get sessionGateRemaining => _sessionGate.remaining;

  /// Gets the session token, exchanging when the cached one will not do.
  ///
  /// Not forced, a usable cached token is the answer. Forced, the cached token is the answer only
  /// inside the forced floor. Otherwise the call joins the exchange in flight or starts one, and
  /// after a failure falls back to the cached token while it has not expired.
  ///
  /// Completes with a [StateError] when the debug provider lacks an option of the app; no request
  /// is sent and no gate is touched then. Every other failure is in the [Outcome].
  Future<Outcome> obtain({required bool forceRefresh}) async {
    if (_closed) {
      return Outcome.failed(appCheckClosed());
    }
    await _firstLoad();
    if (_closed) {
      return Outcome.failed(appCheckClosed());
    }
    final SessionToken? cached = _current;
    if (cached != null && _answersWithoutExchange(cached, forceRefresh)) {
      return Outcome.token(cached);
    }
    try {
      return Outcome.token(
        await _exchanged(forced: forceRefresh, rejected: cached?.token),
      );
    } on FirebaseAppCheckException catch (failure) {
      return _afterFailure(failure);
    }
  }

  /// The refresher's entry: waits for the exchange in flight, or runs one without force while
  /// the session gate is open. Never throws: a failure is in the gate and in the log.
  Future<void> refresh() async {
    if (_closed) {
      return;
    }
    try {
      final _Flight? flight = _flight;
      if (flight != null) {
        await flight.future;
      } else if (!_sessionGate.isClosed) {
        await _startSession(forced: false);
      }
    } on FirebaseAppCheckException {
      // The exchange that failed told the gate and wrote the log line.
    } on StateError {
      // A missing option of the app: every public call reports it.
    }
  }

  /// A new limited-use token: one exchange per call, never shared, cached, stored or announced.
  /// Its outcome goes to the limited-use gate only.
  ///
  /// Throws a [FirebaseAppCheckException], or the [StateError] of [obtain].
  Future<SessionToken> limitedUse() async {
    if (_closed) {
      throw appCheckClosed();
    }
    if (_limitedUseGate.isClosed) {
      throw _refusal(_limitedUseGate, _limitedUsePause);
    }
    final int generation = _limitedUseGate.begin();
    final SessionToken token;
    try {
      token = await _mint(limitedUse: true, forceRefresh: false);
    } on FirebaseAppCheckException catch (error) {
      if (_closed) {
        throw appCheckClosed();
      }
      throw _counted(_limitedUseGate, _limitedUsePause, generation, error);
    }
    if (_closed) {
      throw appCheckClosed();
    }
    _limitedUseGate.succeeded(generation);
    return token;
  }

  /// Reads the stored record and adopts it when it was issued later than the cached token (on the
  /// wall clock), or when there is no cached token. True when the cached token was replaced.
  Future<bool> adoptFromStore() async {
    final TokenStore? store = _tokenStore;
    if (store == null || _closed) {
      return false;
    }
    final SessionToken? stored = await store.readIfIssuedAfter(_current);
    if (stored == null || _closed || !_isIssuedAfterCurrent(stored)) {
      return false;
    }
    _replace(stored, TokenOrigin.adopt, announce: true);
    return true;
  }

  /// Answers every pending wait with `app-check-closed`, stops listening to the store and ends
  /// [events]. The result of an exchange or a callback still running is dropped: it sets no
  /// token, feeds no gate and writes no log line. Idempotent.
  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    _loadTimer?.cancel();
    final Completer<void>? loadWait = _loadWait;
    if (loadWait != null && !loadWait.isCompleted) {
      loadWait.complete();
    }
    for (final void Function() closer in _closers.toList()) {
      closer();
    }
    _closers.clear();
    unawaited(_storeChanges?.cancel());
    _tokenStore?.close();
    unawaited(_events.close());
  }

  /// True when [cached] is the answer without an exchange: usable for a call that is not forced,
  /// inside the forced floor for one that is.
  bool _answersWithoutExchange(SessionToken cached, bool forced) {
    if (!forced) {
      return cached.isUsable(_clocks);
    }
    return cached.isUnexpired(_clocks) &&
        _clocks.monoNow() - cached.issuedMono < _forcedFloor;
  }

  /// The token of the exchange in flight, or of a new one when none is in flight and the session
  /// gate is open. Throws the failure otherwise.
  ///
  /// A forced call does not take the token of an exchange that was started without force when it
  /// is the [rejected] string again (a custom callback that was not told `forceRefresh` may
  /// return it): it then runs, or joins, a forced exchange.
  Future<SessionToken> _exchanged({
    required bool forced,
    required String? rejected,
  }) async {
    _Flight? flight = _flight;
    while (flight != null) {
      final SessionToken token = await flight.future;
      if (!forced || flight.forced || token.token != rejected) {
        return token;
      }
      flight = _flight;
    }
    if (_sessionGate.isClosed) {
      throw _refusal(_sessionGate, _sessionPause);
    }
    return _startSession(forced: forced);
  }

  /// After [failure]: the cached token goes with it while it has not expired.
  Outcome _afterFailure(FirebaseAppCheckException failure) {
    if (_closed) {
      return Outcome.failed(appCheckClosed());
    }
    final SessionToken? cached = _current;
    final bool unexpired = cached != null && cached.isUnexpired(_clocks);
    return Outcome.failed(failure, token: unexpired ? cached : null);
  }

  Future<SessionToken> _startSession({required bool forced}) {
    final Future<SessionToken> future = _runSession(forced: forced);
    _flight = _Flight(future, forced: forced);
    return future;
  }

  /// One session exchange: on success the token is cached, stored and announced; on failure the
  /// gate is told and the line L3 is written.
  Future<SessionToken> _runSession({required bool forced}) async {
    final int generation = _sessionGate.begin();
    try {
      final SessionToken token = await _mint(
        limitedUse: false,
        forceRefresh: forced,
      );
      if (_closed) {
        throw appCheckClosed();
      }
      _sessionGate.succeeded(generation);
      _keep(token);
      return token;
    } on FirebaseAppCheckException catch (error) {
      if (_closed) {
        throw appCheckClosed();
      }
      final FirebaseAppCheckException failure = _counted(
        _sessionGate,
        _sessionPause,
        generation,
        error,
      );
      _logger?.call(
        AppCheckLogLevel.warning,
        requestFailedText(_appName, failure, _sessionGate.remaining),
      );
      throw failure;
    } finally {
      _flight = null;
    }
  }

  /// A token of this instance's own provider becomes the cached one.
  void _keep(SessionToken token) {
    _replace(token, TokenOrigin.exchange, announce: true);
    _tokenStore?.save(token);
  }

  void _replace(
    SessionToken token,
    TokenOrigin origin, {
    required bool announce,
  }) {
    if (_closed) {
      return;
    }
    _current = token;
    _events.add(TokenEvent(token, origin, announce: announce));
  }

  bool _isIssuedAfterCurrent(SessionToken token) {
    final SessionToken? cached = _current;
    return cached == null || token.issuedWall.isAfter(cached.issuedWall);
  }

  /// The `throttled` failure of a call that [gate] refused; the first one of each window writes
  /// the line L4.
  FirebaseAppCheckException _refusal(ExchangeGate gate, String id) {
    _paused(id, requestsPausedText(_appName, gate.remaining));
    return throttled(retryAfter: gate.retryAfter, httpStatus: gate.httpStatus);
  }

  /// Tells [gate] that the exchange which noted [generation] failed with [error], and returns
  /// [error] with the end of the gate's window as its `retryAfter`.
  FirebaseAppCheckException _counted(
    ExchangeGate gate,
    String id,
    int generation,
    FirebaseAppCheckException error,
  ) {
    final Duration? wait = gate.failed(
      generation,
      refused: isRefusal(error),
      httpStatus: error.httpStatus,
    );
    if (wait != null) {
      // A new window: its first refused call is logged again.
      _paused.reset(id);
    }
    final DateTime? retryAfter = gate.retryAfter;
    return retryAfter == null ? error : withRetryAfter(error, retryAfter);
  }

  /// Runs the provider once. Completes with `app-check-closed` when [close] runs first.
  Future<SessionToken> _mint({
    required bool limitedUse,
    required bool forceRefresh,
  }) async {
    final AppCheckProvider provider = _provider;
    if (provider is DebugAppCheckProvider) {
      final ExchangeClient? client = _exchangeClient;
      if (client == null) {
        throw StateError('A debug provider needs an exchange client.');
      }
      return _untilClosed(
        client.exchange(
          debugToken: debugTokenOf(provider),
          limitedUse: limitedUse,
        ),
      );
    }
    if (provider is CustomAppCheckProvider) {
      return _callCustom(
        provider,
        limitedUse: limitedUse,
        forceRefresh: forceRefresh,
      );
    }
    throw StateError('Unknown kind of AppCheckProvider.');
  }

  /// Calls the custom callback under the 7 s deadline.
  ///
  /// The callback cannot be cancelled. Its answer after the deadline is kept when it is for the
  /// session and passes the rules: it becomes the cached token and the session gate is reset as
  /// after a success. A late limited-use answer is dropped: nobody waits for it and it may not be
  /// cached. What the callback throws is kept as the `cause` and never put into a message.
  Future<SessionToken> _callCustom(
    CustomAppCheckProvider provider, {
    required bool limitedUse,
    required bool forceRefresh,
  }) {
    final Completer<SessionToken> done = Completer<SessionToken>();
    final Timer deadline = Timer(providerDeadline, () {
      if (!done.isCompleted) {
        done.completeError(providerTimeout(), StackTrace.current);
      }
    });
    final Future<AppCheckToken> pending = Future<AppCheckToken>.sync(
      () => customCallbackOf(provider)(
        limitedUse: limitedUse,
        forceRefresh: forceRefresh,
      ),
    );
    unawaited(
      pending.then<void>(
        (AppCheckToken answer) {
          deadline.cancel();
          _onCustomAnswer(
            answer,
            done,
            limitedUse: limitedUse,
            forceRefresh: forceRefresh,
          );
        },
        onError: (Object error, StackTrace stack) {
          deadline.cancel();
          if (!done.isCompleted) {
            done.completeError(
              providerError(ProviderProblem.threw, cause: error),
              stack,
            );
          }
        },
      ),
    );
    return _untilClosed(done.future, timer: deadline);
  }

  /// The callback returned [answer]: in time, it settles [done]; late, a session answer that
  /// passes the rules is kept and one that fails a rule is dropped.
  void _onCustomAnswer(
    AppCheckToken answer,
    Completer<SessionToken> done, {
    required bool limitedUse,
    required bool forceRefresh,
  }) {
    if (_closed) {
      return;
    }
    final bool late = done.isCompleted;
    try {
      final SessionToken token = _accepted(
        answer,
        replacing: forceRefresh && !limitedUse,
      );
      if (!late) {
        done.complete(token);
      } else if (!limitedUse) {
        _sessionGate.succeeded(_sessionGate.begin());
        _keep(token);
      }
    } on FirebaseAppCheckException catch (error, stack) {
      if (!late) {
        done.completeError(error, stack);
      }
    }
  }

  /// The rules for a custom provider's [answer]. The issue time is now, the moment the callback
  /// returned; the JWT is not parsed, because this package cannot verify it.
  ///
  /// [replacing] is true for the answer to a forced session request: the cached token was
  /// rejected, so the same string again is not a refresh.
  SessionToken _accepted(AppCheckToken answer, {required bool replacing}) {
    final DateTime issuedWall = _clocks.wallNow();
    final Duration issuedMono = _clocks.monoNow();
    if (!isTokenText(answer.token)) {
      throw providerError(ProviderProblem.invalidToken);
    }
    final Duration life = answer.expireTime.difference(issuedWall);
    if (life < _minCustomLife) {
      throw providerError(ProviderProblem.expiresTooSoon);
    }
    if (replacing && answer.token == _current?.token) {
      throw providerError(ProviderProblem.sameToken);
    }
    return SessionToken(
      token: answer.token,
      issuedWall: issuedWall,
      issuedMono: issuedMono,
      ttl: life > _maxCustomLife ? _maxCustomLife : life,
    );
  }

  /// Completes like [work], or with `app-check-closed` when [close] runs first; [timer] is
  /// cancelled then. A result of [work] that arrives after the close is dropped.
  Future<T> _untilClosed<T>(Future<T> work, {Timer? timer}) {
    final Completer<T> done = Completer<T>();
    void closer() {
      timer?.cancel();
      if (!done.isCompleted) {
        done.completeError(appCheckClosed(), StackTrace.current);
      }
    }

    _closers.add(closer);
    unawaited(
      work.then<void>(
        (T value) {
          _closers.remove(closer);
          if (!done.isCompleted) {
            done.complete(value);
          }
        },
        onError: (Object error, StackTrace stack) {
          _closers.remove(closer);
          if (!done.isCompleted) {
            done.completeError(error, stack);
          }
        },
      ),
    );
    return done.future;
  }

  /// The first load of the stored record: started by the first call, awaited by that call and by
  /// every call that arrives before it settles, for at most 500 ms from its start.
  Future<void> _firstLoad() {
    final TokenStore? store = _tokenStore;
    if (store == null) {
      return Future<void>.value();
    }
    return (_loadWait ??= _startLoad(store)).future;
  }

  Completer<void> _startLoad(TokenStore store) {
    final Completer<void> wait = Completer<void>();
    void settle() {
      if (!wait.isCompleted) {
        wait.complete();
      }
    }

    _storeChanges = store.changed.listen((_) => unawaited(adoptFromStore()));
    _loadTimer = Timer(_loadLimit, settle);
    unawaited(
      store.load().then<void>((SessionToken? token) {
        _loadTimer?.cancel();
        if (token != null && !_closed) {
          _applyLoaded(token, slow: wait.isCompleted);
        }
        settle();
      }),
    );
    return wait;
  }

  /// A record that arrived within the 500 ms becomes the cached token; it is announced only when
  /// it is usable, because one in its last minutes is about to be replaced. A [slow] load counted
  /// as "nothing stored" for the calls that waited, so its record is adopted only when it was
  /// issued later than what is cached by now.
  void _applyLoaded(SessionToken token, {required bool slow}) {
    if (_current == null && !slow) {
      _replace(token, TokenOrigin.load, announce: token.isUsable(_clocks));
    } else if (_isIssuedAfterCurrent(token)) {
      _replace(token, TokenOrigin.adopt, announce: true);
    }
  }
}
