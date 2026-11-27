// The sequences of the recreated_app_pinned_*_test.dart files, named as in
// the reviews of the abandoned recreated-app branches (R1, R2, O1, O2, C1,
// C2, D1, W1, W2). Each returns what happened as strings, and each test file
// pins those strings for its core. A client is written as in [hosts].

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_database_dart/firebase_database_dart.dart' as fs;
import 'package:firebase_database_dart/testing.dart';
import 'package:firebase_database_dart_platform/firebase_database_dart_platform.dart';
import 'package:firebase_database_dart_platform/src/firebase_database.dart';
import 'package:flutter/foundation.dart';

import 'harness.dart';
import 'recreated_app_pinned_support.dart';

/// Sets the emulator `localhost:9000` on [database].
void emulator9000(FirebaseDatabase database) =>
    database.useDatabaseEmulator('localhost', 9000);

/// Turns persistence off on [database].
void persistenceOff(FirebaseDatabase database) =>
    database.setPersistenceEnabled(false);

/// Runs [body] with a configuration whose persistence factory returns a
/// `fakePersistence()`, then puts the previous configuration back.
Future<T> withPersistenceFactory<T>(Future<T> Function() body) async {
  final DartDatabaseConfig previous = DartFirebaseDatabase.config;
  DartFirebaseDatabase.config = DartDatabaseConfig(
    tokenProviderFor: previous.tokenProviderFor,
    appCheckProviderFor: previous.appCheckProviderFor,
    persistenceFor: (int size) => fakePersistence(),
  );
  try {
    return await body();
  } finally {
    DartFirebaseDatabase.config = previous;
  }
}

/// After [recreate] of app [name] with [then]: what a new `instanceFor`, the
/// cached object and `clientFor` give.
Future<Map<String, String>> newObjects(
  String name,
  FirebaseOptions then, {
  void Function(FirebaseDatabase database)? beforeUse,
}) async {
  final Recreated r = await recreate(name, then, beforeUse: beforeUse);
  final String url = then.databaseURL!;
  final FirebaseDatabase fresh = FirebaseDatabase.instanceFor(
    app: r.again,
    databaseURL: url,
  );
  final Map<String, String> got = <String, String>{
    'instanceFor(app: again) is the old object':
        '${identical(FirebaseDatabase.instanceFor(app: r.again), r.database)}',
    'instanceFor(app: again, databaseURL) is the old object':
        '${identical(fresh, r.database)}',
    'old client closed': '${await isClosed(r.client)}',
    'new object set': await outcome(() => fresh.ref('a').set(1)),
  };
  final Object? viaNew = await _clientOrError(
    () => FirebaseDatabaseDart.clientFor(r.again),
  );
  final Object? viaOld = await _clientOrError(
    () => FirebaseDatabaseDart.clientFor(r.old),
  );
  got['old object goOnline'] = await outcome(r.database.goOnline);
  got['clientFor(again) is clientFor(old)'] = '${identical(viaNew, viaOld)}';
  got['clientFor(again)'] = viaNew is String ? viaNew : 'client';
  got['clients'] = '${hosts()}';
  return got;
}

Future<Object?> _clientOrError(fs.FirebaseDatabase Function() get) async {
  try {
    return get();
  } on Object catch (e) {
    return describe(e);
  }
}

/// The app [name] used (the cached object X), deleted and created again
/// with [then]; [second] runs on X before X is used again (R1: the
/// emulator; R2: persistence off); then deleted and created again with
/// [third], and X used once more.
Future<String> twice(
  String name, {
  FirebaseOptions then = options,
  FirebaseOptions third = options,
  void Function(FirebaseDatabase database)? second,
}) async {
  final FirebaseApp g1 = await Firebase.initializeApp(
    name: name,
    options: options,
  );
  final FirebaseDatabase x = FirebaseDatabase.instanceFor(app: g1);
  await x.goOnline();
  await g1.delete();
  final FirebaseApp g2 = await Firebase.initializeApp(
    name: name,
    options: then,
  );
  second?.call(x);
  final String use2 = await outcome(x.goOnline);
  await g2.delete();
  await Firebase.initializeApp(name: name, options: third);
  final String use3 = await outcome(x.goOnline);
  return 'gen2 use: $use2; gen3 use: $use3; ${hosts()}';
}

/// O1: recreated with [otherDatabase]; a new object of the new database
/// with an emulator, then objects and `clientFor` of the old app object in
/// several spellings of the new database's URL.
Future<String> o1(String name) async {
  final Recreated r = await recreate(name, otherDatabase);
  await (FirebaseDatabase.instanceFor(
    app: r.again,
    databaseURL: otherUrl,
  )..useDatabaseEmulator('localhost', 9000)).goOnline();
  final fs.FirebaseDatabase now = FirebaseDatabaseDart.clientFor(
    r.again,
    databaseURL: otherUrl,
  );
  final List<String> same = <String>[];
  for (final String url in <String>[
    otherUrl,
    '$otherUrl/',
    'HTTPS://OTHER-NS.FIREBASEIO.COM',
  ]) {
    final String set = await outcome(
      () => FirebaseDatabase.instanceFor(
        app: r.old,
        databaseURL: url,
      ).ref('x').set(1),
    );
    final Object? client = await _clientOrError(
      () => FirebaseDatabaseDart.clientFor(r.old, databaseURL: url),
    );
    same.add('$url: set $set, same client ${identical(client, now)}');
  }
  return '$same; ${hosts()}';
}

/// O2: recreated with [otherDatabase]; the emulator set through an object of
/// the old app object first, then the new app object's object used.
Future<String> o2(String name) async {
  final Recreated r = await recreate(name, otherDatabase);
  FirebaseDatabase.instanceFor(
    app: r.old,
    databaseURL: '$otherUrl/',
  ).useDatabaseEmulator('localhost', 9000);
  final String use = await outcome(
    FirebaseDatabase.instanceFor(app: r.again, databaseURL: otherUrl).goOnline,
  );
  final Object? viaOld = await _clientOrError(
    () => FirebaseDatabaseDart.clientFor(r.old, databaseURL: otherUrl),
  );
  final Object? viaNew = await _clientOrError(
    () => FirebaseDatabaseDart.clientFor(r.again, databaseURL: otherUrl),
  );
  return 'use $use; same client ${identical(viaOld, viaNew)}; ${hosts()}';
}

/// C1 ([then] = [options]) and C2 ([then] = [otherDatabase]): the cached
/// object with the emulator is used, the delete is started and not awaited,
/// the app is created again before the delete finished.
Future<String> recreateBeforeDeleteFinished(
  String name,
  FirebaseOptions then,
) async {
  final FirebaseApp a1 = await Firebase.initializeApp(
    name: name,
    options: options,
  );
  final FirebaseDatabase x = FirebaseDatabase.instanceFor(app: a1)
    ..useDatabaseEmulator('localhost', 9000);
  await x.goOnline();
  final fs.FirebaseDatabase c1 = FirebaseDatabaseDart.clientFor(a1);
  bool deleted = false;
  final Future<void> deleting = a1.delete().then((_) => deleted = true);
  FirebaseApp? a2;
  final String init = await outcome(() async {
    a2 = await Firebase.initializeApp(name: name, options: then);
    return a2;
  });
  final bool deletedAtRecreate = deleted;
  await deleting;
  final bool exists = Firebase.apps.any((FirebaseApp a) => a.name == name);
  final String use = await outcome(x.goOnline);
  final String clientFor = a2 == null
      ? 'no app'
      : '${await _clientOrError(() => FirebaseDatabaseDart.clientFor(a2!)) is fs.FirebaseDatabase}';
  return 'initializeApp $init; deleted at recreate $deletedAtRecreate; '
      'app exists after $exists; old object use $use; clientFor(a2) gives '
      'a client $clientFor; first client closed ${await isClosed(c1)}; '
      '${hosts()}';
}

/// D1: two overlapping `initializeApp` calls for one name; the emulator set
/// on the object of the first app object; then the use and `clientFor` of
/// the second app object.
Future<String> d1(String name) async {
  final Future<FirebaseApp> first = Firebase.initializeApp(
    name: name,
    options: options,
  );
  final Future<FirebaseApp> second = Firebase.initializeApp(
    name: name,
    options: options,
  );
  final FirebaseApp a = await first;
  final FirebaseApp b = await second;
  final FirebaseDatabase x = FirebaseDatabase.instanceFor(app: a)
    ..useDatabaseEmulator('localhost', 9000);
  final String use = await outcome(x.goOnline);
  final Object? viaB = await _clientOrError(
    () => FirebaseDatabaseDart.clientFor(b),
  );
  final Object? viaA = await _clientOrError(
    () => FirebaseDatabaseDart.clientFor(a),
  );
  return 'use $use; clientFor(b) is clientFor(a) ${identical(viaA, viaB)}; '
      '${hosts()}';
}

/// W1 ([emulator] false) and W2 (true): an app never deleted, the plain use
/// of its `instanceFor(app:)` object, a write, a read of `clientFor`.
Future<String> neverDeleted(String name, {required bool emulator}) async {
  final FirebaseApp app = await Firebase.initializeApp(
    name: name,
    options: options,
  );
  final FirebaseDatabase x = FirebaseDatabase.instanceFor(app: app);
  if (emulator) {
    x.useDatabaseEmulator('localhost', 9000);
  }
  final String use = await outcome(x.goOnline);
  final Future<void> write = x.ref('a').set(1);
  await settle();
  server.ackLastWrite();
  final String set = await outcome(() => write);
  final String again = await outcome(x.goOnline);
  final bool same = identical(
    FirebaseDatabaseDart.clientFor(app),
    FirebaseDatabaseDart.clientFor(app, databaseURL: '$databaseUrl/'),
  );
  return 'use $use; set $set; use again $again; one client $same; ${hosts()}';
}

/// Deleted and not created again: the cached object's use.
Future<String> deletedOnly(String name) async {
  final FirebaseApp app = await Firebase.initializeApp(
    name: name,
    options: options,
  );
  final FirebaseDatabase x = FirebaseDatabase.instanceFor(app: app);
  await x.goOnline();
  final fs.FirebaseDatabase client = FirebaseDatabaseDart.clientFor(app);
  await app.delete();
  return 'closed ${await isClosed(client)}; goOnline '
      '${await outcome(x.goOnline)}; set ${await outcome(() => x.ref('a').set(1))}; '
      'ref ${await outcome(() => x.ref('a'))}; useDatabaseEmulator '
      '${await outcome(() => x.useDatabaseEmulator('localhost', 9001))}; '
      'clientFor ${await _clientOrError(() => FirebaseDatabaseDart.clientFor(app))}; '
      '${hosts()}';
}

/// How often the token and App Check provider factories were called: the
/// app used, deleted, created again with the same options, the cached
/// object used, a second database of the app used. [returnNull] makes both
/// factories return null.
Future<String> providerCalls(String name, {required bool returnNull}) async {
  final DartDatabaseConfig previous = DartFirebaseDatabase.config;
  int tokens = 0;
  int appChecks = 0;
  DartFirebaseDatabase.config = DartDatabaseConfig(
    tokenProviderFor: (FirebaseApp app) {
      tokens++;
      return returnNull ? null : FixedToken('t');
    },
    appCheckProviderFor: (FirebaseApp app) {
      appChecks++;
      return null;
    },
  );
  try {
    final FirebaseApp g1 = await Firebase.initializeApp(
      name: name,
      options: options,
    );
    final FirebaseDatabase x = FirebaseDatabase.instanceFor(app: g1);
    await x.goOnline();
    final String gen1 = 'token $tokens appCheck $appChecks';
    await FirebaseDatabase.instanceFor(
      app: g1,
      databaseURL: otherUrl,
    ).goOnline();
    final String second = 'token $tokens appCheck $appChecks';
    await g1.delete();
    await Firebase.initializeApp(name: name, options: options);
    await x.goOnline();
    return 'first client: $gen1; second database: $second; after recreate: '
        'token $tokens appCheck $appChecks';
  } finally {
    DartFirebaseDatabase.config = previous;
  }
}

/// Collects what [body] prints with `debugPrint`.
Future<List<String>> printed(Future<void> Function() body) async {
  final List<String> lines = <String>[];
  final DebugPrintCallback original = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) => lines.add('$message');
  try {
    await body();
  } finally {
    debugPrint = original;
  }
  return lines;
}
