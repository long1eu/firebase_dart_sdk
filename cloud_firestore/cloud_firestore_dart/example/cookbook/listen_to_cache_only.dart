// Recipe: a listener that only reads the local cache (`ListenSource.cache`),
// and a one-time read that only asks the server (`Source.server`). A cache
// listener costs no reads on the backend and works offline; it sees this
// client's writes and whatever other reads bring into the cache.
//
// The default memory cache drops a document as soon as no listener needs it,
// so this example keeps documents with an LRU memory cache. A persistent cache
// (see offline_persistence.dart) keeps them as well.
//
// Run from cloud_firestore/cloud_firestore_dart against the emulator:
//
//     FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart run example/cookbook/listen_to_cache_only.dart

import 'dart:async';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';

import '../common.dart';

Future<void> main() async {
  // Two clients: "other" stands in for another device.
  final Firestore firestore = Firestore.instanceFor(
    app: exampleApp(),
    settings: emulatorSettings(
      cacheSettings: MemoryCacheSettings(gcSettings: MemoryLruGcSettings()),
    ),
  );
  final Firestore other = connect('other');
  final String path = scratch('settings');
  final DocumentReference<Map<String, Object?>> theme = firestore
      .collection(path)
      .doc('theme');
  await theme.set(<String, Object?>{'mode': 'light'});

  final StreamController<String> seen = StreamController<String>();
  final StreamSubscription<DocumentSnapshot<Map<String, Object?>>>
  subscription = theme
      .getSnapshotsWithOptions(
        const SnapshotListenOptions(source: ListenSource.cache),
      )
      .listen((DocumentSnapshot<Map<String, Object?>> snapshot) {
        seen.add('${snapshot['mode']}');
      });
  final StreamIterator<String> events = StreamIterator<String>(seen.stream);

  await events.moveNext();
  print('cache listener: ${events.current}');

  // A change by another client does not reach the cache listener...
  await other.collection(path).doc('theme').set(<String, Object?>{
    'mode': 'dark',
  });
  // ...until something on this client reads it from the server.
  final DocumentSnapshot<Map<String, Object?>> fresh = await theme.get(
    Source.server,
  );
  print('server read: ${fresh['mode']}');
  await events.moveNext();
  print('cache listener: ${events.current}');

  // This client's own writes reach it at once.
  await theme.update(<String, Object?>{'mode': 'sepia'});
  await events.moveNext();
  print('cache listener: ${events.current}');

  await subscription.cancel();
  await events.cancel();
  await firestore.terminate();
  await other.terminate();
}
