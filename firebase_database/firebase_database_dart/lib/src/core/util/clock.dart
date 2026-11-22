/// Clock injection and server time. JS: `core/Repo.ts` (`repoServerTime`, `.info/serverTimeOffset`);
/// Android: `core/utilities/Clock.java`, `DefaultClock.java`, `OffsetClock.java`.
library;

/// The time source of the core; tests inject a fake one. Returns the local wall time.
typedef Clock = DateTime Function();

/// Holds the offset between the server's clock and the local [clock], as reported at each
/// handshake through `.info/serverTimeOffset`, and gives the estimated server time.
final class ServerClock {
  /// Creates a server clock over [clock] with an initial offset of zero.
  ServerClock(this.clock);

  /// The local clock.
  final Clock clock;

  /// The last server time offset in milliseconds (server minus local).
  /// Android `OffsetClock.offset`.
  // The getter and setter pair is the skeleton's signature.
  // ignore: unnecessary_getters_setters
  int get offsetMillis => _offsetMillis;
  int _offsetMillis = 0;

  /// Sets the server time offset in milliseconds (Android `OffsetClock.setOffset`).
  set offsetMillis(int value) => _offsetMillis = value;

  /// The estimated server time in milliseconds since the epoch: local time plus the offset.
  /// Android `OffsetClock.millis`; JS `repoServerTime`.
  int nowMillis() => clock().millisecondsSinceEpoch + _offsetMillis;
}
