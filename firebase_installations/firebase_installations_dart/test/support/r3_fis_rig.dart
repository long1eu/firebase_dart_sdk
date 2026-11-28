/// Helpers of `installations_r3_test.dart`: one app and one shared [MemoryKeyValueStore] for several
/// `FirebaseInstallations` instances (tabs of one page), a store view whose reads and updates can be
/// made to fail, and the JSON of a stored installation record.
///
/// Create an [R3Rig] inside `fakeAsync`, so its stores, instances and timers live in that zone.
library;

import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_installations_dart/firebase_installations_dart.dart';

import 'fakes.dart';

/// A valid FID (`^[cdef][A-Za-z0-9_-]{21}$`) for records the tests write themselves.
final String r3Fid = 'fR3${'A' * 19}';

/// The failure an [R3Store] throws: an [Exception], so the instance treats it as a transient failure.
final class R3StoreFailure implements Exception {
  /// A failure of [operation].
  const R3StoreFailure(this.operation);

  /// `read` or `update`.
  final String operation;

  @override
  String toString() => 'R3StoreFailure($operation)';
}

/// A view of a shared [MemoryKeyValueStore] whose reads and updates fail on demand.
///
/// A failing update reads the stored value and runs the transform first when [transformBeforeFailing]
/// is set (the write itself failed), else fails before calling it (the store could not start).
final class R3Store implements KeyValueStore {
  /// A view of [inner].
  R3Store(this.inner);

  /// The store shared with the other instances.
  final MemoryKeyValueStore inner;

  /// How many of the next reads fail.
  int failNextReads = 0;

  /// How many of the next updates (and writes) fail.
  int failNextUpdates = 0;

  /// While set, every update (and write) fails.
  bool failUpdates = false;

  /// Whether a failing update runs the transform before it throws.
  bool transformBeforeFailing = true;

  /// How many updates and writes failed so far.
  int updateFailures = 0;

  bool _takeUpdateFailure() {
    if (failUpdates || failNextUpdates > 0) {
      if (failNextUpdates > 0) {
        failNextUpdates--;
      }
      updateFailures++;
      return true;
    }
    return false;
  }

  @override
  Future<String?> read(String key) {
    if (failNextReads > 0) {
      failNextReads--;
      return Future<String?>.error(const R3StoreFailure('read'));
    }
    return inner.read(key);
  }

  @override
  Future<void> write(String key, String? value) {
    if (_takeUpdateFailure()) {
      return Future<void>.error(const R3StoreFailure('update'));
    }
    return inner.write(key, value);
  }

  @override
  Future<String?> update(
    String key,
    String? Function(String? current) transform,
  ) async {
    if (_takeUpdateFailure()) {
      if (transformBeforeFailing) {
        transform(await inner.read(key));
      }
      throw const R3StoreFailure('update');
    }
    return inner.update(key, transform);
  }

  @override
  Stream<String> get changes => const Stream<String>.empty();

  @override
  Future<void> close() => inner.close();
}

/// One app, one shared [MemoryKeyValueStore] and a clock following fake time.
final class R3Rig {
  /// A rig in [async]'s zone.
  R3Rig(this.async)
    : app = newFisApp(),
      memory = MemoryKeyValueStore(),
      clock = FisClock(async);

  /// The fake time of the test.
  final FakeAsync async;

  /// The app every instance belongs to, so they all share one record.
  final FirebaseApp app;

  /// The store behind every instance.
  final MemoryKeyValueStore memory;

  /// The clock of every instance.
  final FisClock clock;

  final List<FirebaseInstallations> _instances = <FirebaseInstallations>[];

  /// The store key of the installation record.
  String get key => 'installations/${app.persistenceKey}';

  /// A new view of [memory] that can fail.
  R3Store flakyStore() => R3Store(memory);

  /// A new instance talking to [fis], on [store] (default [memory] itself).
  FirebaseInstallations instance(FakeFis fis, {KeyValueStore? store}) {
    final FirebaseInstallations installations = newFisInstance(
      fis: fis,
      app: app,
      store: store ?? memory,
      clock: clock,
    );
    _instances.add(installations);
    return installations;
  }

  /// The stored record text, or null.
  String? storedText() {
    String? text;
    memory.read(key).then((String? value) => text = value);
    async.flushMicrotasks();
    return text;
  }

  /// The stored record as a JSON object, or null.
  Map<String, Object?>? stored() {
    final String? text = storedText();
    return text == null ? null : jsonDecode(text) as Map<String, Object?>;
  }

  /// Writes [text] as the record (null removes it), as another instance would.
  void put(String? text) {
    memory.write(key, text);
    async.flushMicrotasks();
  }

  /// Closes every instance and deletes the app; never awaits their futures.
  void dispose() {
    for (final FirebaseInstallations installations in _instances) {
      unawaited(installations.close());
    }
    unawaited(app.delete());
    async.flushMicrotasks();
  }
}

/// The JSON text of a stored installation record (spec 5.3 plus the owners of A5); null fields are
/// left out.
String r3Record({
  required String fid,
  required String status,
  DateTime? registrationStartedAt,
  String? registrationOwner,
  String? refreshToken,
  String? token,
  DateTime? tokenCreatedAt,
  Duration? tokenExpiresIn,
  DateTime? tokenRequestStartedAt,
  String? tokenRequestOwner,
}) => jsonEncode(<String, Object?>{
  'v': 1,
  'fid': fid,
  'status': status,
  'registrationStartedAt': ?registrationStartedAt?.millisecondsSinceEpoch,
  'registrationOwner': ?registrationOwner,
  'refreshToken': ?refreshToken,
  'token': ?token,
  'tokenCreatedAt': ?tokenCreatedAt?.millisecondsSinceEpoch,
  'tokenExpiresIn': ?tokenExpiresIn?.inMilliseconds,
  'tokenRequestStartedAt': ?tokenRequestStartedAt?.millisecondsSinceEpoch,
  'tokenRequestOwner': ?tokenRequestOwner,
});
