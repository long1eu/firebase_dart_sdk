/// The fake-time harness of the persisted realtime backoff tests in `rc_missing_test.dart` (A38, A39):
/// a public [FirebaseRemoteConfig] over a [ScriptedStore] that the test seeds before the instance
/// loads, wired to a [RealtimeServer].
library;

import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_remote_config_dart/firebase_remote_config_dart.dart';

import 'fakes.dart';
import 'rc_realtime_fakes.dart';

int _apps = 0;

/// [seconds] after [rcEpoch], fractions allowed.
Duration secondsAfterEpoch(num seconds) =>
    Duration(microseconds: (seconds * 1000000).round());

/// The milliseconds since the Unix epoch of [rcEpoch] plus [offset].
int epochMillis(Duration offset) => rcEpoch.add(offset).millisecondsSinceEpoch;

/// The `realtime` record as A39 stores it; a null wait is left out. Each wait is an offset from
/// [rcEpoch].
String backoffText({
  int serverFailures = 0,
  int transportFailures = 0,
  Duration? serverUntil,
  Duration? transportUntil,
  Duration? retryUntil,
}) => jsonEncode(
  backoffJson(
    serverFailures: serverFailures,
    transportFailures: transportFailures,
    serverUntil: serverUntil,
    transportUntil: transportUntil,
    retryUntil: retryUntil,
  ),
);

/// The decoded form of [backoffText].
Map<String, Object?> backoffJson({
  int serverFailures = 0,
  int transportFailures = 0,
  Duration? serverUntil,
  Duration? transportUntil,
  Duration? retryUntil,
}) => <String, Object?>{
  'v': 1,
  'serverFailures': serverFailures,
  'transportFailures': transportFailures,
  if (serverUntil != null) 'serverUntil': epochMillis(serverUntil),
  if (transportUntil != null) 'transportUntil': epochMillis(transportUntil),
  if (retryUntil != null) 'retryUntil': epochMillis(retryUntil),
};

/// A [FirebaseInstallations] over a given [store], with a fixed id and token.
final class MissingInstallations implements FirebaseInstallations {
  /// Creates the fake for [app] over [store].
  MissingInstallations(this.app, this.store);

  @override
  final FirebaseApp app;

  @override
  final KeyValueStore store;

  @override
  final Map<String, String> headers = const <String, String>{};

  final StreamController<String> _idChanges =
      StreamController<String>.broadcast();

  @override
  Stream<String> get onIdChange => _idChanges.stream;

  @override
  Future<({String id, String token})> getIdAndToken({
    bool forceRefresh = false,
  }) async => (id: rcFirstFid, token: 'missing-installations-token');

  @override
  Future<void> close() async {
    // Not awaited: closing a broadcast controller without a listener never completes in fake time.
    unawaited(_idChanges.close());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A [FirebaseRemoteConfig] on fake time over a [ScriptedStore] seeded with records before it loads.
///
/// The jitter source returns 0.5, so every backoff is exactly its table value.
final class BackoffHarness {
  /// Builds the instance inside [async]. [records] maps record names (`realtime`, `active`, ...) to the
  /// stored text; [before] is set on the store before the instance is created, so it sees the load.
  BackoffHarness(
    this.async, {
    Map<String, String> records = const <String, String>{},
    FutureOr<void> Function(StoreOp op, String key)? before,
    this.logger,
  }) {
    server = RealtimeServer(now);
    app = FirebaseApp.withOptions(rcOptions, name: 'rc-missing-${_apps++}');
    installations = MissingInstallations(app, store);
    for (final MapEntry<String, String> record in records.entries) {
      async.settle(store.inner.write(key(record.key), record.value));
    }
    store.before = before;
    remoteConfig = _create();
    async.flushMicrotasks();
  }

  /// The fake-time zone.
  final FakeAsync async;

  /// Receives the log messages of every instance this harness creates.
  final RemoteConfigLogger? logger;

  /// The store of every instance.
  final ScriptedStore store = ScriptedStore();

  /// Both servers.
  late final RealtimeServer server;

  /// The app; [dispose] deletes it.
  late final FirebaseApp app;

  /// The Installations fake over [store].
  late final MissingInstallations installations;

  /// The instance under test; [restart] replaces it.
  late FirebaseRemoteConfig remoteConfig;

  /// The fake clock.
  DateTime now() => rcEpoch.add(async.elapsed);

  /// The store key of the record [name].
  String key(String name) => 'remote_config/${app.persistenceKey}/$name';

  /// The stored record [name] decoded as JSON, or null when absent. Bypasses [ScriptedStore.before].
  Map<String, Object?>? record(String name) {
    final String? text = async.settle(store.inner.read(key(name)));
    return text == null ? null : jsonDecode(text) as Map<String, Object?>;
  }

  /// Listens to `onConfigUpdated` and runs the timers due now.
  UpdateLog listen() {
    final UpdateLog log = UpdateLog()..listen(remoteConfig.onConfigUpdated);
    async.elapse(Duration.zero);
    return log;
  }

  /// Advances fake time to [offset] from [rcEpoch].
  void elapseTo(Duration offset) {
    async.elapse(offset - async.elapsed);
  }

  /// Closes [remoteConfig] and creates another instance on the same app and store (a new process).
  void restart() {
    unawaited(remoteConfig.close());
    async.flushMicrotasks();
    remoteConfig = _create();
    async.flushMicrotasks();
  }

  /// Closes the instance and deletes the app.
  void dispose() {
    unawaited(remoteConfig.close());
    unawaited(installations.close());
    unawaited(app.delete());
    async.flushMicrotasks();
  }

  FirebaseRemoteConfig _create() => FirebaseRemoteConfig(
    app,
    installations: installations,
    defaults: const <String, Object>{'welcome': 'default'},
    languageCode: 'en',
    httpClient: server.client,
    serverOrigin: rcServerOrigin,
    realtimeOrigin: rcRealtimeOrigin,
    logger: logger,
    clock: now,
    random: () => 0.5,
  );
}
