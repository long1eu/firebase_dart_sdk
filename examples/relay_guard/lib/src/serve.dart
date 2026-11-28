import 'dart:async';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

/// Serves [handler] on [address]:[port] like `shelf_io.serve`, with two protections a relay needs:
///
/// * every connection is destroyed [connectionDeadline] after it was accepted. A client that sends the headers
///   and never the body would otherwise hold the connection forever: `dart:io` reads the whole body before it
///   writes any answer, even a refusal, and a handler cannot close the connection;
/// * idle keep-alive connections close after [idleTimeout].
///
/// A relay's requests are short, so the deadline only ends connections that stall. On Cloud Run also set the
/// request timeout of the service (`--timeout`) to about 30 seconds, and choose `--concurrency` and
/// `--max-instances` so that a flood cannot scale the service without bound.
Future<HttpServer> serveGuarded(
  Handler handler,
  Object address,
  int port, {
  Duration connectionDeadline = const Duration(seconds: 20),
  Duration idleTimeout = const Duration(seconds: 10),
}) async {
  final ServerSocket socket = await ServerSocket.bind(address, port);
  final HttpServer server = HttpServer.listenOn(
    _DeadlineServerSocket(socket, connectionDeadline),
  )..idleTimeout = idleTimeout;
  shelf_io.serveRequests(server, handler);
  return server;
}

/// A server socket whose connections are destroyed [_deadline] after they were accepted.
final class _DeadlineServerSocket extends Stream<Socket>
    implements ServerSocket {
  _DeadlineServerSocket(this._inner, this._deadline);

  final ServerSocket _inner;
  final Duration _deadline;

  @override
  StreamSubscription<Socket> listen(
    void Function(Socket socket)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _inner
      .map((Socket socket) {
        final Timer timer = Timer(_deadline, socket.destroy);
        socket.done.whenComplete(timer.cancel).ignore();
        return socket;
      })
      .listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );

  @override
  InternetAddress get address => _inner.address;

  @override
  int get port => _inner.port;

  @override
  Future<ServerSocket> close() async {
    await _inner.close();
    return this;
  }
}
