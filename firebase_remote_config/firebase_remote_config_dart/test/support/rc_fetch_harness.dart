/// The `fakeAsync` harness of `fetch_test.dart` and `activate_test.dart`.
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_remote_config_dart/firebase_remote_config_dart.dart';
import 'package:test/test.dart';

import 'fakes.dart';

/// The fake time at which every harness test starts.
final DateTime harnessStart = DateTime.utc(2026, 11, 28, 12);

/// A test that runs [body] inside `fakeAsync` with a [Harness]; every [RcEnv] it made is disposed at
/// the end.
void fakeTest(
  String description,
  void Function(FakeAsync async, Harness harness) body,
) {
  test(description, () {
    fakeAsync((FakeAsync async) {
      final Harness harness = Harness._(async);
      try {
        body(async, harness);
      } finally {
        harness._disposeAll();
      }
    });
  });
}

/// Builds environments on the fake clock and waits for futures.
final class Harness {
  Harness._(this.async);

  /// The fake zone of the test.
  final FakeAsync async;

  final List<RcEnv> _envs = <RcEnv>[];

  /// The fake time now.
  DateTime now() => harnessStart.add(async.elapsed);

  /// An [RcEnv] on the fake clock (see [RcEnv.create]).
  RcEnv env({
    FakeBackend? backend,
    KeyValueStore? store,
    bool register = true,
    FirebaseOptions options = fakeOptions,
    Map<String, Object> defaults = const <String, Object>{},
    Duration minimumFetchInterval = const Duration(hours: 12),
    Duration fetchTimeout = const Duration(seconds: 60),
    String? languageCode = 'en-US',
    double Function()? random,
    RemoteConfigLogger? logger,
  }) {
    final RcEnv env = async.settle(
      RcEnv.create(
        backend: backend,
        store: store,
        clock: now,
        register: register,
        options: options,
        defaults: defaults,
        minimumFetchInterval: minimumFetchInterval,
        fetchTimeout: fetchTimeout,
        languageCode: languageCode,
        random: random ?? () => 0.5,
        logger: logger,
      ),
    );
    _envs.add(env);
    return env;
  }

  /// Waits for [future] without moving the clock.
  T settle<T>(Future<T> future) => async.settle(future);

  /// Waits for [future] and returns the [FirebaseRemoteConfigException] it fails with; fails the test
  /// when it succeeds or fails with something else.
  FirebaseRemoteConfigException rcError(Future<Object?> future) {
    try {
      final Object? value = async.settle(future);
      fail('Expected a FirebaseRemoteConfigException, got $value.');
    } on FirebaseRemoteConfigException catch (error) {
      return error;
    }
  }

  /// As [rcError], moving the clock in steps of 100 ms for at most [limit].
  FirebaseRemoteConfigException rcErrorWithin(
    Future<Object?> future,
    Duration limit,
  ) {
    try {
      final Object? value = async.settleWithin(future, limit);
      fail('Expected a FirebaseRemoteConfigException, got $value.');
    } on FirebaseRemoteConfigException catch (error) {
      return error;
    }
  }

  void _disposeAll() {
    for (final RcEnv env in _envs) {
      async.settle(env.dispose());
    }
  }
}

/// A gate an answer waits for ([FakeAnswer.after]).
final class Gate {
  final Completer<void> _completer = Completer<void>();

  /// Completes when [open] is called.
  Future<void> get future => _completer.future;

  /// Lets the waiting answer through.
  void open() {
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }
}
