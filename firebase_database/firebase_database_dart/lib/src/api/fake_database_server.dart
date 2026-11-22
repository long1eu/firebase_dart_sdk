/// An in-memory server for tests, scripted by the test. JS: none; Android: none (the JS and Android tests
/// use a live backend). Built over `lib/src/testing/fake_server_actions.dart`.
library;

/// A server for tests that sits at the connection seam and answers only what the test tells it to.
///
/// Pass it to `databaseWithFakeServer`. Requests are recorded in [requests]; listens, writes and gets wait
/// until the test answers them. Drive time with `fakeAsync`.
///
/// ```dart
/// fakeAsync((FakeAsync async) {
///   final FakeDatabaseServer server = FakeDatabaseServer();
///   final FirebaseDatabase db = databaseWithFakeServer(app, server);
///   db.ref('a').onValue.listen((DatabaseEvent e) => print(e.snapshot.value));
///   async.elapse(Duration.zero);
///   server.answerListen('a', 1); // prints 1
///   async.elapse(Duration.zero);
/// });
/// ```
final class FakeDatabaseServer {
  /// Creates a server that accepts connections.
  FakeDatabaseServer();

  /// Whether a connection attempt succeeds. Default true. Set it to false, then call [dropConnection], to
  /// keep the client offline.
  bool acceptConnections = true;

  /// The number of connection attempts the client has made.
  int get connectionAttempts => throw UnimplementedError();

  /// The requests received, oldest first, as `'<action> <path>'`: `q` listen, `n` unlisten, `g` get, `p`
  /// put, `m` merge, `o` onDisconnect put, and so on, for example `'q /a'`.
  List<String> get requests => throw UnimplementedError();

  /// Answers the open listen at [path] with [value] (JSON, `.priority`/`.value` allowed), completing it.
  void answerListen(String path, Object? value) => throw UnimplementedError();

  /// Refuses the open listen at [path] with the wire [status], for example `'permission_denied'`.
  void failListen(String path, String status) => throw UnimplementedError();

  /// Sends [value] as new data at [path], as another client's write would.
  void push(String path, Object? value) => throw UnimplementedError();

  /// Cancels the active listen at [path] with the wire [status], as a rules change would.
  void cancelListen(String path, String status) => throw UnimplementedError();

  /// Acknowledges the most recent unanswered write (put or merge).
  void ackLastWrite() => throw UnimplementedError();

  /// Refuses the most recent unanswered write with the wire [status], for example `'permission_denied'` or
  /// `'datastale'`.
  void failLastWrite(String status) => throw UnimplementedError();

  /// Acknowledges the most recent unanswered onDisconnect request.
  void ackLastOnDisconnect() => throw UnimplementedError();

  /// Answers the open get at [path] with [value].
  void answerGet(String path, Object? value) => throw UnimplementedError();

  /// Refuses the open get at [path] with the wire [status].
  void failGet(String path, String status) => throw UnimplementedError();

  /// Drops the current connection; the client reconnects when [acceptConnections] allows it.
  void dropConnection() => throw UnimplementedError();

  /// Revokes the client's auth: the connection drops and the client listens again after reconnecting.
  void revokeAuth() => throw UnimplementedError();

  /// Kills the connection with [reason], as the server's kill message does: the client stays offline until
  /// the instance is recreated.
  void kill(String reason) => throw UnimplementedError();
}
