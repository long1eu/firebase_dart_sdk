// Fakes shared by the unit tests: a clock, timers, and ID tokens in the shape of the Auth emulator's.

import 'dart:async';
import 'dart:convert';

class FakeClock {
  FakeClock([DateTime? start]) : now = start ?? DateTime.utc(2026, 1, 1, 12);

  DateTime now;

  DateTime call() => now;

  void advance(Duration duration) => now = now.add(duration);
}

class FakeTimer implements Timer {
  FakeTimer(this.delay, this._callback);

  final Duration delay;
  final void Function() _callback;
  bool cancelled = false;
  bool fired = false;

  @override
  void cancel() => cancelled = true;

  @override
  bool get isActive => !cancelled && !fired;

  @override
  int get tick => fired ? 1 : 0;

  void fire() {
    fired = true;
    _callback();
  }
}

class FakeTimers {
  final List<FakeTimer> all = <FakeTimer>[];

  Timer create(Duration delay, void Function() callback) {
    final FakeTimer timer = FakeTimer(delay, callback);
    all.add(timer);
    return timer;
  }

  List<FakeTimer> get active => all.where((FakeTimer t) => t.isActive).toList();
}

String _encode(Object json) =>
    base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');

/// An unsigned ID token like the ones the Auth emulator returns.
String idToken(
  String uid, {
  required DateTime expires,
  String provider = 'password',
  String? email,
  String tag = '',
}) {
  return '${_encode(<String, Object?>{'alg': 'none', 'typ': 'JWT'})}.'
      '${_encode(<String, Object?>{
        'user_id': uid,
        'sub': uid,
        'email': ?email,
        'exp': expires.millisecondsSinceEpoch ~/ 1000,
        'iat': expires.millisecondsSinceEpoch ~/ 1000 - 3600,
        'firebase': <String, Object?>{'sign_in_provider': provider},
        if (tag.isNotEmpty) 'tag': tag,
      })}.';
}

/// Lets pending microtasks and zero-delay futures run.
Future<void> pump() => Future<void>.delayed(Duration.zero);
