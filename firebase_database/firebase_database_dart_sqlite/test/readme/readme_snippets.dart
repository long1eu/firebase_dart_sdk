// GENERATED from the README files by test/readme_snippets_test.dart. Do not edit: change the
// README and regenerate (see that file).
//
// This file is only analyzed, never run.

// ignore_for_file: type=lint, unused_local_variable, unused_import
// ignore_for_file: unused_element

import 'dart:io';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:firebase_database_dart/firebase_database_dart.dart';
import 'package:firebase_database_dart_sqlite/firebase_database_dart_sqlite.dart';

late FirebaseApp app;
late FirebaseDatabase database;
late DatabaseReference ref;

// ../firebase_database_dart/README.md:122
Future<void> clientReadmeLine122() async {
  final FirebaseApp projectApp = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: '<the Web API key of the project>',
      appId: '1:1234567890:dart:example',
      projectId: 'my-project',
    ),
  );
  // https://my-project-default-rtdb.firebaseio.com
  final FirebaseDatabase db = FirebaseDatabase(projectApp);
  // A database in another region, or a second database, has its own URL.
  final FirebaseDatabase other = FirebaseDatabase(
    projectApp,
    databaseUrl: 'https://my-project-other.europe-west1.firebasedatabase.app',
  );
  await other.close();
  await db.close();
}

// ../firebase_database_dart/README.md:155
Future<void> clientReadmeLine155() async {
  final DatabaseReference ada = database.ref('users/ada');

  await ada.set(<String, Object?>{'name': 'Ada', 'age': 36, 'city': 'London'});
  await ada.update(<String, Object?>{'age': 37, 'city': null}); // null removes the child

  final DataSnapshot snapshot = await ada.get();
  if (snapshot.value case {'name': String name, 'age': num age}) {
    print('$name is $age');
  }
  print(snapshot.exists); // false for a location with no data

  final DatabaseReference message = database.ref('messages').push(); // a new key, ordered by time
  await message.set(<String, Object?>{'text': 'hello', 'at': ServerValue.timestamp});
  print(message.key);

  await ada.remove(); // set(null)
}

// ../firebase_database_dart/README.md:208
Future<void> clientReadmeLine208() async {
  final DatabaseReference items = database.ref('items');

  final subscription = items.onValue.listen((DatabaseEvent event) {
    print('${event.snapshot.children.length} children');
  });
  items.onChildAdded.listen((e) => print('added ${e.snapshot.key} after ${e.previousChildKey}'));
  items.onChildChanged.listen((e) => print('changed ${e.snapshot.key}'));
  items.onChildMoved.listen((e) => print('moved ${e.snapshot.key}'));
  items.onChildRemoved.listen((e) => print('removed ${e.snapshot.key}'));

  // One stream of all four child events, in the order they happened.
  items.onChildEvents.listen((e) => print('${e.type.name} ${e.snapshot.key}'));

  final DatabaseEvent first = await items.once(); // first value event, then the listener is gone
  print(first.snapshot.value);

  await subscription.cancel();
}

// ../firebase_database_dart/README.md:245
Future<void> clientReadmeLine245() async {
  final Query players = database.ref('players');

  // Results are ascending; for a top three take the last three and reverse them.
  final Query top = players.orderByChild('score').limitToLast(3);
  final DatabaseEvent event = await top.once();
  for (final DataSnapshot child in event.snapshot.children.toList().reversed) {
    print('${child.key}: ${child.value}');
  }

  final Query middle = players.orderByChild('score').startAt(20).endAt(30);
  final Query after = players.orderByChild('score').startAfter(20);
  final Query red = players.orderByChild('team').equalTo('red');
  final Query keys = players.orderByKey().startAt('b').endAt('c');
  for (final Query query in <Query>[middle, after, red, keys]) {
    print((await query.once()).snapshot.children.map((DataSnapshot c) => c.key).toList());
  }

  // Order-only queries need no index in the rules, so get() works.
  final DataSnapshot sorted = await players.orderByKey().get();
  print(sorted.children.length);
}

// ../firebase_database_dart/README.md:294
Future<void> clientReadmeLine294() async {
  final TransactionResult result = await database.ref('seats').runTransaction((Object? current) {
    if (current == null) {
      return Transaction.success(null); // the first run often sees null, the client has no data yet
    }
    final num seats = current as num;
    return seats > 0 ? Transaction.success(seats - 1) : const Transaction.abort();
  });
  print('committed: ${result.committed}, value: ${result.snapshot.value}');
}

// ../firebase_database_dart/README.md:323
Future<void> clientReadmeLine323() async {
  final DatabaseReference status = database.ref('status/ada');
  // Register again at every connection: the server forgets the registrations when the
  // connection ends, and the client does not keep them across a restart.
  final presence = database.onConnected.listen((bool connected) async {
    if (!connected) {
      return;
    }
    await status.onDisconnect.set(<String, Object?>{'state': 'offline', 'at': ServerValue.timestamp});
    await status.set(<String, Object?>{'state': 'online', 'at': ServerValue.timestamp});
  });
  // ... later, to stop:
  await presence.cancel();
}

// ../firebase_database_dart/README.md:350
Future<void> clientReadmeLine350() async {
  await database.ref('post').set(<String, Object?>{
    'title': 'Hello',
    'createdAt': ServerValue.timestamp, // milliseconds since the epoch, on the server
  });

  await database.ref('views').set(ServerValue.increment(1)); // a missing or non-number value counts as 0

  print('offset: ${database.serverTimeOffset}, now on the server: ${database.estimatedServerTime}');
}

// ../firebase_database_dart/README.md:371
Future<void> clientReadmeLine371() async {
  database.onConnected.listen((bool connected) => print('connected: $connected'));
  await database.onConnected.firstWhere((bool connected) => connected);

  database.goOffline(); // synchronous; listeners keep their data, writes wait in a queue
  final Future<void> queued = database.ref('queued').set('written offline');
  database.goOnline(); // sends the queue in order
  await queued;
}

// ../firebase_database_dart/README.md:414
Future<void> clientReadmeLine414() async {
  // Before the FirebaseDatabase is constructed: it reads the app's providers then.
  final FirebaseUserAuth auth = await FirebaseUserAuth.forApp(app);
  await auth.signInAnonymously();
  final FirebaseDatabase signedIn = FirebaseDatabase(app);
  await signedIn.close();
}

// ../firebase_database_dart/README.md:433
Future<void> clientReadmeLine433() async {
  final FirebaseDatabase asAda = FirebaseDatabase(
    app,
    emulatorHost: '127.0.0.1:9100',
    mockUserToken: mockUserTokenFor(
      'ada',
      projectId: 'demo-test',
      claims: <String, Object?>{'role': 'editor'},
    ),
  );
  await asAda.close();
}

// ../firebase_database_dart/README.md:461
Future<void> clientReadmeLine461() async {
  const String supportDirectory = '/path/to/app/support';
  final FirebaseDatabase cached = FirebaseDatabase(
    app,
    persistence: sqlitePersistence(
      '$supportDirectory/firebase_database',
      cacheSizeBytes: 20 * 1024 * 1024, // 1 MiB to 100 MiB, 10 MiB by default
    ),
  );
  print(cached.persistenceEnabled); // false when another instance owns the file

  // Only the pending writes are stored; no server data is kept on disk:
  final FirebaseDatabase writesOnly = FirebaseDatabase(
    app,
    persistence: sqlitePersistence('$supportDirectory/writes', cacheServerData: false),
  );

  await cached.close();
  await writesOnly.close();
  await clearSqlitePersistence(
    '$supportDirectory/firebase_database',
    appName: app.name,
    databaseUrl: cached.databaseUrl,
  );
}

// ../firebase_database_dart/README.md:503
Future<void> clientReadmeLine503() async {
  try {
    await ref.get();
  } on FirebaseDatabaseException catch (e) {
    switch (e.code) {
      case 'permission-denied':
        print('the rules refused the request (${e.serverStatus})');
      case 'unavailable' || 'network-error':
        print('no connection');
      default:
        print('${e.code}: ${e.message}');
    }
  }
}

// ../firebase_database_dart/README.md:542
Future<void> clientReadmeLine542() async {
  final FirebaseDatabase logged = FirebaseDatabase(
    app,
    logger: (DatabaseLogLevel level, String message) {
      if (level.index >= DatabaseLogLevel.warning.index) {
        print('[${level.name}] $message');
      }
    },
  );
  await logged.close();
}

// README.md:48
Future<void> sqliteReadmeLine48() async {
  final FirebaseDatabase cached = FirebaseDatabase(
    app,
    persistence: sqlitePersistence('/path/to/app/support/firebase_database'),
  );
  await cached.close();
}

// README.md:76
Future<void> sqliteReadmeLine76() async {
  await database.close();
  await clearSqlitePersistence(
    '/path/to/app/support/firebase_database',
    appName: app.name,
    databaseUrl: database.databaseUrl,
  );
}

// ../../docs/guides/database.md:89
Future<void> databaseGuideLine89() async {
  ref.child('private').onValue.listen(
    (DatabaseEvent event) => print(event.snapshot.value),
    onError: (Object error) {
      if (error is FirebaseDatabaseException && error.code == 'permission-denied') {
        print('the rules refused or revoked this listen; the stream has ended');
      }
    },
  );
  try {
    await ref.child('private/note').set('hello');
  } on FirebaseDatabaseException catch (e) {
    print('write refused: ${e.code} (${e.serverStatus})');
  }
}

// ../../docs/guides/database.md:190
Future<void> databaseGuideLine190() async {
  final FirebaseDatabase cached = FirebaseDatabase(
    app,
    persistence: sqlitePersistence('/var/lib/my-app/rtdb', cacheSizeBytes: 50 * 1024 * 1024),
  );
  final DatabaseReference notes = cached.ref('users/ada/notes');
  notes.onValue.listen((DatabaseEvent event) => print(event.snapshot.children.length));
  print('durable: ${cached.persistenceEnabled}');
  await cached.close();
}

// ../../docs/guides/database.md:247
Future<void> databaseGuideLine247() async {
  database.onConnected.listen((bool connected) => print('connected: $connected'));
  ProcessSignal.sigterm.watch().first.then((ProcessSignal _) async {
    await database.close();
    exit(0);
  });
}

// ../../docs/guides/database.md:278
Future<void> databaseGuideLine278() async {
  final FirebaseDatabase asAda = FirebaseDatabase(
    app,
    emulatorHost: '127.0.0.1:9100',
    mockUserToken: mockUserTokenFor('ada', projectId: 'demo-test', claims: <String, Object?>{'role': 'editor'}),
  );
  await asAda.ref('private/ada').set('hello');
  await asAda.close();
}
