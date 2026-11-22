// Owner U. The rig of the connection-only emulator tests: the emulator address from
// FIREBASE_DATABASE_EMULATOR_HOST, one fresh namespace per test, rules and data through REST as
// the owner, and clients (a real PersistentConnection over the io connector, with the core's
// RecordingServerActionsDelegate), optionally through the chaos proxy and its frame tap.
//
// Every expectation in the tests that use it is what rtdb_emulator_probe.md MEASURED (emulator
// v4.11.2); each test names the section.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:firebase_database_dart/src/core/connection/listen_hash_provider.dart';
import 'package:firebase_database_dart/src/core/connection/listen_spec.dart';
import 'package:firebase_database_dart/src/core/connection/server_actions.dart';
import 'package:firebase_database_dart/src/core/repo_info.dart';
import 'package:firebase_database_dart/src/realtime/connection.dart';
import 'package:firebase_database_dart/src/realtime/connection_timings.dart';
import 'package:firebase_database_dart/src/realtime/database_url.dart';
import 'package:firebase_database_dart/src/realtime/persistent_connection.dart';
import 'package:firebase_database_dart/src/realtime/realtime_target.dart';
import 'package:firebase_database_dart/src/realtime/reconnect_backoff.dart';
import 'package:firebase_database_dart/src/realtime/rest_client.dart';
import 'package:firebase_database_dart/src/realtime/transport/ws_connector.dart';
import 'package:firebase_database_dart/src/testing/recording_server_actions_delegate.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../util/chaos_proxy.dart';
import '../util/fakes.dart';

/// The project id of the emulator scripts (`tool/start_database_emulator.sh`).
const String emulatorProjectId = 'demo-test';

/// Null when the emulator address is set, else why every test of a file is skipped.
String? get emulatorSkipReason =>
    Platform.environment[RealtimeProtocol.emulatorHostVariable] == null
    ? '${RealtimeProtocol.emulatorHostVariable} is not set: start the emulator with '
          'tool/start_database_emulator.sh 9100 and export '
          '${RealtimeProtocol.emulatorHostVariable}=127.0.0.1:9100'
    : null;

/// Timings for tests: the production values except a short reconnect delay and connect
/// timeout, so a reconnect takes milliseconds. Tests that need other values copy these.
const ConnectionTimings testTimings = ConnectionTimings(
  reconnectMin: Duration(milliseconds: 50),
  reconnectMax: Duration(milliseconds: 500),
  connectTimeout: Duration(seconds: 5),
);

/// How long a test waits for something the emulator does at once.
const Duration quick = Duration(seconds: 5);

/// The default listen of [path] (`ListenSpec` of the default query).
ListenSpec defaultSpec(String path) => ListenSpec(
  path: path,
  queryObject: const <String, Object?>{},
  queryIdentifier: 'default',
  isDefault: true,
  loadsAllData: true,
  indexName: '.priority',
  restParams: const <String, String>{},
);

/// A `.key` query of [path] limited to the first [limit] children.
ListenSpec keyLimitSpec(String path, int limit) => ListenSpec(
  path: path,
  queryObject: <String, Object?>{'i': '.key', 'l': limit, 'vf': 'l'},
  queryIdentifier: '{"i":".key","l":$limit,"vf":"l"}',
  isDefault: false,
  loadsAllData: false,
  indexName: '.key',
  restParams: <String, String>{'orderBy': '"\$key"', 'limitToFirst': '$limit'},
);

/// A hash provider with a fixed simple hash (`""`: the client holds nothing) and no compound
/// hash.
final class FixedHash implements ListenHashProvider {
  /// Creates the provider of [hash].
  const FixedHash([this.hash = '']);

  /// The `h` sent with the listen.
  final String hash;

  @override
  String simpleHash() => hash;

  @override
  bool shouldIncludeCompoundHash() => false;

  @override
  WireCompoundHash compoundHash() =>
      throw UnsupportedError('no compound hash in these tests');
}

/// Polls [probe] every 10 ms until it returns non-null, failing after [timeout] with [what].
Future<T> eventually<T>(
  T? Function() probe, {
  required String what,
  Duration timeout = quick,
}) async {
  final Stopwatch watch = Stopwatch()..start();
  while (true) {
    final T? value = probe();
    if (value != null) {
      return value;
    }
    if (watch.elapsed > timeout) {
      fail('Timed out after $timeout waiting for $what');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// One request's completion: its status and data, and how many delegate calls had been
/// recorded when it completed (to check that a push came before the ack).
typedef Ack = ({String status, Object? data, int callsBefore});

/// One namespace on the emulator, and the clients and proxies opened on it.
final class EmulatorRig {
  EmulatorRig._(this.host, this.port, this.namespace);

  /// A rig on a fresh namespace `t-<random>` (probe "Namespaces": lowercase letters, digits and
  /// `-` work, every new name is an empty database with open rules; "Notes for the tests").
  static EmulatorRig create() {
    final ({String host, int port}) address = parseEmulatorHost(
      Platform.environment[RealtimeProtocol.emulatorHostVariable]!,
    );
    final Random random = Random();
    final String suffix = List<String>.generate(
      10,
      (_) => 'abcdefghijklmnopqrstuvwxyz0123456789'[random.nextInt(36)],
    ).join();
    final EmulatorRig rig = EmulatorRig._(
      address.host,
      address.port,
      't-$suffix',
    );
    addTearDown(rig.close);
    return rig;
  }

  /// The emulator host.
  final String host;

  /// The emulator port.
  final int port;

  /// This test's namespace.
  final String namespace;

  final http.Client _http = http.Client();
  final List<RigClient> _clients = <RigClient>[];
  final List<ChaosProxy> _proxies = <ChaosProxy>[];

  /// The emulator database of this namespace, reached directly.
  RepoInfo get repoInfo => emulatorDatabase(host, port, namespace: namespace);

  Uri _rest(
    String path, [
    Map<String, String> params = const <String, String>{},
  ]) => RealtimeTarget(repoInfo, useHeaders: true).restUri(path, params);

  Map<String, String> get _owner => const <String, String>{
    'Authorization': 'Bearer owner',
  };

  /// Sets the rules of this namespace: `PUT /.settings/rules.json` as the owner (probe
  /// "`/.settings/rules.json`": 200 `{"status":"ok"}`; rules apply at once to open connections).
  Future<void> setRules(Map<String, Object?> rules) async {
    final http.Response response = await _http.put(
      _rest('/.settings/rules'),
      headers: _owner,
      body: jsonEncode(<String, Object?>{'rules': rules}),
    );
    expect(response.statusCode, 200, reason: response.body);
  }

  /// Writes [value] at [path] through REST as the owner (`Bearer owner` is admin, probe "Auth
  /// on REST").
  Future<void> write(String path, Object? value) async {
    final http.Response response = await _http.put(
      _rest(path),
      headers: _owner,
      body: jsonEncode(value),
    );
    expect(response.statusCode, 200, reason: response.body);
  }

  /// The raw JSON text at [path], read through REST as the owner.
  Future<String> readRaw(String path) async {
    final http.Response response = await _http.get(
      _rest(path),
      headers: _owner,
    );
    expect(response.statusCode, 200, reason: response.body);
    return response.body;
  }

  /// The decoded value at [path].
  Future<Object?> read(String path) async => jsonDecode(await readRaw(path));

  /// Starts a chaos proxy in front of the emulator, closed at the end of the test.
  Future<ChaosProxy> proxy() async {
    final ChaosProxy proxy = await ChaosProxy.start(host, port);
    _proxies.add(proxy);
    return proxy;
  }

  /// Opens a client, connected (its first `onConnect` seen) when the future completes; through
  /// [proxy] when given.
  Future<RigClient> open({
    FakeTokenSource? tokens,
    ConnectionTimings timings = testTimings,
    ChaosProxy? proxy,
  }) async {
    final RepoInfo info = proxy == null
        ? repoInfo
        : emulatorDatabase(proxy.host, proxy.port, namespace: namespace);
    final RigClient client = RigClient._(
      RealtimeTarget(info, useHeaders: wsConnectorSendsHeaders),
      tokens ?? FakeTokenSource(),
      timings,
    );
    _clients.add(client);
    client.connection.initialize();
    await client.waitConnects(1);
    return client;
  }

  /// A REST client of this namespace (`RestClient`) with [tokens].
  RestRigClient openRest({FakeTokenSource? tokens}) {
    final RecordingServerActionsDelegate delegate =
        RecordingServerActionsDelegate();
    final RestClient client = RestClient(
      target: RealtimeTarget(repoInfo, useHeaders: true),
      tokens: tokens ?? FakeTokenSource(),
      delegate: delegate,
      maxResponseBytes: testTimings.maxMessageBytes,
      useHeaders: true,
      requestTimeout: quick,
    );
    addTearDown(client.shutdown);
    return (client: client, delegate: delegate);
  }

  /// Shuts every client down, closes the proxies and the HTTP client.
  Future<void> close() async {
    for (final RigClient client in _clients) {
      await client.connection.shutdown();
    }
    for (final ChaosProxy proxy in _proxies) {
      await proxy.close();
    }
    _http.close();
  }
}

/// A [RestClient] and the delegate it reports to.
typedef RestRigClient = ({
  RestClient client,
  RecordingServerActionsDelegate delegate,
});

/// One [PersistentConnection] with its recording delegate and the reasons its connections
/// closed with (seen through a wrapper around the connection's own delegate).
final class RigClient {
  RigClient._(this.target, this.tokens, ConnectionTimings timings) {
    connection = PersistentConnection(
      target: target,
      connectionFactory: _factory(timings),
      backoff: ReconnectBackoff(
        min: timings.reconnectMin,
        max: timings.reconnectMax,
        multiplier: timings.reconnectMultiplier,
        resetAfter: timings.reconnectResetAfter,
        now: DateTime.now,
        random: Random().nextDouble,
      ),
      tokens: tokens,
      delegate: delegate,
      timings: timings,
      now: DateTime.now,
      random: Random().nextDouble,
    );
  }

  /// Where it connects.
  final RealtimeTarget target;

  /// Its token source.
  final FakeTokenSource tokens;

  /// What the connection told Repo.
  final RecordingServerActionsDelegate delegate =
      RecordingServerActionsDelegate();

  /// The reason of every closed connection, in order.
  final List<DisconnectReason> disconnectReasons = <DisconnectReason>[];

  /// The connection under test.
  late final PersistentConnection connection;

  RealtimeConnectionFactory _factory(ConnectionTimings timings) {
    return (
      RealtimeDelegate inner, {
      String? lastSessionId,
      String? appId,
      String? appCheckToken,
    }) => RealtimeConnection(
      target,
      // As production wires it (RealtimeConnectionFactory's doc): every inbound frame reaches
      // the persistent connection's link-silence timer (review H1).
      tapInboundFrames(
        platformWsConnector(maxMessageBytes: timings.maxMessageBytes),
        () => connection.inboundFrame(),
      ),
      timings,
      _ReasonRecorder(inner, disconnectReasons),
      lastSessionId: lastSessionId,
      appId: appId,
      appCheckToken: appCheckToken,
    );
  }

  /// Completes once [count] `onConnect` calls were recorded.
  Future<void> waitConnects(int count, {Duration timeout = quick}) =>
      eventually(
        () => delegate.callsOf('connect').length >= count ? true : null,
        what: '$count connect(s)',
        timeout: timeout,
      );

  /// The first data update after index [from] matching [test].
  Future<DelegateCall> update(
    bool Function(DelegateCall c) test, {
    int from = 0,
    Duration timeout = quick,
  }) => eventually(
    () {
      for (final DelegateCall call in delegate.calls.skip(from)) {
        if (call.method == 'dataUpdate' && test(call)) {
          return call;
        }
      }
      return null;
    },
    what: 'a matching data update',
    timeout: timeout,
  );

  /// The data updates at [path] recorded so far.
  List<DelegateCall> updatesAt(String path) => delegate
      .callsOf('dataUpdate')
      .where((DelegateCall c) => c.path == path)
      .toList();

  /// A callback that records every completion of one request, and its first completion.
  (RequestResultCallback, List<Ack>) recorder() {
    final List<Ack> acks = <Ack>[];
    return (
      (String status, Object? data) => acks.add((
        status: status,
        data: data,
        callsBefore: delegate.calls.length,
      )),
      acks,
    );
  }

  /// Listens to [spec] and returns the list its completions go to.
  List<Ack> listen(ListenSpec spec, {int? tag, String hash = ''}) {
    final (RequestResultCallback callback, List<Ack> acks) = recorder();
    connection.listen(
      spec,
      hashProvider: FixedHash(hash),
      tag: tag,
      onComplete: callback,
    );
    return acks;
  }

  /// Waits for the first completion in [acks].
  Future<Ack> first(List<Ack> acks, {Duration timeout = quick}) => eventually(
    () => acks.isEmpty ? null : acks.first,
    what: 'a request completion',
    timeout: timeout,
  );

  /// Puts [data] at [path] and waits for the answer.
  Future<Ack> put(String path, Object? data, {Duration timeout = quick}) {
    final (RequestResultCallback callback, List<Ack> acks) = recorder();
    connection.put(path, data, onComplete: callback);
    return first(acks, timeout: timeout);
  }
}

final class _ReasonRecorder implements RealtimeDelegate {
  _ReasonRecorder(this._inner, this._reasons);

  final RealtimeDelegate _inner;
  final List<DisconnectReason> _reasons;

  @override
  void onReady(int serverTimeMs, String sessionId) =>
      _inner.onReady(serverTimeMs, sessionId);

  @override
  void onDataMessage(Map<String, Object?> message) =>
      _inner.onDataMessage(message);

  @override
  void onDisconnect(DisconnectReason reason) {
    _reasons.add(reason);
    _inner.onDisconnect(reason);
  }

  @override
  void onKill(String reason) => _inner.onKill(reason);
}
