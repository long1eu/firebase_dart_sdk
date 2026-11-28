import 'package:_firebase_transport_dart/_firebase_transport_dart.dart';

/// Where a channel connects: the one source of host, port and TLS for both the channel and the
/// token check.
final class GrpcTarget {
  /// A target at [host] and [port], over TLS when [secure].
  ///
  /// Throws an [ArgumentError] for an empty host or a port outside 1 to 65535. Not const: it
  /// validates.
  GrpcTarget({required this.host, required this.port, required this.secure}) {
    if (host.isEmpty) {
      throw ArgumentError('GrpcTarget: the host is empty');
    }
    if (port < 1 || port > 65535) {
      throw ArgumentError('GrpcTarget: the port must be 1 to 65535');
    }
  }

  /// The emulator at [emulator], over plaintext.
  GrpcTarget.emulator(EmulatorHost emulator)
    : this(host: emulator.host, port: emulator.port, secure: false);

  /// The host name or IP address; an IPv6 address is without brackets.
  final String host;

  /// The port, 1 to 65535.
  final int port;

  /// Whether the channel uses TLS.
  final bool secure;

  /// `Uri(scheme: secure ? 'https' : 'http', host: host, port: port)`: what
  /// `TokenSource.tokensFor` is called with, and what the token headers of a call are checked
  /// against.
  Uri get origin =>
      Uri(scheme: secure ? 'https' : 'http', host: host, port: port);

  /// `GrpcTarget(<host>:<port>, secure: <secure>)`.
  @override
  String toString() => 'GrpcTarget($host:$port, secure: $secure)';
}
