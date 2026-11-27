// Owner K. ReconnectBackoff (rtdb_protocol.md 8.2, threat model T13, test plan B-8.2a to B-8.2d).
import 'package:firebase_database_dart/src/realtime/reconnect_backoff.dart';
import 'package:test/test.dart';

/// A clock the test moves by hand.
final class _Clock {
  DateTime now = DateTime.utc(2026, 11, 22);

  DateTime call() => now;

  void advance(Duration by) {
    now = now.add(by);
  }
}

ReconnectBackoff _backoff(_Clock clock, double Function() random) =>
    ReconnectBackoff(
      min: const Duration(seconds: 1),
      max: const Duration(seconds: 30),
      multiplier: 1.3,
      resetAfter: const Duration(seconds: 30),
      now: clock.call,
      random: random,
    );

/// The delays of [count] attempts that each failed at once.
List<Duration> _delays(ReconnectBackoff backoff, _Clock clock, int count) =>
    <Duration>[
      for (int i = 0; i < count; i++)
        backoff.nextDelay(attemptStartedAt: clock.now),
    ];

const Duration _ms = Duration(milliseconds: 1);

void main() {
  group('bounds and jitter (B-8.2a)', () {
    test('random 1 gives the bounds 1, 1.3, 1.69 s ... capped at 30 s', () {
      final _Clock clock = _Clock();
      final ReconnectBackoff backoff = _backoff(clock, () => 1);
      final List<Duration> delays = _delays(backoff, clock, 16);
      expect(delays.sublist(0, 5), <Duration>[
        _ms * 1000,
        _ms * 1300,
        _ms * 1690,
        _ms * 2197,
        const Duration(microseconds: 2856100),
      ]);
      expect(delays[12], const Duration(microseconds: 23298085));
      expect(delays[13], const Duration(seconds: 30));
      expect(delays[15], const Duration(seconds: 30));
    });

    test('random 0 gives no delay and still grows the bound', () {
      final _Clock clock = _Clock();
      double value = 0;
      final ReconnectBackoff backoff = _backoff(clock, () => value);
      expect(_delays(backoff, clock, 3), <Duration>[
        Duration.zero,
        Duration.zero,
        Duration.zero,
      ]);
      value = 1;
      expect(backoff.nextDelay(attemptStartedAt: clock.now), _ms * 2197);
    });

    test('random 0.5 gives half of each bound', () {
      final _Clock clock = _Clock();
      final ReconnectBackoff backoff = _backoff(clock, () => 0.5);
      expect(_delays(backoff, clock, 3), <Duration>[
        _ms * 500,
        _ms * 650,
        _ms * 845,
      ]);
    });

    test('the time spent in the failed attempt is subtracted', () {
      final _Clock clock = _Clock();
      final ReconnectBackoff backoff = _backoff(clock, () => 0.5);
      final DateTime started = clock.now;
      clock.advance(_ms * 400);
      expect(backoff.nextDelay(attemptStartedAt: started), _ms * 300);
    });

    test('an attempt longer than the bound reconnects at once', () {
      final _Clock clock = _Clock();
      final ReconnectBackoff backoff = _backoff(clock, () => 1);
      final DateTime started = clock.now;
      clock.advance(const Duration(seconds: 30));
      expect(backoff.nextDelay(attemptStartedAt: started), Duration.zero);
      expect(backoff.nextDelay(attemptStartedAt: clock.now), _ms * 1300);
    });

    test('an attempt start in the future counts as no time spent', () {
      final _Clock clock = _Clock();
      final ReconnectBackoff backoff = _backoff(clock, () => 1);
      expect(
        backoff.nextDelay(
          attemptStartedAt: clock.now.add(const Duration(hours: 1)),
        ),
        _ms * 1000,
      );
    });

    test('a random value outside [0, 1] is clamped', () {
      final _Clock clock = _Clock();
      double value = 2;
      final ReconnectBackoff backoff = _backoff(clock, () => value);
      expect(backoff.nextDelay(attemptStartedAt: clock.now), _ms * 1000);
      value = -1;
      expect(backoff.nextDelay(attemptStartedAt: clock.now), Duration.zero);
    });
  });

  group('reset after an established connection (B-8.2b)', () {
    test('a connection established longer than 30 s resets the bound', () {
      final _Clock clock = _Clock();
      final ReconnectBackoff backoff = _backoff(clock, () => 1);
      _delays(backoff, clock, 5);
      backoff.markEstablished();
      clock.advance(const Duration(seconds: 31));
      expect(backoff.nextDelay(attemptStartedAt: clock.now), _ms * 1000);
    });

    test('exactly 30 s or less does not reset', () {
      for (final Duration age in <Duration>[
        const Duration(seconds: 30),
        const Duration(seconds: 29),
      ]) {
        final _Clock clock = _Clock();
        final ReconnectBackoff backoff = _backoff(clock, () => 1);
        _delays(backoff, clock, 2);
        backoff.markEstablished();
        clock.advance(age);
        expect(
          backoff.nextDelay(attemptStartedAt: clock.now),
          _ms * 1690,
          reason: '$age',
        );
      }
    });

    test('the established mark is used once', () {
      final _Clock clock = _Clock();
      final ReconnectBackoff backoff = _backoff(clock, () => 1);
      _delays(backoff, clock, 2);
      backoff.markEstablished();
      clock.advance(const Duration(seconds: 31));
      backoff.nextDelay(attemptStartedAt: clock.now);
      clock.advance(const Duration(seconds: 31));
      expect(backoff.nextDelay(attemptStartedAt: clock.now), _ms * 1300);
    });

    test('a connection that was never established does not reset (T13)', () {
      final _Clock clock = _Clock();
      final ReconnectBackoff backoff = _backoff(clock, () => 1);
      _delays(backoff, clock, 3);
      clock.advance(const Duration(minutes: 5));
      expect(backoff.nextDelay(attemptStartedAt: clock.now), _ms * 2197);
    });
  });

  group('reset and setToMax (B-8.2c, 8.3)', () {
    test('reset goes back to the first bound', () {
      final _Clock clock = _Clock();
      final ReconnectBackoff backoff = _backoff(clock, () => 1);
      _delays(backoff, clock, 6);
      backoff.reset();
      expect(_delays(backoff, clock, 2), <Duration>[_ms * 1000, _ms * 1300]);
    });

    test('setToMax gives the cap at once and then stays capped', () {
      final _Clock clock = _Clock();
      final ReconnectBackoff backoff = _backoff(clock, () => 1);
      backoff.setToMax();
      expect(_delays(backoff, clock, 2), <Duration>[
        const Duration(seconds: 30),
        const Duration(seconds: 30),
      ]);
    });

    test('setToMax wins over an established connection older than 30 s', () {
      final _Clock clock = _Clock();
      final ReconnectBackoff backoff = _backoff(clock, () => 1);
      backoff.markEstablished();
      clock.advance(const Duration(seconds: 40));
      backoff.setToMax();
      expect(
        backoff.nextDelay(attemptStartedAt: clock.now),
        const Duration(seconds: 30),
      );
    });
  });
}
