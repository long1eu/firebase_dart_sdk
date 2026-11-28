import 'package:firebase_app_check_dart/src/clocks.dart';
import 'package:meta/meta.dart';

/// The margin before its expiry at which a token stops being usable, for lifetimes of 10 minutes
/// or more.
const Duration _usableMargin = Duration(minutes: 5);

/// An App Check token and the time it stops being valid.
///
/// Whoever holds [token] can use it until [expireTime]: do not log it. [toString] does not print
/// it.
final class AppCheckToken {
  /// A token with its expiry. A custom provider returns one from its callback.
  const AppCheckToken({required this.token, required this.expireTime});

  /// The token: the value of the `X-Firebase-AppCheck` header.
  final String token;

  /// When the token stops being valid. The package gives it in UTC.
  final DateTime expireTime;

  @override
  String toString() =>
      'AppCheckToken(<redacted>, expireTime: '
      '${expireTime.toUtc().toIso8601String()})';
}

/// A token as the package holds it: its text, when it was issued on both clocks, and its lifetime.
@internal
final class SessionToken {
  /// A token issued at [issuedWall] (wall clock) and [issuedMono] (monotonic) that lives [ttl].
  const SessionToken({
    required this.token,
    required this.issuedWall,
    required this.issuedMono,
    required this.ttl,
  });

  /// The token text.
  final String token;

  /// The wall clock's time at issue, in UTC.
  final DateTime issuedWall;

  /// The monotonic source's reading at issue.
  final Duration issuedMono;

  /// The lifetime, counted from the issue.
  final Duration ttl;

  /// The token's age: the larger of the two elapsed times since its issue, so a wall clock set
  /// back and a monotonic source that stopped both err towards refreshing early.
  Duration age(Clocks c) {
    final Duration wall = c.wallNow().difference(issuedWall);
    final Duration mono = c.monoNow() - issuedMono;
    return wall > mono ? wall : mono;
  }

  /// True while the age is under the lifetime.
  bool isUnexpired(Clocks c) => age(c) < ttl;

  /// True while the age is under the lifetime minus the smaller of 5 minutes and half the
  /// lifetime: what a result without an error must be.
  bool isUsable(Clocks c) {
    final Duration half = ttl ~/ 2;
    final Duration margin = half < _usableMargin ? half : _usableMargin;
    return age(c) < ttl - margin;
  }

  /// The wall-clock issue time plus the lifetime, in UTC.
  DateTime get expireTime => issuedWall.toUtc().add(ttl);

  /// The public form of this token.
  AppCheckToken toPublic() =>
      AppCheckToken(token: token, expireTime: expireTime);

  @override
  String toString() =>
      'SessionToken(<redacted>, issued: '
      '${issuedWall.toUtc().toIso8601String()}, ttl: ${ttl.inSeconds} s)';
}

/// Where a replacement of the cached session token came from.
@internal
enum TokenOrigin {
  /// An exchange of this instance.
  exchange,

  /// The first load of the stored record.
  load,

  /// A stored record that another instance wrote and that was issued later.
  adopt,
}

/// One replacement of the cached session token.
@internal
final class TokenEvent {
  /// The cached token became [token], from [origin]; listeners are told when [announce] is true.
  const TokenEvent(this.token, this.origin, {required this.announce});

  /// The new cached token.
  final SessionToken token;

  /// Where it came from.
  final TokenOrigin origin;

  /// False for a loaded record that is unexpired but no longer usable: it is about to be replaced,
  /// so `onTokenChanged` and the seam's stream skip it.
  final bool announce;

  @override
  String toString() =>
      'TokenEvent($token, ${origin.name}, announce: $announce)';
}
