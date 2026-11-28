/// Helpers of `rc_abt_test.dart` (A42, the A/B testing hand-off): a recording [RemoteConfigAnalytics]
/// whose calls can throw or hang, and a [AbtKit] that builds Remote Config instances with it on the
/// fake clock of a [Harness].
library;

import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:firebase_remote_config_dart/firebase_remote_config_dart.dart';
import 'package:test/test.dart';

import 'fakes.dart';
import 'rc_fetch_harness.dart';

/// The event the hand-off logs after the user properties (A42).
const String abtEvent = 'set_firebase_experiment_state';

/// One call the connector received.
final class AbtCall {
  /// A `setUserProperties` call.
  AbtCall.set(Map<String, String?> properties)
    : properties = Map<String, String?>.of(properties),
      event = null;

  /// A `logEvent` call.
  AbtCall.event(String this.event) : properties = null;

  /// The map of a `setUserProperties` call; null for `logEvent`.
  final Map<String, String?>? properties;

  /// The name of a `logEvent` call; null for `setUserProperties`.
  final String? event;

  @override
  String toString() => properties == null
      ? 'logEvent($event)'
      : 'setUserProperties($properties)';
}

/// A [RemoteConfigAnalytics] that records every call in [calls]. [onSet] and [onEvent] give the future
/// each call returns (default: completes at once); they may throw or return a future that never
/// completes.
final class FakeAnalytics implements RemoteConfigAnalytics {
  /// The calls, in order.
  final List<AbtCall> calls = <AbtCall>[];

  /// The answer of `setUserProperties`; null completes at once.
  Future<void> Function(Map<String, String?> properties)? onSet;

  /// The answer of `logEvent`; null completes at once.
  Future<void> Function(String name)? onEvent;

  /// The maps of the `setUserProperties` calls, in order.
  List<Map<String, String?>> get sets => <Map<String, String?>>[
    for (final AbtCall call in calls)
      if (call.properties case final Map<String, String?> properties)
        properties,
  ];

  /// The names of the `logEvent` calls, in order.
  List<String> get events => <String>[
    for (final AbtCall call in calls)
      if (call.event case final String event) event,
  ];

  /// Makes every call return a future that fails with a new [error].
  void failWith(Error Function() error) {
    onSet = (Map<String, String?> _) async => throw error();
    onEvent = (String _) async => throw error();
  }

  @override
  Future<void> setUserProperties(Map<String, String?> properties) {
    calls.add(AbtCall.set(properties));
    return onSet?.call(properties) ?? Future<void>.value();
  }

  @override
  Future<void> logEvent(String name) {
    calls.add(AbtCall.event(name));
    return onEvent?.call(name) ?? Future<void>.value();
  }
}

/// A test that runs [body] in `fakeAsync` with an [AbtKit]; every instance the kit made is closed at
/// the end.
void abtTest(String description, void Function(AbtKit kit) body) {
  fakeTest(description, (FakeAsync async, Harness harness) {
    final AbtKit kit = AbtKit._(async, harness);
    try {
      body(kit);
    } finally {
      kit._closeAll();
    }
  });
}

/// Builds an [RcEnv] and Remote Config instances with a [FakeAnalytics] on the fake clock.
final class AbtKit {
  AbtKit._(this.async, this.h);

  /// The fake zone.
  final FakeAsync async;

  /// The harness of the test.
  final Harness h;

  /// The warnings every instance of this kit logged, in order.
  final List<String> warnings = <String>[];

  final List<FirebaseRemoteConfig> _instances = <FirebaseRemoteConfig>[];
  int _version = 0;

  /// The environment (app, Installations, backend, store); created on first use.
  late final RcEnv env = h.env(store: store);

  /// The store of [env]; calls can be delayed or failed.
  late final ScriptedStore store = ScriptedStore();

  /// The store key of the experiments record.
  String get experimentsKey => env.recordKey('experiments');

  /// A Remote Config instance on [env] with [analytics] (none when null), a fetch interval of zero and
  /// [fetchTimeout]. Its warnings go to [warnings].
  FirebaseRemoteConfig instance({
    RemoteConfigAnalytics? analytics,
    Duration fetchTimeout = const Duration(seconds: 60),
  }) {
    final RcEnv environment = env;
    final FirebaseRemoteConfig rc = FirebaseRemoteConfig(
      environment.app,
      installations: environment.installations,
      minimumFetchInterval: Duration.zero,
      fetchTimeout: fetchTimeout,
      languageCode: 'en-US',
      httpClient: environment.backend.client,
      analytics: analytics,
      logger: (RemoteConfigLogLevel level, String message) {
        if (level == RemoteConfigLogLevel.warning) {
          warnings.add(message);
        }
      },
      clock: environment.clock,
      random: () => 0.5,
    );
    _instances.add(rc);
    return rc;
  }

  /// The warnings that mention the analytics connector.
  List<String> get analyticsWarnings => <String>[
    for (final String warning in warnings)
      if (warning.contains('analytics')) warning,
  ];

  /// Moves the clock by one second (so the next fetch has a new fetch time), then fetches a new
  /// template whose `experimentDescriptions` hold [experiments] (experiment id to variant id, in order).
  void fetch(FirebaseRemoteConfig rc, Map<String, String> experiments) {
    fetchDescriptions(rc, <Map<String, Object?>>[
      for (final MapEntry<String, String> entry in experiments.entries)
        <String, Object?>{'experimentId': entry.key, 'variantId': entry.value},
    ]);
  }

  /// As [fetch] with raw [descriptions].
  void fetchDescriptions(
    FirebaseRemoteConfig rc,
    List<Map<String, Object?>> descriptions,
  ) {
    _version++;
    env.backend.enqueue(
      FakeRoute.fetch,
      FakeAnswer.fetch(
        entries: <String, String>{'k': 'v$_version'},
        templateVersion: '$_version',
        extra: <String, Object?>{
          if (descriptions.isNotEmpty) 'experimentDescriptions': descriptions,
        },
      ),
    );
    async.elapse(const Duration(seconds: 1));
    expect(h.settle(rc.fetch()), FetchResult.updated);
  }

  /// [fetch], then [FirebaseRemoteConfig.activate] without moving the clock; returns its result.
  bool cycle(FirebaseRemoteConfig rc, Map<String, String> experiments) {
    fetch(rc, experiments);
    return h.settle(rc.activate());
  }

  /// The stored experiment ids, or null when there is no record.
  Set<String>? storedIds() {
    final String? text = h.settle(env.store.read(experimentsKey));
    if (text == null) {
      return null;
    }
    final Map<String, Object?> json = jsonDecode(text) as Map<String, Object?>;
    return <String>{...(json['ids']! as List<Object?>).cast<String>()};
  }

  /// Writes the experiments record with [ids] as the package stores it.
  void storeIds(Iterable<String> ids) {
    writeRaw(jsonEncode(<String, Object?>{'v': 1, 'ids': ids.toList()}));
  }

  /// Writes [text] as the experiments record.
  void writeRaw(String? text) {
    h.settle(env.store.write(experimentsKey, text));
  }

  /// Tracks whether [future] completed, without waiting for it; errors are kept, not thrown.
  Tracked<T> track<T>(Future<T> future) => Tracked<T>._(future);

  void _closeAll() {
    for (final FirebaseRemoteConfig rc in _instances) {
      h.settle(rc.close());
    }
  }
}

/// The state of a future the test does not wait for.
final class Tracked<T> {
  Tracked._(Future<T> future) {
    future.then<void>(
      (T result) {
        done = true;
        value = result;
      },
      onError: (Object e) {
        done = true;
        error = e;
      },
    );
  }

  /// True once the future completed.
  bool done = false;

  /// Its value, once it completed with one.
  T? value;

  /// Its error, once it failed.
  Object? error;
}
