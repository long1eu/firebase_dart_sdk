// Tests of the test-only ChaosProxy, against a local echo server.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

import '../../util/chaos_proxy.dart';

void main() {
  late ServerSocket echo;
  late ChaosProxy proxy;
  final List<Socket> sockets = <Socket>[];

  setUp(() async {
    echo = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    echo.listen((Socket socket) {
      unawaited(socket.done.catchError((Object _) {}));
      socket.listen(socket.add, onError: (Object _) {}, onDone: socket.destroy);
    });
    proxy = await ChaosProxy.start(echo.address.address, echo.port);
  });

  tearDown(() async {
    for (final Socket socket in sockets) {
      socket.destroy();
    }
    sockets.clear();
    await proxy.close();
    await echo.close();
  });

  /// Connects through the proxy. `received` collects what comes back; `closed` completes when the connection ends.
  Future<({Socket socket, StringBuffer received, Future<void> closed})>
  connect() async {
    final Socket socket = await Socket.connect(proxy.host, proxy.port);
    sockets.add(socket);
    unawaited(socket.done.catchError((Object _) {}));
    final StringBuffer received = StringBuffer();
    final Completer<void> closed = Completer<void>();
    socket.listen(
      (Uint8List data) => received.write(utf8.decode(data)),
      onError: (Object _) {},
      onDone: closed.complete,
    );
    return (socket: socket, received: received, closed: closed.future);
  }

  Future<void> settle([int milliseconds = 100]) =>
      Future<void>.delayed(Duration(milliseconds: milliseconds));

  /// Waits until [condition] holds, checking every few milliseconds, for at
  /// most 10 seconds: for what must happen (bytes that arrive), so that a
  /// loaded machine only makes the test slower. What must not happen is
  /// still checked after a fixed [settle].
  Future<void> until(bool Function() condition) async {
    final Stopwatch watch = Stopwatch()..start();
    while (!condition() && watch.elapsed < const Duration(seconds: 10)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  test('forwards in both directions and counts', () async {
    final connection = await connect();
    connection.socket.add(utf8.encode('hello'));
    await until(
      () =>
          connection.received.toString() == 'hello' &&
          proxy.bytesUp == 5 &&
          proxy.bytesDown == 5,
    );
    expect(connection.received.toString(), 'hello');
    expect(proxy.bytesUp, 5);
    expect(proxy.bytesDown, 5);
    expect(proxy.acceptedConnections, 1);
    expect(proxy.openConnections, 1);
  });

  test('cut drops the open connections, new ones work', () async {
    final first = await connect();
    await settle(50);
    proxy.cut();
    await first.closed.timeout(const Duration(seconds: 2));
    expect(proxy.cuts, 1);
    expect(proxy.openConnections, 0);

    final second = await connect();
    second.socket.add(utf8.encode('again'));
    await settle();
    expect(second.received.toString(), 'again');
  });

  test('disconnect refuses connections until restore', () async {
    proxy.disconnect();
    final refused = await connect();
    await refused.closed.timeout(const Duration(seconds: 2));
    proxy.restore();
    final accepted = await connect();
    accepted.socket.add(utf8.encode('x'));
    await settle();
    expect(accepted.received.toString(), 'x');
  });

  test('stall keeps the bytes and forwards them in order on resume', () async {
    final connection = await connect();
    proxy.mode = ChaosMode.stall;
    connection.socket.add(utf8.encode('one'));
    await settle(50);
    connection.socket.add(utf8.encode('two'));
    await settle();
    expect(connection.received.toString(), isEmpty);
    proxy.mode = ChaosMode.forward;
    await settle();
    expect(connection.received.toString(), 'onetwo');
  });

  test('stallUp holds the requests, stallDown the answers', () async {
    final connection = await connect();
    proxy.mode = ChaosMode.stallUp;
    connection.socket.add(utf8.encode('up'));
    await settle();
    expect(proxy.bytesDown, 0, reason: 'the echo server got nothing');
    proxy.mode = ChaosMode.forward;
    await settle();
    expect(connection.received.toString(), 'up');

    proxy.mode = ChaosMode.stallDown;
    connection.socket.add(utf8.encode('down'));
    await settle();
    expect(proxy.bytesDown, 6, reason: 'the echo server answered');
    expect(connection.received.toString(), 'up');
    proxy.mode = ChaosMode.forward;
    await settle();
    expect(connection.received.toString(), 'updown');
  });

  test(
    'a black hole drops the bytes and the connection dies on restore',
    () async {
      final connection = await connect();
      proxy.mode = ChaosMode.blackHole;
      connection.socket.add(utf8.encode('lost'));
      await settle();
      expect(connection.received.toString(), isEmpty);
      expect(proxy.openConnections, 1);
      proxy.restore();
      await connection.closed.timeout(const Duration(seconds: 2));
      expect(connection.received.toString(), isEmpty);
    },
  );

  test(
      'a black hole followed by a stall cuts the connection that lost bytes: '
      'it never resumes with a hole in its byte stream', () async {
    final connection = await connect();
    proxy.mode = ChaosMode.blackHole;
    connection.socket.add(utf8.encode('lost'));
    await settle();
    // The soak test starts a stall while a black hole is still on, and resumes later.
    proxy.mode = ChaosMode.stall;
    await connection.closed.timeout(const Duration(seconds: 2));
    expect(proxy.openConnections, 0);
    proxy.mode = ChaosMode.forward;
    await settle();
    expect(connection.received.toString(), isEmpty);
  });

  test('a connection that lost nothing in a black hole stays open', () async {
    final connection = await connect();
    proxy.mode = ChaosMode.blackHole;
    await settle();
    proxy.mode = ChaosMode.stall;
    connection.socket.add(utf8.encode('kept'));
    await settle();
    proxy.mode = ChaosMode.forward;
    await settle();
    expect(connection.received.toString(), 'kept');
    expect(proxy.openConnections, 1);
  });

  test('delay adds latency and keeps the order', () async {
    final connection = await connect();
    proxy.delay = const Duration(milliseconds: 150);
    final Stopwatch watch = Stopwatch()..start();
    connection.socket.add(utf8.encode('a'));
    await settle(20);
    connection.socket.add(utf8.encode('b'));
    await settle(100);
    expect(connection.received.toString(), isEmpty);
    while (connection.received.length < 2 &&
        watch.elapsed < const Duration(seconds: 3)) {
      await settle(20);
    }
    expect(connection.received.toString(), 'ab');
    // Up and down are delayed.
    expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(300));
  });

  test(
    'cutAfter and cutOnNext cut mid-stream without forwarding the chunk',
    () async {
      final first = await connect();
      final Future<void> cut = proxy.cutAfter(ChaosDirection.up, 4);
      first.socket.add(utf8.encode('1234'));
      await settle();
      expect(first.received.toString(), '1234');
      first.socket.add(utf8.encode('5'));
      await cut.timeout(const Duration(seconds: 2));
      await first.closed.timeout(const Duration(seconds: 2));
      expect(first.received.toString(), '1234');

      final second = await connect();
      final Future<void> onResponse = proxy.cutOnNext(
        ChaosDirection.down,
        minBytes: 3,
      );
      second.socket.add(utf8.encode('ab'));
      await settle();
      expect(second.received.toString(), 'ab', reason: 'too small to cut');
      second.socket.add(utf8.encode('abc'));
      await onResponse.timeout(const Duration(seconds: 2));
      await second.closed.timeout(const Duration(seconds: 2));
      expect(
        second.received.toString(),
        'ab',
        reason: 'the echo server got the request, the answer was lost',
      );
      expect(proxy.cuts, 2);
    },
  );

  test(
    'what was received is delivered when the sender closes right after',
    () async {
      // A server that answers and closes, like an HTTP/1.1 response with `Connection: close`.
      final ServerSocket server = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      server.listen((Socket socket) {
        unawaited(socket.done.catchError((Object _) {}));
        socket.listen((Uint8List data) async {
          socket.add(utf8.encode('answer to ${utf8.decode(data)}'));
          await socket.flush();
          await socket.close();
        }, onError: (Object _) {});
      });
      final ChaosProxy closing = await ChaosProxy.start(
        server.address.address,
        server.port,
      );
      addTearDown(() async {
        await closing.close();
        await server.close();
      });

      Future<String> request() async {
        final Socket socket = await Socket.connect(closing.host, closing.port);
        sockets.add(socket);
        unawaited(socket.done.catchError((Object _) {}));
        final StringBuffer received = StringBuffer();
        final Completer<void> closed = Completer<void>();
        socket.listen(
          (Uint8List data) => received.write(utf8.decode(data)),
          onError: (Object _) {},
          onDone: closed.complete,
        );
        socket.add(utf8.encode('q'));
        await closed.future.timeout(const Duration(seconds: 3));
        return received.toString();
      }

      expect(await request(), 'answer to q');
      closing.delay = const Duration(milliseconds: 100);
      expect(await request(), 'answer to q', reason: 'with latency');
      closing.delay = Duration.zero;
      closing.mode = ChaosMode.stallDown;
      final Future<String> stalled = request();
      await settle(200);
      closing.mode = ChaosMode.forward;
      expect(await stalled, 'answer to q', reason: 'after a stall');
      expect(closing.cuts, 0);
    },
  );
}
