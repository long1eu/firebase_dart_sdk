// Recipe: an infinite list that stays live. Each page is fetched once to find
// its first and last document, then gets its own listener bounded by those two
// documents. A document added inside a page shows up in that page; pages never
// overlap and no document falls between two pages.
//
// Run from cloud_firestore/cloud_firestore_dart against the emulator:
//
//     FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart run example/cookbook/infinite_scroll.dart

import 'dart:async';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';

import '../common.dart';

/// One page of the list: its listener and the documents it shows now.
class Page {
  Page(this.number, this.end);

  final int number;

  /// The last document of the page when it was loaded; the next page starts
  /// after it.
  final DocumentSnapshot<Map<String, Object?>> end;
  List<String> ids = <String>[];
  StreamSubscription<QuerySnapshot<Map<String, Object?>>>? subscription;
}

Future<void> main() async {
  final FirebaseFirestore firestore = connect();
  final CollectionReference<Map<String, Object?>> messages = firestore
      .collection(scratch('messages'));

  final WriteBatch batch = firestore.batch();
  for (int i = 10; i <= 80; i += 10) {
    batch.set(messages.doc('m$i'), <String, Object?>{'rank': i});
  }
  await batch.commit();

  final Query<Map<String, Object?>> ordered = messages.orderBy('rank');
  const int pageSize = 3;
  final List<Page> pages = <Page>[];
  final StreamController<void> changes = StreamController<void>.broadcast();

  // Loads the next page and starts listening to it. Returns false at the end.
  Future<bool> loadNextPage() async {
    Query<Map<String, Object?>> next = ordered.limit(pageSize);
    if (pages.isNotEmpty) {
      next = next.startAfterDocument(pages.last.end);
    }
    final QuerySnapshot<Map<String, Object?>> first = await next.get();
    if (first.isEmpty) {
      return false;
    }
    final Page page = Page(pages.length + 1, first.docs.last)
      ..ids = <String>[for (final d in first) d.id];
    pages.add(page);
    // The listener is bounded by documents, not by a limit, so the page
    // grows or shrinks when documents are added to or removed from its range.
    page.subscription = ordered
        .startAtDocument(first.docs.first)
        .endAtDocument(first.docs.last)
        .snapshots()
        .listen((QuerySnapshot<Map<String, Object?>> snapshot) {
          page.ids = <String>[for (final d in snapshot) d.id];
          changes.add(null);
        });
    return first.length == pageSize;
  }

  void show(String when) {
    print(
      '$when: ${<String>[for (final p in pages) 'page ${p.number} ${p.ids}'].join(', ')}',
    );
  }

  // The user scrolls to the end three times.
  while (await loadNextPage()) {}
  show('loaded');

  // A new document lands between m40 and m50, inside page 2.
  final Future<void> seen = changes.stream.firstWhere(
    (_) => pages[1].ids.contains('m45'),
  );
  await messages.doc('m45').set(<String, Object?>{'rank': 45});
  await seen;
  show('after m45');

  for (final Page page in pages) {
    await page.subscription?.cancel();
  }
  await changes.close();
  await firestore.terminate();
}
