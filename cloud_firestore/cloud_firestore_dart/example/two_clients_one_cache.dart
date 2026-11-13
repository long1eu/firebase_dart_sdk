// Two clients on one cache: the main isolate and a background isolate open
// the same SQLite file (the same app name, project and database).
//
// One client at a time, the primary, holds the lease and talks to the
// backend. A client that opens a cache whose lease is held takes it over (a
// Flutter hot restart works that way), so here the background isolate becomes
// primary and the main isolate becomes a secondary: it reports itself offline,
// answers from the cache and keeps its writes pending. When the background
// isolate terminates, the main isolate takes the lease back and sends them.
//
// A background isolate that must be online at the same time as the main one
// should not share the cache: give it its own app name (see
// docs/guides/multiple_clients.md).
//
//     FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart run example/two_clients_one_cache.dart

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';

import 'common.dart';
import 'sqlite_database.dart';

Future<void> main() async {
  final Directory directory = Directory.systemTemp.createTempSync(
    'firestore_two_clients_',
  );
  final String notes = scratch('notes');

  final Firestore firestore = _open(directory);
  final CollectionReference<Map<String, Object?>> collection = firestore
      .collection(notes);
  await collection.doc('main').set(<String, Object?>{'from': 'main isolate'});
  print('main isolate: wrote online');

  // Every change of `isFromCache` of this listener shows whether the main
  // isolate is online, that is, primary.
  final StreamController<bool> online = StreamController<bool>();
  final StreamSubscription<QuerySnapshot<Map<String, Object?>>> listener =
      collection
          .getSnapshots(MetadataChanges.include)
          .listen(
            (QuerySnapshot<Map<String, Object?>> snapshot) =>
                online.add(!snapshot.metadata.isFromCache),
          );
  final StreamIterator<bool> onlineStates = StreamIterator<bool>(
    online.stream.distinct(),
  );
  await _waitFor(onlineStates, true);

  // The background isolate opens the same file and takes the lease.
  final ReceivePort fromBackground = ReceivePort();
  final StreamIterator<Object?> messages = StreamIterator<Object?>(
    fromBackground,
  );
  await Isolate.spawn(_background, <Object?>[
    fromBackground.sendPort,
    directory.path,
    notes,
  ]);
  await messages.moveNext();
  final SendPort toBackground = messages.current! as SendPort;
  await messages.moveNext();
  print('background isolate: ${messages.current}');

  // The main isolate notices at its next lease refresh (within 4 seconds).
  await _waitFor(onlineStates, false);
  print('main isolate: secondary, answers from the cache');

  // What the primary stored is in the file, so the secondary reads it.
  final DocumentSnapshot<Map<String, Object?>> written = await collection
      .doc('background')
      .get(Source.cache);
  print('main isolate: reads ${written.data} from the cache');

  // A write of a secondary is stored, but not sent while it is secondary.
  bool acknowledged = false;
  final Future<void> pending = collection
      .doc('main')
      .update(<String, Object?>{'from': 'main isolate, while secondary'})
      .then((_) => acknowledged = true);
  await Future<void>.delayed(const Duration(seconds: 1));
  print('main isolate: write acknowledged while secondary: $acknowledged');

  // When the background isolate terminates, it gives up the lease; the main
  // isolate takes it at its next refresh, goes online and sends the write.
  toBackground.send('terminate');
  await messages.moveNext();
  print('background isolate: ${messages.current}');
  await _waitFor(onlineStates, true);
  await pending;
  print('main isolate: primary again, write acknowledged: $acknowledged');

  await listener.cancel();
  await onlineStates.cancel();
  await online.close();
  await messages.cancel();
  await firestore.terminate();
  directory.deleteSync(recursive: true);
}

/// The background isolate: opens the cache in [args] and writes a document,
/// then waits until it is told to terminate.
Future<void> _background(List<Object?> args) async {
  final SendPort toMain = args[0]! as SendPort;
  final Directory directory = Directory(args[1]! as String);
  final String notes = args[2]! as String;

  final ReceivePort commands = ReceivePort();
  toMain.send(commands.sendPort);

  final Firestore firestore = _open(directory);
  await firestore.collection(notes).doc('background').set(<String, Object?>{
    'from': 'background isolate',
  });
  toMain.send('took the lease and wrote online');

  await commands.first;
  await firestore.terminate();
  toMain.send('terminated');
}

/// A Firestore instance with a SQLite cache in [directory]. Both isolates
/// call it with the same (default) app name, so they open the same file.
Firestore _open(Directory directory) {
  return Firestore.instanceFor(
    app: exampleApp(),
    openDatabase: sqliteOpener(directory),
    settings: emulatorSettings(cacheSettings: PersistentCacheSettings()),
  );
}

Future<void> _waitFor(StreamIterator<bool> states, bool wanted) async {
  while (await states.moveNext()) {
    if (states.current == wanted) {
      return;
    }
  }
  throw StateError(
    'The listener ended before it was ${wanted ? 'on' : 'off'}line.',
  );
}
