import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_remote_config_dart/firebase_remote_config_dart.dart';
import 'package:firebase_remote_config_dart/src/realtime/auto_fetch.dart';
import 'package:firebase_remote_config_dart/src/realtime/realtime_client.dart';
import 'package:firebase_remote_config_dart/src/template.dart';

import 'rc_realtime_fakes.dart';

int _appCount = 0;

/// A public [FirebaseRemoteConfig] on fake time, wired to a [RealtimeServer] and [FakeInstallations].
///
/// The jitter source returns [random] for every draw: 0.5 makes every backoff exactly its table value
/// and every auto-fetch wait 1.5 s.
final class RcHarness {
  /// Builds the instance inside [async] and lets it load its (empty) records.
  RcHarness(
    this.async, {
    FirebaseOptions options = rcOptions,
    this.random = 0.5,
    Future<void> Function(Duration duration)? delay,
  }) {
    server = RealtimeServer(now);
    app = FirebaseApp.withOptions(
      options,
      name: 'rc-realtime-test-${_appCount++}',
    );
    installations = FakeInstallations(now, app: app);
    remoteConfig = FirebaseRemoteConfig(
      app,
      installations: installations,
      defaults: const <String, Object>{'welcome': 'default'},
      languageCode: 'en',
      httpClient: server.client,
      serverOrigin: rcServerOrigin,
      realtimeOrigin: rcRealtimeOrigin,
      clock: now,
      random: () => random,
      delay: delay,
    );
    async.flushMicrotasks();
  }

  /// The fake-time zone.
  final FakeAsync async;

  /// The value every random draw returns.
  final double random;

  /// Both servers.
  late final RealtimeServer server;

  /// The app; [dispose] deletes it.
  late final FirebaseApp app;

  /// The Installations fake.
  late final FakeInstallations installations;

  /// The instance under test.
  late final FirebaseRemoteConfig remoteConfig;

  /// The fake clock.
  DateTime now() => rcEpoch.add(async.elapsed);

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

  /// Closes the instance and deletes the app.
  void dispose() {
    unawaited(remoteConfig.close());
    unawaited(app.delete());
    async.flushMicrotasks();
  }
}

/// A [RealtimeClient] built through its constructor on fake time.
///
/// The network stream replays `true` on listen unless `seedNetwork` is false; then the test sends the
/// first event itself (the one the client must skip).
final class DirectRealtime {
  /// Builds the client inside [async].
  DirectRealtime(
    this.async, {
    FirebaseOptions options = rcOptions,
    this.random = 0.5,
    bool seedNetwork = true,
  }) {
    server = RealtimeServer(now);
    installations = FakeInstallations(now);
    if (seedNetwork) {
      network.add(true);
    }
    client = RealtimeClient(
      options: options,
      installations: installations,
      fetchForRealtime: (int attempt) {
        fetchAttempts.add(attempt);
        return onFetch(attempt);
      },
      templates: () => (active: active, fetched: fetched),
      isInBackground: () => background.value,
      backgroundChanged: background.stream,
      networkConnected: network.stream,
      visibility: visibility,
      httpClient: server.client,
      origin: rcRealtimeOrigin,
      clock: now,
      random: () => random,
      delay: Future<void>.delayed,
    );
    async.flushMicrotasks();
  }

  /// The fake-time zone.
  final FakeAsync async;

  /// The value every random draw returns.
  final double random;

  /// The realtime server.
  late final RealtimeServer server;

  /// The Installations fake.
  late final FakeInstallations installations;

  /// The client under test.
  late final RealtimeClient client;

  /// `onBackgroundChanged`.
  final ReplayingBool background = ReplayingBool(false);

  /// `onNetworkConnected`: a single-subscription stream, so the first event is the replayed seed.
  final StreamController<bool> network = StreamController<bool>();

  /// Page visibility.
  final FakeVisibility visibility = FakeVisibility();

  /// The active record the client sees.
  TemplateRecord? active;

  /// The fetched record the client sees.
  TemplateRecord? fetched;

  /// The attempts passed to `fetchForRealtime`, in order.
  final List<int> fetchAttempts = <int>[];

  /// Answers `fetchForRealtime`. Default: unchanged.
  Future<FetchResult> Function(int attempt) onFetch = (int attempt) async =>
      FetchResult.unchanged;

  /// The records, as the client reads them.
  TemplateRecords get templates => (active: active, fetched: fetched);

  /// The fake clock.
  DateTime now() => rcEpoch.add(async.elapsed);

  /// Listens to the client's stream and runs the timers due now.
  UpdateLog listen() {
    final UpdateLog log = UpdateLog()..listen(client.stream);
    async.elapse(Duration.zero);
    return log;
  }

  /// Advances fake time to [offset] from [rcEpoch].
  void elapseTo(Duration offset) {
    async.elapse(offset - async.elapsed);
  }

  /// Closes the client.
  void dispose() {
    unawaited(client.close());
    async.flushMicrotasks();
  }
}
