import 'package:meta/meta.dart';

/// The two time sources of an instance.
///
/// Waits (gate windows, deadlines, timers, the forced floor) read [monoNow] only, so a wall clock
/// that is moved changes none of them. A token's age reads both, and a date (an expiry) comes from
/// [wallNow].
@internal
final class Clocks {
  /// Clocks reading [wall] (the wall clock) and [elapsed] (the time since an arbitrary start, which
  /// never goes back).
  Clocks({
    required DateTime Function() wall,
    required Duration Function() elapsed,
  }) : _wall = wall,
       _elapsed = elapsed;

  final DateTime Function() _wall;
  final Duration Function() _elapsed;

  /// The wall clock's time, in UTC.
  DateTime wallNow() => _wall().toUtc();

  /// The monotonic source's reading.
  Duration monoNow() => _elapsed();
}
