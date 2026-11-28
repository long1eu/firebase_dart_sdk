import 'dart:async';

import 'package:_firebase_transport_dart/_firebase_transport_dart.dart';
import 'package:firebase_data_connect_dart/src/errors.dart';
import 'package:firebase_data_connect_dart/src/transport/transport.dart';

/// Runs the attempts of one operation: one, and at most one more after the service refused the
/// Auth token of the first.
///
/// Every attempt fetches its own tokens and has its own budget of `requestTimeout`, which covers
/// the wait for the tokens and the request. The second attempt is made only when all of these
/// hold:
///
/// 1. the first ended with the status `unauthenticated`;
/// 2. the first carried an Auth token: a call without a signed-in user is never sent twice, and
///    costs no token refresh;
/// 3. after `invalidate(TokenKind.auth)` the token source gives tokens that differ from those of
///    the first attempt. The source forces an Auth refresh at most once per
///    [TokenSource.authForcedRefreshMinInterval], so a second refusal inside that time brings the
///    same tokens back and the call ends `unauthenticated` with one request.
///
/// The App Check token is never invalidated: no refusal of the service that names App Check is
/// known. Queries and mutations follow the same rule.
final class OperationRunner {
  /// A runner that takes tokens from [tokenSource] and gives each attempt [requestTimeout],
  /// measured with the monotonic clock [elapsed].
  ///
  /// [isClosed] is asked after every wait; once it answers true the call ends with
  /// [clientClosedException] and nothing more is sent.
  OperationRunner({
    required TokenSource tokenSource,
    required Duration requestTimeout,
    required Duration Function() elapsed,
    required bool Function() isClosed,
  }) : _tokenSource = tokenSource,
       _requestTimeout = requestTimeout,
       _elapsed = elapsed,
       _isClosed = isClosed;

  final TokenSource _tokenSource;
  final Duration _requestTimeout;
  final Duration Function() _elapsed;
  final bool Function() _isClosed;

  /// Sends the operation [operationName] of [kind] over [transport] and gives what the last
  /// attempt returned: a response, or the failure of the transport.
  ///
  /// Throws a [DataConnectException] when an attempt could not be sent: `client-closed`,
  /// `deadline-exceeded` when its budget ran out during the token wait, or the code of a token
  /// failure (`unauthenticated`, `unavailable`, `failed-precondition`). Such a failure is not
  /// retried, and its `cause` is null.
  Future<WireResult> run(
    OperationTransport transport,
    OperationKind kind,
    String operationName,
    Map<String, Object?>? variables,
  ) async {
    final _Call call = _Call(transport, kind, operationName, variables);
    final _Attempt first = await _prepare(call);
    final WireResult result = await _send(call, first);
    if (!_isAuthRefusal(result) || !first.tokens.hasAuthToken) {
      return result;
    }
    _tokenSource.invalidate(TokenKind.auth);
    final _Attempt second = await _prepare(call);
    if (second.tokens.sameTokensAs(first.tokens)) {
      return result;
    }
    return _send(call, second);
  }

  /// Starts the budget of an attempt and fetches its tokens.
  Future<_Attempt> _prepare(_Call call) async {
    if (_isClosed()) {
      throw clientClosedException();
    }
    final Duration startedAt = _elapsed();
    final RequestTokens tokens;
    try {
      tokens = await _tokenSource.tokensFor(
        call.transport.tokenUrl(call.kind),
        timeLeft: _requestTimeout,
      );
    } on TokenFetchException catch (failure) {
      throw exceptionOfTokenFailure(failure);
    } on TimeoutException {
      throw _outOfTime();
    } on StateError {
      // The token source reports a deleted app this way; the instance of a deleted app is closed.
      if (_isClosed()) {
        throw clientClosedException();
      }
      rethrow;
    }
    if (_isClosed()) {
      throw clientClosedException();
    }
    return _Attempt(tokens, startedAt);
  }

  /// Sends [attempt] within what its token wait left of the budget.
  Future<WireResult> _send(_Call call, _Attempt attempt) async {
    final Duration timeLeft =
        _requestTimeout - (_elapsed() - attempt.startedAt);
    if (timeLeft <= Duration.zero) {
      throw _outOfTime();
    }
    final WireResult result = await call.transport.execute(
      call.kind,
      call.operationName,
      call.variables,
      attempt.tokens,
      timeout: timeLeft,
    );
    if (_isClosed()) {
      throw clientClosedException();
    }
    return result;
  }
}

/// What every attempt of one call sends.
final class _Call {
  const _Call(this.transport, this.kind, this.operationName, this.variables);

  final OperationTransport transport;
  final OperationKind kind;
  final String operationName;
  final Map<String, Object?>? variables;
}

/// An attempt that has its tokens and was not sent yet.
final class _Attempt {
  const _Attempt(this.tokens, this.startedAt);

  final RequestTokens tokens;

  /// The clock reading at which the budget of the attempt started.
  final Duration startedAt;
}

bool _isAuthRefusal(WireResult result) {
  return result is WireFailure &&
      !result.invalidResponse &&
      result.status == RpcStatus.unauthenticated;
}

DataConnectException _outOfTime() {
  return DataConnectException(
    RpcStatus.deadlineExceeded.kebab,
    message: 'The call ran out of time while waiting for a token.',
  );
}
