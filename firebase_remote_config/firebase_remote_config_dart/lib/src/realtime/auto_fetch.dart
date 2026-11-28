import 'dart:async';

import 'package:firebase_remote_config_dart/src/exception.dart';
import 'package:firebase_remote_config_dart/src/realtime/updated_keys.dart';
import 'package:firebase_remote_config_dart/src/template.dart';
import 'package:firebase_remote_config_dart/src/types.dart';

/// The active and the fetched record, as memory holds them now.
typedef TemplateRecords = ({TemplateRecord? active, TemplateRecord? fetched});

/// The version the client already knows (5.9 Fields, step 2): the fetched record's version, else the
/// active record's, else 0.
int knownVersion(TemplateRecords records) =>
    records.fetched?.templateVersion ?? records.active?.templateVersion ?? 0;

/// The auto-fetch of 5.9.2 as built (A12, A19): one chain at a time per instance, up to three attempts
/// after an invalidation.
///
/// An attempt is up to date only when [knownVersion] reaches the chain's target; an `unchanged` answer
/// below the target (a lagging backend) is not, and the next attempt follows. After a chain that did not
/// end up to date (its attempts ran out, or one failed), no new chain starts for [coolDown];
/// invalidations in that time raise a pending target, and when the cool-down ends one deferred chain
/// starts if that target is still ahead of [knownVersion]. A storm of rising announcements therefore
/// costs at most one chain per [coolDown]. A chain that ended up to date leaves no cool-down, so the
/// next publish is fetched at once.
final class AutoFetcher {
  /// Creates the auto-fetcher. [fetchForRealtime] is the fetch path with interval zero, the shared
  /// throttle and `REALTIME/<attempt>`; [onUpdate] and [onError] reach the listeners. [delay] replaces
  /// the wait before each attempt; without it the wait is a timer that close cancels.
  AutoFetcher({
    required Future<FetchResult> Function(int attempt) fetchForRealtime,
    required TemplateRecords Function() templates,
    required double Function() random,
    required DateTime Function() clock,
    required Future<void> closed,
    required void Function(RemoteConfigUpdate update) onUpdate,
    required void Function(FirebaseRemoteConfigException error) onError,
    Future<void> Function(Duration duration)? delay,
  }) : _fetchForRealtime = fetchForRealtime,
       _templates = templates,
       _random = random,
       _delay = delay,
       _clock = clock,
       _closed = closed,
       _onUpdate = onUpdate,
       _onError = onError {
    unawaited(_closed.then((_) => _isClosed = true));
  }

  /// Attempts in one chain.
  static const int maxAttempts = 3;

  /// The longest random wait before an attempt.
  static const Duration maxJitter = Duration(seconds: 3);

  /// After a chain that did not end up to date, the time before another chain may start.
  static const Duration coolDown = Duration(seconds: 60);

  final Future<FetchResult> Function(int attempt) _fetchForRealtime;
  final TemplateRecords Function() _templates;
  final double Function() _random;
  final Future<void> Function(Duration duration)? _delay;
  final DateTime Function() _clock;
  final Future<void> _closed;
  final void Function(RemoteConfigUpdate update) _onUpdate;
  final void Function(FirebaseRemoteConfigException error) _onError;

  bool _isClosed = false;
  int? _target;
  bool _running = false;
  bool _deferred = false;
  DateTime? _coolUntil;

  /// An invalidation announced [version]: starts a chain, raises the target of the running or deferred
  /// one, or (during the cool-down) schedules the deferred chain.
  void invalidate(int version) {
    if (_isClosed) {
      return;
    }
    final int? target = _target;
    if (target == null || version > target) {
      _target = version;
    }
    if (_running || _deferred) {
      return;
    }
    final DateTime? coolUntil = _coolUntil;
    final DateTime now = _clock();
    if (coolUntil != null && now.isBefore(coolUntil)) {
      // Measured on the injected clock; a clock that stepped back never stretches the wait past
      // [coolDown].
      final Duration left = coolUntil.difference(now);
      _deferred = true;
      unawaited(_runDeferred(left > coolDown ? coolDown : left));
      return;
    }
    _start();
  }

  void _start() {
    _running = true;
    unawaited(_run());
  }

  Future<void> _runDeferred(Duration wait) async {
    // A timer, not the injected jitter delay: a delay that returns at once must not end the cool-down.
    await _sleep(wait);
    _deferred = false;
    final int? target = _target;
    if (_isClosed || target == null || target <= knownVersion(_templates())) {
      _target = null;
      return;
    }
    _start();
  }

  Future<void> _run() async {
    bool upToDate = false;
    try {
      upToDate = await _chain();
    } finally {
      _running = false;
      _target = null;
      _coolUntil = upToDate ? null : _clock().add(coolDown);
    }
  }

  /// Runs the attempts; returns true when the chain ended up to date.
  Future<bool> _chain() async {
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      await _jitter();
      if (_isClosed) {
        return false;
      }
      try {
        await _fetchForRealtime(attempt);
      } on FirebaseRemoteConfigException catch (error) {
        _report(error);
        return false;
      }
      if (_isClosed) {
        return false;
      }
      final TemplateRecords records = _templates();
      // Up to date only at the target: `unchanged` below it is a lagging answer, not the new template.
      if (knownVersion(records) >= _target!) {
        // With no fetched record nothing was fetched to compare, so no key changed.
        final Set<String> keys = records.fetched == null
            ? const <String>{}
            : updatedKeys(records.active, records.fetched);
        if (keys.isNotEmpty) {
          _onUpdate(RemoteConfigUpdate(keys));
        }
        return true;
      }
    }
    _report(null);
    return false;
  }

  /// The random wait before an attempt; it ends early when the instance closes.
  Future<void> _jitter() {
    final Duration wait = maxJitter * _random();
    final Future<void> Function(Duration duration)? delay = _delay;
    if (delay == null) {
      return _sleep(wait);
    }
    return Future.any(<Future<void>>[delay(wait), _closed]);
  }

  /// Waits [wait] on a timer, or until the instance closes; close cancels the timer.
  Future<void> _sleep(Duration wait) async {
    final Completer<void> elapsed = Completer<void>();
    final Timer timer = Timer(wait, elapsed.complete);
    await Future.any(<Future<void>>[elapsed.future, _closed]);
    timer.cancel();
  }

  void _report(FirebaseRemoteConfigException? cause) {
    if (_isClosed || cause?.code == 'remote-config-closed') {
      return;
    }
    _onError(
      FirebaseRemoteConfigException(
        code: 'update-not-fetched',
        message: cause == null
            ? 'The fetches after a realtime update did not get the new template.'
            : 'The fetch after a realtime update failed (${cause.code}).',
        cause: cause,
      ),
    );
  }
}
