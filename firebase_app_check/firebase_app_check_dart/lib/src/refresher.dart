import 'dart:async';

import 'package:firebase_app_check_dart/src/app_check_token.dart';
import 'package:firebase_app_check_dart/src/clocks.dart';
import 'package:firebase_app_check_dart/src/logger.dart';
import 'package:firebase_app_check_dart/src/token_manager.dart';
import 'package:meta/meta.dart';

/// The margin of the usable rule, and the time added to half the lifetime in the due time.
const Duration _margin = Duration(minutes: 5);

/// The largest lead: how much earlier than its due time a refresh may run.
const Duration _maxLead = Duration(minutes: 2);

/// No refresh runs sooner than this after the token's issue, and none sooner than this after a
/// failed one.
const Duration _floor = Duration(seconds: 30);

Duration _smaller(Duration a, Duration b) => a < b ? a : b;

/// How long from now until [token] is due for its proactive refresh; zero when the time has
/// passed.
///
/// The due time, counted from the issue on the monotonic source, is
/// `min(ttl/2 + 5 min, ttl − min(5 min, ttl/2)) − lead`, and at least 30 s. The lead is
/// [lead01] (a draw in [0, 1)) times `min(2 min, ttl/10)`: instances that hold the same stored
/// token then come due at different moments, and the first one's new token is adopted by the
/// others. A draw outside [0, 1) counts as 0.
@internal
Duration refreshDelay(SessionToken token, Clocks clocks, double lead01) {
  final Duration ttl = token.ttl;
  final Duration half = ttl ~/ 2;
  final Duration due = _smaller(half + _margin, ttl - _smaller(_margin, half));
  final double draw = lead01 >= 0 && lead01 < 1 ? lead01 : 0;
  final Duration lead = _smaller(_maxLead, ttl ~/ 10) * draw;
  final Duration afterIssue = due - lead < _floor ? _floor : due - lead;
  final Duration delay = afterIssue - (clocks.monoNow() - token.issuedMono);
  return delay < Duration.zero ? Duration.zero : delay;
}

/// Replaces the session token before it stops being usable: one timer per instance.
///
/// It schedules from every replacement of the cached token, whatever its origin, and does not
/// depend on anyone listening. It has no backoff of its own: after a failure it runs again when
/// the session gate opens, and not sooner than 30 s later. A timer that fires late delays only
/// this proactive refresh: every call judges the cached token at the time of the call.
@internal
final class TokenRefresher {
  /// A refresher for [manager]'s token, switched on or off by [enabled]. [random] returns a
  /// number in [0, 1) and draws the lead. [appName] is used in log lines only.
  TokenRefresher({
    required TokenManager manager,
    required Clocks clocks,
    required double Function() random,
    required bool enabled,
    required AppCheckLogger? logger,
    required String appName,
  }) : _manager = manager,
       _clocks = clocks,
       _random = random,
       _enabled = enabled,
       _logger = logger,
       _appName = appName {
    _events = manager.events.listen(_onEvent);
  }

  final TokenManager _manager;
  final Clocks _clocks;
  final double Function() _random;
  final AppCheckLogger? _logger;
  final String _appName;
  late final StreamSubscription<TokenEvent> _events;

  bool _enabled;
  bool _closed = false;
  bool _running = false;
  Timer? _timer;

  /// Whether the token is refreshed before it stops being usable.
  bool get enabled => _enabled;

  /// Switches the refresher: off cancels the timer; on schedules from the cached token, if there
  /// is one.
  void setEnabled(bool enabled) {
    if (_closed || enabled == _enabled) {
      return;
    }
    _enabled = enabled;
    _cancelTimer();
    final SessionToken? current = _manager.current;
    if (enabled && current != null) {
      _schedule(current);
    }
  }

  /// Cancels the timer and stops listening. Idempotent.
  void close() {
    _closed = true;
    _cancelTimer();
    unawaited(_events.cancel());
  }

  void _onEvent(TokenEvent event) {
    if (_closed || !_enabled) {
      return;
    }
    final Duration delay = _schedule(event.token);
    if (event.origin == TokenOrigin.exchange) {
      _logger?.call(AppCheckLogLevel.debug, tokenReceivedText(_appName, delay));
    }
  }

  /// Sets the timer for [token]'s due time, with a new lead, and returns the delay.
  Duration _schedule(SessionToken token) {
    final Duration delay = refreshDelay(token, _clocks, _random());
    _setTimer(delay);
    return delay;
  }

  void _setTimer(Duration delay) {
    _cancelTimer();
    _timer = Timer(delay, () {
      _timer = null;
      unawaited(_run());
    });
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// At the due time: adopt a stored token that was issued later; otherwise let the manager wait
  /// for the exchange in flight or run one. A new token arrives as an event, which schedules the
  /// next run; without one, this method schedules the retry.
  Future<void> _run() async {
    if (_running) {
      return;
    }
    _running = true;
    final SessionToken? before = _manager.current;
    if (!await _manager.adoptFromStore()) {
      await _manager.refresh();
    }
    _running = false;
    if (_closed || !_enabled || _timer != null) {
      return;
    }
    final SessionToken? after = _manager.current;
    if (after != null && !identical(after, before)) {
      // The token was replaced during this run; the timer its event set may have fired, and
      // been skipped, while the run was still busy.
      _schedule(after);
      return;
    }
    final Duration gate = _manager.sessionGateRemaining;
    _setTimer(gate > _floor ? gate : _floor);
  }
}
