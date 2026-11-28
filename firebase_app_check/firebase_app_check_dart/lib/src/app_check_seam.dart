import 'dart:async';

import 'package:firebase_app_check_dart/src/app_check_token.dart';
import 'package:firebase_app_check_dart/src/clocks.dart';
import 'package:firebase_app_check_dart/src/exception.dart';
import 'package:firebase_app_check_dart/src/logger.dart';
import 'package:firebase_app_check_dart/src/token_manager.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:meta/meta.dart';

/// How long a call may wait before it is answered: a little under the 8 s within which every
/// provider must answer, so the answer is out before that limit.
const Duration _answerMargin = Duration(milliseconds: 250);

/// What the seam object forwards to while it is bound.
final class _Binding {
  _Binding({required this.manager, required this.clocks, required this.events});

  final TokenManager manager;
  final Clocks clocks;
  final StreamSubscription<TokenEvent> events;
}

/// The provider that the services of an app ask for App Check tokens: one per app, kept for the
/// app's life.
///
/// Firestore, Auth and the Realtime Database keep the provider they read when they were created.
/// So this object stays on the app when its `FirebaseAppCheck` is closed, and a later
/// `FirebaseAppCheck` of the same app binds to it again: the services that kept it follow.
///
/// Bound, it forwards to the instance's [TokenManager] and never throws. Unbound, both methods
/// answer with an empty token and a [StateError], so services send no App Check header: a closed
/// App Check is "no App Check", not "attestation failed".
///
/// Every call is answered within [AppCheckTokenProvider.responseDeadline]. The manager's own
/// waits add up to less (500 ms for the stored record, 7 s for an exchange), with one exception:
/// a forced call that joined an exchange and then has to run its own. So each call has a timer of
/// its own, 250 ms under the deadline. When it fires, [getToken] answers with the cached token and
/// the error while that token has not expired, otherwise with the placeholder, and
/// [getLimitedUseToken] with the placeholder. The work goes on in the background: a session token
/// it brings is cached for the next call, and a limited-use token is dropped.
///
/// [onTokenChanged] is one broadcast stream across bindings; it ends when the app is deleted.
@internal
final class AppCheckSeam extends AppCheckTokenProvider
    implements LimitedUseAppCheckTokenProvider {
  /// An unbound seam object for [app]. It listens to the app's deletion to end [onTokenChanged].
  AppCheckSeam(FirebaseApp app) {
    _appDeleted = app.onDeleteApp.listen((String _) {
      unawaited(_appDeleted.cancel());
      unawaited(_changes.close());
    });
  }

  final StreamController<AppCheckTokenResult> _changes =
      StreamController<AppCheckTokenResult>.broadcast();
  late final StreamSubscription<String> _appDeleted;

  _Binding? _binding;
  String? _lastAnnounced;

  /// The logger and the app name of the instance that was bound last, for the line written after
  /// its close.
  AppCheckLogger? _logger;
  String _appName = '';
  bool _closeLogged = true;

  /// True while a `FirebaseAppCheck` is bound.
  bool get isBound => _binding != null;

  /// Binds an open instance: calls go to [manager], and the announced tokens of [events] are
  /// emitted on [onTokenChanged]. [clocks] judge whether a token that comes with a failure is
  /// still usable.
  ///
  /// Throws a [StateError] when an instance is bound already.
  void bind({
    required TokenManager manager,
    required Stream<TokenEvent> events,
    required Clocks clocks,
    required AppCheckLogger? logger,
    required String appName,
  }) {
    if (_binding != null) {
      throw StateError('This App Check seam object is bound already.');
    }
    _logger = logger;
    _appName = appName;
    _binding = _Binding(
      manager: manager,
      clocks: clocks,
      events: events.listen(_onEvent),
    );
  }

  /// Unbinds the instance: from now on, and for every call that is waiting, the answer is the
  /// closed one. Does nothing when no instance is bound.
  void unbind() {
    final _Binding? binding = _binding;
    if (binding == null) {
      return;
    }
    _binding = null;
    _closeLogged = false;
    unawaited(binding.events.cancel());
  }

  @override
  Future<AppCheckTokenResult> getToken({required bool forceRefresh}) async {
    final _Binding? binding = _binding;
    if (binding == null) {
      return _closedResult();
    }
    final Outcome outcome;
    try {
      outcome = await _answeredInTime(
        binding.manager.obtain(forceRefresh: forceRefresh),
        () => _overdue(binding),
      );
    } on Object catch (error) {
      // A missing option of the app (a StateError); the seam never throws.
      return _isCurrent(binding)
          ? AppCheckTokenResult.failure(error)
          : _closedResult();
    }
    if (!_isCurrent(binding)) {
      return _closedResult();
    }
    return _resultOf(outcome, binding.clocks);
  }

  @override
  Future<AppCheckTokenResult> getLimitedUseToken() async {
    final _Binding? binding = _binding;
    if (binding == null) {
      return _closedResult();
    }
    try {
      final AppCheckTokenResult result = await _answeredInTime(
        binding.manager.limitedUse().then(
          (SessionToken token) => AppCheckTokenResult(token.token),
        ),
        () => AppCheckTokenResult.failure(fetchTimeout()),
      );
      return _isCurrent(binding) ? result : _closedResult();
    } on Object catch (error) {
      return _isCurrent(binding) && !_isClosedFailure(error)
          ? AppCheckTokenResult.failure(error)
          : _closedResult();
    }
  }

  @override
  Stream<AppCheckTokenResult> get onTokenChanged => _changes.stream;

  @override
  String toString() => 'AppCheckSeam(${isBound ? 'bound' : 'unbound'})';

  /// Completes like [work], or with [onDeadline]'s value when [work] is still running 250 ms
  /// before the response deadline. [work] is not cancelled, and what it brings later is not
  /// reported here.
  Future<T> _answeredInTime<T>(Future<T> work, T Function() onDeadline) {
    final Completer<T> done = Completer<T>();
    final Timer timer = Timer(
      AppCheckTokenProvider.responseDeadline - _answerMargin,
      () {
        if (!done.isCompleted) {
          done.complete(onDeadline());
        }
      },
    );
    unawaited(
      work.then<void>(
        (T value) {
          timer.cancel();
          if (!done.isCompleted) {
            done.complete(value);
          }
        },
        onError: (Object error, StackTrace stack) {
          timer.cancel();
          if (!done.isCompleted) {
            done.completeError(error, stack);
          }
        },
      ),
    );
    return done.future;
  }

  /// The outcome of a session call that ran out of time: a timeout, with the cached token while
  /// it has not expired.
  Outcome _overdue(_Binding binding) {
    final SessionToken? cached = binding.manager.current;
    final bool unexpired = cached != null && cached.isUnexpired(binding.clocks);
    return Outcome.failed(fetchTimeout(), token: unexpired ? cached : null);
  }

  bool _isCurrent(_Binding binding) => identical(_binding, binding);

  bool _isClosedFailure(Object error) =>
      error is FirebaseAppCheckException && error.code == 'app-check-closed';

  /// A token alone is usable. A token that comes with a failure is sent without the error while
  /// it is usable (a forced call that could not replace it), and with the error in its last
  /// minutes. A failure alone is the placeholder.
  AppCheckTokenResult _resultOf(Outcome outcome, Clocks clocks) {
    final SessionToken? token = outcome.token;
    final FirebaseAppCheckException? failure = outcome.failure;
    if (token == null) {
      return failure == null || _isClosedFailure(failure)
          ? _closedResult()
          : AppCheckTokenResult.failure(failure);
    }
    if (failure == null || token.isUsable(clocks)) {
      return AppCheckTokenResult(token.token);
    }
    return AppCheckTokenResult(token.token, error: failure);
  }

  /// The answer of a closed App Check: an empty token, so no header is sent. The first one after
  /// each unbinding writes the line L5 through the logger of the instance that was bound.
  AppCheckTokenResult _closedResult() {
    if (!_closeLogged) {
      _closeLogged = true;
      _logger?.call(AppCheckLogLevel.warning, closedText(_appName));
    }
    return AppCheckTokenResult(
      '',
      error: StateError('This FirebaseAppCheck was closed.'),
    );
  }

  void _onEvent(TokenEvent event) {
    final String token = event.token.token;
    if (!event.announce || token == _lastAnnounced || _changes.isClosed) {
      return;
    }
    _lastAnnounced = token;
    _changes.add(AppCheckTokenResult(token));
  }
}
