/// Helpers of `rc_review198_test.dart` (the fixes of the review of pull request #198, A38, A39, A42):
/// a [GatedStore] whose calls can pause before or after they run, or fail, per key; a fake
/// Installations whose id the test changes; and a [Review198Rig] that builds Remote Config instances
/// over them on fake time.
library;

import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_remote_config_dart/firebase_remote_config_dart.dart';
import 'package:test/test.dart';

import 'fakes.dart';
import 'missing_backoff_harness.dart';
import 'rc_realtime_fakes.dart';

/// The fake time at which every rig test starts.
final DateTime rigStart = DateTime.utc(2026, 11, 28, 12);

int _apps = 0;

/// What a [GatedStore] rule does with the call it matches.
enum _RuleKind { pauseBefore, pauseAfter, fail }

/// A pause of one store call, set with [GatedStore.pauseBefore] or [GatedStore.pauseAfter].
final class StorePause {
  StorePause._();

  final Completer<void> _gate = Completer<void>();

  /// True once the call reached the pause.
  bool reached = false;

  /// Lets the paused call go on.
  void open() {
    if (!_gate.isCompleted) {
      _gate.complete();
    }
  }
}

final class _Rule {
  _Rule(this.kind, this.op, this.key, this.skip, [this.pause]);

  final _RuleKind kind;
  final StoreOp op;
  final String key;
  final StorePause? pause;
  int skip;
  bool used = false;
}

/// A [KeyValueStore] over a [MemoryKeyValueStore] whose calls can pause before or after they run, or
/// fail, chosen by operation and key. Every call is logged in [calls] when it starts.
final class GatedStore implements KeyValueStore {
  /// The store that keeps the values; reading it bypasses the rules and the log.
  final MemoryKeyValueStore inner = MemoryKeyValueStore();

  /// Every call, in the order they started.
  final List<(StoreOp, String)> calls = <(StoreOp, String)>[];

  final List<_Rule> _rules = <_Rule>[];

  /// Pauses a call of [op] on [key] before it reaches [inner]: the first such call after [skip] more.
  StorePause pauseBefore(StoreOp op, String key, {int skip = 0}) =>
      _addPause(_RuleKind.pauseBefore, op, key, skip);

  /// Pauses a call of [op] on [key] after [inner] ran it, before it returns: the first such call after
  /// [skip] more.
  StorePause pauseAfter(StoreOp op, String key, {int skip = 0}) =>
      _addPause(_RuleKind.pauseAfter, op, key, skip);

  /// Fails a call of [op] on [key] (after [skip] more) with a [StateError]; it changes nothing.
  void failOnce(StoreOp op, String key, {int skip = 0}) {
    _rules.add(_Rule(_RuleKind.fail, op, key, skip));
  }

  /// The number of calls of [op] on [key] so far.
  int count(StoreOp op, String key) => calls
      .where(((StoreOp, String) call) => call.$1 == op && call.$2 == key)
      .length;

  StorePause _addPause(_RuleKind kind, StoreOp op, String key, int skip) {
    final StorePause pause = StorePause._();
    _rules.add(_Rule(kind, op, key, skip, pause));
    return pause;
  }

  /// The rule of [kind] the call takes, if any; counts the call against every other matching rule.
  _Rule? _take(_RuleKind kind, StoreOp op, String key) {
    _Rule? chosen;
    for (final _Rule rule in _rules) {
      if (rule.used || rule.kind != kind || rule.op != op || rule.key != key) {
        continue;
      }
      if (rule.skip > 0) {
        rule.skip--;
      } else if (chosen == null) {
        rule.used = true;
        chosen = rule;
      }
    }
    return chosen;
  }

  Future<T> _run<T>(StoreOp op, String key, Future<T> Function() call) async {
    calls.add((op, key));
    final StorePause? before = _take(_RuleKind.pauseBefore, op, key)?.pause;
    if (before != null) {
      before.reached = true;
      await before._gate.future;
    }
    if (_take(_RuleKind.fail, op, key) != null) {
      throw StateError('fake store failure (${op.name} $key)');
    }
    final T result = await call();
    final StorePause? after = _take(_RuleKind.pauseAfter, op, key)?.pause;
    if (after != null) {
      after.reached = true;
      await after._gate.future;
    }
    return result;
  }

  @override
  Future<String?> read(String key) =>
      _run(StoreOp.read, key, () => inner.read(key));

  @override
  Future<void> write(String key, String? value) =>
      _run(StoreOp.write, key, () => inner.write(key, value));

  @override
  Future<String?> update(
    String key,
    String? Function(String? current) transform,
  ) => _run(StoreOp.update, key, () => inner.update(key, transform));

  @override
  Stream<String> get changes => inner.changes;

  @override
  Future<void> close() => inner.close();
}

/// A [FirebaseInstallations] over a given store whose id the test changes with [changeId].
final class Review198Installations implements FirebaseInstallations {
  /// Creates the fake for [app] over [store].
  Review198Installations(this.app, this.store);

  @override
  final FirebaseApp app;

  @override
  final KeyValueStore store;

  @override
  final Map<String, String> headers = const <String, String>{};

  /// The id [getIdAndToken] returns.
  String fid = rcFirstFid;

  final StreamController<String> _idChanges =
      StreamController<String>.broadcast();

  @override
  Stream<String> get onIdChange => _idChanges.stream;

  @override
  Future<({String id, String token})> getIdAndToken({
    bool forceRefresh = false,
  }) async => (id: fid, token: 'review198-token');

  /// Switches to [id] and emits it on [onIdChange].
  void changeId(String id) {
    fid = id;
    _idChanges.add(id);
  }

  @override
  Future<void> close() async {
    // Not awaited: closing a broadcast controller without a listener never completes in fake time.
    unawaited(_idChanges.close());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The state of a future the test does not wait for; errors are kept, not thrown.
final class Pending<T> {
  /// Tracks [future].
  Pending(this.future) {
    unawaited(
      future.then<void>(
        (T result) {
          done = true;
          value = result;
        },
        onError: (Object e) {
          done = true;
          error = e;
        },
      ),
    );
  }

  /// The tracked future.
  final Future<T> future;

  /// True once [future] completed.
  bool done = false;

  /// Its value, once it completed with one.
  T? value;

  /// Its error, once it failed.
  Object? error;
}

/// Counts the events of `onActivated`.
final class ActivatedCount {
  /// Listens to [stream].
  ActivatedCount(Stream<void> stream) {
    stream.listen((void _) => count++);
  }

  /// The events so far.
  int count = 0;
}

/// A test that runs [body] in `fakeAsync` with a [Review198Rig], disposed at the end.
void rigTest(String description, void Function(Review198Rig rig) body) {
  test(description, () {
    fakeAsync((FakeAsync async) {
      final Review198Rig rig = Review198Rig._(async);
      try {
        body(rig);
      } finally {
        rig._dispose();
      }
    });
  });
}

/// An app, a [Review198Installations] and a [FakeBackend] over one [GatedStore], on fake time.
final class Review198Rig {
  Review198Rig._(this.async) {
    app = FirebaseApp.withOptions(fakeOptions, name: 'rc-review198-${_apps++}');
    installations = Review198Installations(app, store);
  }

  /// The fake zone.
  final FakeAsync async;

  /// The store of every instance.
  final GatedStore store = GatedStore();

  /// The fetch server.
  final FakeBackend backend = FakeBackend();

  /// The app; deleted at the end.
  late final FirebaseApp app;

  /// The Installations fake over [store].
  late final Review198Installations installations;

  /// The warnings every instance logged, in order.
  final List<String> warnings = <String>[];

  final List<FirebaseRemoteConfig> _instances = <FirebaseRemoteConfig>[];

  /// The fake clock.
  DateTime now() => rigStart.add(async.elapsed);

  /// Moves the fake clock to [time].
  void elapseTo(DateTime time) {
    async.elapse(time.difference(now()));
  }

  /// Runs the microtasks and the zero-length timers due now, a few rounds.
  void pump() {
    for (int i = 0; i < 5; i++) {
      async
        ..flushMicrotasks()
        ..elapse(Duration.zero);
    }
  }

  /// The store key of the record [name].
  String key(String name) => 'remote_config/${app.persistenceKey}/$name';

  /// The stored text of the record [name], bypassing the rules of [store].
  String? raw(String name) => async.settle(store.inner.read(key(name)));

  /// The stored record [name] decoded as JSON, or null when absent.
  Map<String, Object?>? record(String name) {
    final String? text = raw(name);
    return text == null ? null : jsonDecode(text) as Map<String, Object?>;
  }

  /// Waits for [future] without moving the clock.
  T settle<T>(Future<T> future) => async.settle(future);

  /// Waits for [future] and returns the [FirebaseRemoteConfigException] it fails with.
  FirebaseRemoteConfigException rcError(Future<Object?> future) {
    try {
      final Object? value = async.settle(future);
      fail('Expected a FirebaseRemoteConfigException, got $value.');
    } on FirebaseRemoteConfigException catch (error) {
      return error;
    }
  }

  /// A Remote Config instance with a fetch interval of zero; its warnings go to [warnings].
  FirebaseRemoteConfig instance({
    RemoteConfigAnalytics? analytics,
    Duration fetchTimeout = const Duration(seconds: 60),
    Map<String, Object> defaults = const <String, Object>{},
  }) {
    final FirebaseRemoteConfig rc = FirebaseRemoteConfig(
      app,
      installations: installations,
      defaults: defaults,
      minimumFetchInterval: Duration.zero,
      fetchTimeout: fetchTimeout,
      languageCode: 'en-US',
      httpClient: backend.client,
      analytics: analytics,
      logger: (RemoteConfigLogLevel level, String message) {
        if (level == RemoteConfigLogLevel.warning) {
          warnings.add(message);
        }
      },
      clock: now,
      random: () => 0.5,
    );
    _instances.add(rc);
    return rc;
  }

  /// A fetch answer with [entries], [version] and [experiments] (experiment id to variant id).
  FakeAnswer template({
    required int version,
    Map<String, String> entries = const <String, String>{'a': 'remote'},
    Map<String, String> experiments = const <String, String>{},
  }) => FakeAnswer.fetch(
    entries: entries,
    templateVersion: '$version',
    extra: <String, Object?>{
      if (experiments.isNotEmpty)
        'experimentDescriptions': <Map<String, Object?>>[
          for (final MapEntry<String, String> entry in experiments.entries)
            <String, Object?>{
              'experimentId': entry.key,
              'variantId': entry.value,
            },
        ],
    },
  );

  /// Moves the clock by one second, then fetches [template] into [rc].
  void fetch(
    FirebaseRemoteConfig rc, {
    required int version,
    Map<String, String> entries = const <String, String>{'a': 'remote'},
    Map<String, String> experiments = const <String, String>{},
  }) {
    backend.enqueue(
      FakeRoute.fetch,
      template(version: version, entries: entries, experiments: experiments),
    );
    async.elapse(const Duration(seconds: 1));
    expect(async.settle(rc.fetch()), FetchResult.updated);
  }

  void _dispose() {
    for (final FirebaseRemoteConfig rc in _instances) {
      unawaited(rc.close());
    }
    unawaited(installations.close());
    unawaited(app.delete());
    async.flushMicrotasks();
  }
}

/// A second Remote Config instance on the app, Installations and store of [h], built like the
/// harness's own, without waiting for its load.
FirebaseRemoteConfig review198BackoffInstance(BackoffHarness h) =>
    FirebaseRemoteConfig(
      h.app,
      installations: h.installations,
      defaults: const <String, Object>{'welcome': 'default'},
      languageCode: 'en',
      httpClient: h.server.client,
      serverOrigin: rcServerOrigin,
      realtimeOrigin: rcRealtimeOrigin,
      clock: h.now,
      random: () => 0.5,
    );
