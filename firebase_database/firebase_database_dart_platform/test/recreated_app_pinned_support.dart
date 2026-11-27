// What the recreated_app_pinned_*_test.dart files share: the fake cores, the
// options, and helpers that turn what a call did into a short string, so that
// each test pins today's behaviour of an app deleted and created again.
//
// One core per test file: firebase_core keeps the core it reads first.

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_database_dart/firebase_database_dart.dart' as fs;
import 'package:firebase_database_dart_platform/firebase_database_dart_platform.dart';
import 'package:firebase_database_dart_platform/src/firebase_database.dart';

import 'harness.dart';

/// The database URL of [otherDatabase].
const String otherUrl = 'https://other-ns.firebaseio.com';

/// [options] with another database URL.
const FirebaseOptions otherDatabase = FirebaseOptions(
  apiKey: 'test-api-key',
  appId: '1:1:web:1',
  messagingSenderId: '1',
  projectId: 'demo-unit',
  databaseURL: otherUrl,
);

/// [options] with another apiKey and the same database URL.
const FirebaseOptions otherKey = FirebaseOptions(
  apiKey: 'other-api-key',
  appId: '1:1:web:1',
  messagingSenderId: '1',
  projectId: 'demo-unit',
  databaseURL: databaseUrl,
);

/// Runs inside the delete of an app of [NativeLikeCore] or [WebLikeCore],
/// during the awaited platform call, before the core removes the app.
void Function(String name)? duringDelete;

/// A core like `MethodChannelFirebase` (macOS, Windows, Android, iOS): it
/// knows nothing of the `firebase_app_dart` app of the same name, refuses
/// another app of a name in use with another apiKey, databaseURL or
/// storageBucket, and stores the app after an awaited platform call, so that
/// two overlapping `initializeApp` calls for one name both succeed and the
/// second replaces the object of the first (`_initializeFirebaseAppFromMap`).
/// Deleting the default app is refused; another app is removed after an
/// awaited platform call, during which [duringDelete] runs.
class NativeLikeCore extends FirebasePlatform {
  final Map<String, _CoreApp> _apps = <String, _CoreApp>{};

  @override
  List<FirebaseAppPlatform> get apps =>
      List<FirebaseAppPlatform>.unmodifiable(_apps.values);

  @override
  Future<FirebaseAppPlatform> initializeApp({
    String? name,
    FirebaseOptions? options,
  }) async {
    final String appName = name ?? defaultFirebaseAppName;
    final _CoreApp? existing = _apps[appName];
    if (existing != null) {
      if (options!.apiKey != existing.options.apiKey ||
          options.databaseURL != existing.options.databaseURL ||
          options.storageBucket != existing.options.storageBucket) {
        throw duplicateApp(appName);
      }
      return existing;
    }
    await Future<void>.delayed(Duration.zero);
    return _apps[appName] = _CoreApp(appName, options!, () {
      _apps.remove(appName);
    });
  }

  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) =>
      _apps[name] ?? (throw noAppExists(name));
}

/// A core like `firebase_core_web` 4.2.0, whose `apps` and `app()` build a
/// new `FirebaseAppPlatform` object on every read
/// (`firebase.apps.map(_createFromJsApp)`). It knows nothing of the
/// `firebase_app_dart` app, refuses an app of a name in use with other
/// options, and removes an app after an awaited call.
class WebLikeCore extends FirebasePlatform {
  final Map<String, FirebaseOptions> _options = <String, FirebaseOptions>{};

  /// How many times [apps] was read.
  int appsReads = 0;

  FirebaseAppPlatform _of(String name) =>
      _CoreApp(name, _options[name]!, () => _options.remove(name));

  @override
  List<FirebaseAppPlatform> get apps {
    appsReads++;
    return <FirebaseAppPlatform>[
      for (final String name in _options.keys) _of(name),
    ];
  }

  @override
  Future<FirebaseAppPlatform> initializeApp({
    String? name,
    FirebaseOptions? options,
  }) async {
    final String appName = name ?? defaultFirebaseAppName;
    final FirebaseOptions? existing = _options[appName];
    if (existing != null && existing != options) {
      throw duplicateApp(appName);
    }
    _options[appName] = options!;
    return _of(appName);
  }

  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) =>
      _options.containsKey(name) ? _of(name) : throw noAppExists(name);
}

class _CoreApp extends FirebaseAppPlatform {
  _CoreApp(super.name, super.options, this._remove);

  final void Function() _remove;

  @override
  Future<void> delete() async {
    if (name == defaultFirebaseAppName) {
      throw noDefaultAppDelete();
    }
    await Future<void>.delayed(Duration.zero);
    duringDelete?.call(name);
    await Future<void>.delayed(Duration.zero);
    _remove();
  }
}

/// Every client created in the test, as `url|emulator|persistence`: `url`
/// is the `databaseURL` argument (null for the app's), `emulator` null for
/// production, `persistence` `disk` or `memory`.
List<String> hosts() => <String>[
  for (final DatabaseClientSettings s in createdClients)
    '${s.databaseUrl}|${s.emulatorHost}|'
        '${s.persistence == null ? 'memory' : 'disk'}',
];

/// The clients of [hosts] that go to production (no emulator host).
List<String> productionClients() => <String>[
  for (final String host in hosts())
    if (host.split('|')[1] == 'null') host,
];

/// What [call] did: `ok`, `pending` (accepted by an open client, which waits
/// for the fake server), or the error, as `plugin/code` for a
/// `FirebaseException` and `Type: message` (first line, cut at 60
/// characters) for others.
Future<String> outcome(FutureOr<Object?> Function() call) async {
  try {
    await Future<Object?>.sync(call).timeout(const Duration(milliseconds: 200));
    return 'ok';
  } on TimeoutException {
    return 'pending';
  } on Object catch (e) {
    return describe(e);
  }
}

/// [e] as [outcome] writes an error.
String describe(Object e) {
  if (e is FirebaseException) {
    return '${e.plugin}/${e.code}';
  }
  if (e is fs.FirebaseDatabaseException) {
    return 'client/${e.code}';
  }
  final String text = e is StateError
      ? e.message
      : e is ArgumentError
      ? '${e.message}'
      : '$e';
  final String line = text.split('\n').first;
  return '${e.runtimeType}: '
      '${line.length > 60 ? line.substring(0, 60) : line}';
}

/// What a listen of `onValue` of [ref] got in 200 ms: `event`, `error ...`,
/// `done` or `nothing`.
Future<String> listenOutcome(DatabaseReference ref) async {
  final Completer<String> got = Completer<String>();
  final StreamSubscription<DatabaseEvent> subscription;
  try {
    subscription = ref.onValue.listen(
      (_) => got.isCompleted ? null : got.complete('event'),
      onError: (Object e) async =>
          got.isCompleted ? null : got.complete('error ${describe(e)}'),
      onDone: () => got.isCompleted ? null : got.complete('done'),
    );
  } on Object catch (e) {
    return 'throws ${describe(e)}';
  }
  final String result = await got.future.timeout(
    const Duration(milliseconds: 200),
    onTimeout: () => 'nothing',
  );
  await subscription.cancel();
  return result;
}

/// Whether [client] is closed: a read fails with `database-closed` at once.
Future<bool> isClosed(fs.FirebaseDatabase client) async =>
    await outcome(() => client.ref('a').get()) == 'client/database-closed';

/// An app created with some options, its `instanceFor(app:)` object set up
/// and used (so it has a client), deleted, and created again.
typedef Recreated = ({
  FirebaseApp old,
  FirebaseDatabase database,
  fs.FirebaseDatabase client,
  FirebaseApp again,
});

/// Builds a [Recreated].
Future<Recreated> recreate(
  String name,
  FirebaseOptions then, {
  FirebaseOptions first = options,
  void Function(FirebaseDatabase database)? beforeUse,
}) async {
  final FirebaseApp old = await Firebase.initializeApp(
    name: name,
    options: first,
  );
  final FirebaseDatabase database = FirebaseDatabase.instanceFor(app: old);
  beforeUse?.call(database);
  await database.goOnline();
  final fs.FirebaseDatabase client = FirebaseDatabaseDart.clientFor(old);
  await old.delete();
  final FirebaseApp again = await Firebase.initializeApp(
    name: name,
    options: then,
  );
  return (old: old, database: database, client: client, again: again);
}

/// The calls of an object made before the delete, each run on its own as
/// the first call after the recreate.
final Map<String, FutureOr<Object?> Function(FirebaseDatabase database)>
oldObjectCalls = <String, FutureOr<Object?> Function(FirebaseDatabase)>{
  'ref': (FirebaseDatabase d) => d.ref('a'),
  'set': (FirebaseDatabase d) => d.ref('a').set(1),
  'get': (FirebaseDatabase d) => d.ref('a').get(),
  'useDatabaseEmulator same': (FirebaseDatabase d) =>
      d.useDatabaseEmulator('localhost', 9000),
  'useDatabaseEmulator other': (FirebaseDatabase d) =>
      d.useDatabaseEmulator('localhost', 9001),
  'setPersistenceEnabled(true)': (FirebaseDatabase d) =>
      d.setPersistenceEnabled(true),
  'setPersistenceEnabled(false)': (FirebaseDatabase d) =>
      d.setPersistenceEnabled(false),
  'goOnline': (FirebaseDatabase d) => d.goOnline(),
  'goOffline': (FirebaseDatabase d) => d.goOffline(),
  'purgeOutstandingWrites': (FirebaseDatabase d) => d.purgeOutstandingWrites(),
};

/// For each of [oldObjectCalls] (plus `onValue`): a new app named
/// `$prefix-<n>` recreated as [recreate] does with [then] and [beforeUse],
/// then the call on the object from before the delete, then a `goOnline` of
/// it. Gives `call -> outcome; goOnline after; clients`.
Future<Map<String, String>> oldObjectTable(
  String prefix,
  FirebaseOptions then, {
  void Function(FirebaseDatabase database)? beforeUse,
}) async {
  final Map<String, String> table = <String, String>{};
  int n = 0;
  Future<void> row(
    String call,
    Future<String> Function(FirebaseDatabase database) run,
  ) async {
    createdClients.clear();
    final Recreated r = await recreate(
      '$prefix-${n++}',
      then,
      beforeUse: beforeUse,
    );
    final String first = await run(r.database);
    final String after = await outcome(r.database.goOnline);
    table[call] = '$first; then goOnline: $after; ${hosts()}';
  }

  for (final MapEntry<String, FutureOr<Object?> Function(FirebaseDatabase)> call
      in oldObjectCalls.entries) {
    await row(call.key, (FirebaseDatabase d) => outcome(() => call.value(d)));
  }
  await row('onValue', (FirebaseDatabase d) => listenOutcome(d.ref('a')));
  return table;
}
