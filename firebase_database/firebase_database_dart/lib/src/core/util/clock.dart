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
  int get offsetMillis => throw UnimplementedError();

  /// Sets the server time offset in milliseconds.
  set offsetMillis(int value) => throw UnimplementedError();

  /// The estimated server time in milliseconds since the epoch: local time plus the offset.
  int nowMillis() => throw UnimplementedError();
}
