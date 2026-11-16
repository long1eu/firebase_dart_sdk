// A smoke test of the part of the page that does not need a browser: the
// instance opened offline, the query of the form, and a write that stays
// pending. Runs on the Dart VM with no backend: `dart test`.

import 'dart:async';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:playground/playground.dart';
import 'package:test/test.dart';

void main() {
  test('a write shows in the listener at once and stays pending', () async {
    final FirebaseApp app = FirebaseApp.withOptions(playgroundOptions);
    final Firestore firestore = await openOffline(app);
    addTearDown(firestore.terminate);

    const QuerySpec spec = QuerySpec(
      collection: 'cities',
      whereField: 'country',
      op: WhereOp.isEqualTo,
      whereValue: 'JP',
      orderField: 'population',
      descending: true,
      limit: 10,
    );
    final StreamIterator<QuerySnapshot<Map<String, Object?>>> snapshots =
        StreamIterator<QuerySnapshot<Map<String, Object?>>>(
          spec.build(firestore).getSnapshots(MetadataChanges.include),
        );
    addTearDown(snapshots.cancel);

    expect(await snapshots.moveNext(), isTrue);
    expect(snapshots.current.isEmpty, isTrue);
    expect(snapshots.current.metadata.isFromCache, isTrue);

    final Future<void> write = firestore
        .doc('cities/tokyo')
        .set(sampleDocuments['cities/tokyo']!);
    expect(await snapshots.moveNext(), isTrue);
    final QuerySnapshot<Map<String, Object?>> snapshot = snapshots.current;
    expect(
      snapshot.docs.map((QueryDocumentSnapshot<Object?> d) => d.id),
      <String>['tokyo'],
    );
    expect(snapshot.metadata.hasPendingWrites, isTrue);
    expect(
      snapshot.getDocumentChanges(MetadataChanges.include).single.type,
      DocumentChangeType.added,
    );

    // No backend: the write is never acknowledged.
    bool done = false;
    unawaited(
      write.then((_) => done = true, onError: (Object _) => done = true),
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(done, isFalse);
  });

  test('the form shows the Dart code of its query', () {
    const QuerySpec spec = QuerySpec(
      collection: 'tasks',
      whereField: 'priority',
      op: WhereOp.isLessThan,
      whereValue: '3',
      limit: 5,
    );
    expect(
      spec.toDart(),
      "firestore\n    .collection('tasks')\n    .where('priority', isLessThan: 3)"
      '\n    .limit(5)\n    .getSnapshots(MetadataChanges.include)\n    .listen(...);',
    );
    expect(parseValue('Paris'), 'Paris');
    expect(parseValue('"Paris"'), 'Paris');
    expect(parseValue('true'), isTrue);
  });
}
