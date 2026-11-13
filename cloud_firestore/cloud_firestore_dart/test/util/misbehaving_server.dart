// A test-only server that accepts connections and then lets the client down
// in one of several ways, and counts how often the client came back.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'self_signed_certificate.dart';

/// What a [MisbehavingServer] does with a connection.
enum Misbehavior {
  /// Accepts the connection and closes it at once (a load balancer without a
  /// backend, a captive portal).
  closeAtOnce,

  /// Completes the TLS handshake and then closes the connection, without
  /// answering, as soon as the client sends its first bytes over TLS (a
  /// TLS-terminating middlebox without a backend).
  closeAfterTlsHandshake,

  /// Reads the HTTP/2 preface of the client and then closes the connection
  /// without ever sending a frame.
  closeAfterPreface,

  /// Sends its SETTINGS and a GOAWAY right away and keeps the connection open.
  goAwayAtOnce,
}

/// See [Misbehavior]. The connections are counted in [connections], with the
/// time at which each one was accepted in [acceptedAt].
class MisbehavingServer {
  MisbehavingServer._(this.misbehavior, this._server, this._stopwatch);

  /// Starts a server on a free loopback port. The TLS variant needs a
  /// [certificate] (see [SelfSignedCertificate]), which the client has to
  /// accept.
  static Future<MisbehavingServer> start(
    Misbehavior misbehavior, {
    SelfSignedCertificate? certificate,
  }) async {
    final Stopwatch stopwatch = Stopwatch()..start();
    final MisbehavingServer server;
    if (misbehavior == Misbehavior.closeAfterTlsHandshake) {
      if (certificate == null) {
        throw ArgumentError('The TLS variant needs a certificate');
      }
      final SecurityContext context = SecurityContext()
        ..useCertificateChain(certificate.certificatePath)
        ..usePrivateKey(certificate.keyPath);
      final SecureServerSocket socket = await SecureServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
        context,
      );
      server = MisbehavingServer._(misbehavior, socket, stopwatch);
      socket.listen(server._accept, onError: (Object _) {});
    } else {
      final ServerSocket socket = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      server = MisbehavingServer._(misbehavior, socket, stopwatch);
      socket.listen(server._accept);
    }
    return server;
  }

  final Misbehavior misbehavior;
  final Stream<Socket> _server;
  final Stopwatch _stopwatch;
  final Set<Socket> _open = <Socket>{};

  /// When each connection was accepted, since the server started.
  final List<Duration> acceptedAt = <Duration>[];

  int get connections => acceptedAt.length;

  String get host => '127.0.0.1';

  int get port => switch (_server) {
    final ServerSocket socket => socket.port,
    final SecureServerSocket socket => socket.port,
    _ => throw StateError('not a server socket'),
  };

  /// The longest time without a new connection between the first and the last
  /// one.
  Duration get longestGap {
    Duration longest = Duration.zero;
    for (int i = 1; i < acceptedAt.length; i++) {
      final Duration gap = acceptedAt[i] - acceptedAt[i - 1];
      if (gap > longest) {
        longest = gap;
      }
    }
    return longest;
  }

  void _accept(Socket socket) {
    acceptedAt.add(_stopwatch.elapsed);
    switch (misbehavior) {
      case Misbehavior.closeAtOnce:
        socket.destroy();
      case Misbehavior.closeAfterTlsHandshake:
        // The handshake is complete on this side. The connection goes away
        // when the client sends its first bytes over TLS (the HTTP/2
        // preface): the client has then completed the handshake too, however
        // slow it is. A timer here raced the client's handshake on a loaded
        // machine.
        _open.add(socket);
        socket.listen(
          (Uint8List _) {
            _open.remove(socket);
            socket.destroy();
          },
          onError: (Object _) {},
          onDone: () => _open.remove(socket),
        );
      case Misbehavior.closeAfterPreface:
        _open.add(socket);
        int received = 0;
        socket.listen(
          (Uint8List data) {
            received += data.length;
            // The preface is 24 bytes, followed by the SETTINGS of the client.
            if (received >= 24) {
              _open.remove(socket);
              socket.destroy();
            }
          },
          onError: (Object _) {},
          onDone: () => _open.remove(socket),
        );
      case Misbehavior.goAwayAtOnce:
        _open.add(socket);
        socket
          // In one write, so that the client reads both frames together and
          // handles the GOAWAY before it can start a call on the connection.
          // Two writes could reach it apart on a loaded machine; the client
          // would then use the connection in between, which is another case.
          ..add(<int>[
            // An empty SETTINGS frame.
            0, 0, 0, 4, 0, 0, 0, 0, 0,
            // GOAWAY: last stream id 0, NO_ERROR.
            0, 0, 8, 7, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
          ])
          ..listen(
            (Uint8List _) {},
            onError: (Object _) {},
            onDone: () => _open.remove(socket),
          );
        unawaited(socket.flush().catchError((Object _) {}));
    }
  }

  Future<void> close() async {
    for (final Socket socket in _open.toList()) {
      socket.destroy();
    }
    _open.clear();
    switch (_server) {
      case final ServerSocket socket:
        await socket.close();
      case final SecureServerSocket socket:
        await socket.close();
    }
  }
}
