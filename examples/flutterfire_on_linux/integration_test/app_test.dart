// Drives the app on the desktop device against the Firestore emulator:
//
//   flutter test integration_test/app_test.dart -d linux \
//     --dart-define=EMULATOR_PORT=8161
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterfire_on_linux/bootstrap.dart';
import 'package:flutterfire_on_linux/items_page.dart';
import 'package:flutterfire_on_linux/main.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(bootstrap);

  // Each test starts from an empty collection, so that the query has a known
  // answer.
  setUp(() async {
    final QuerySnapshot<Map<String, dynamic>> existing = await items.get();
    final WriteBatch batch = FirebaseFirestore.instance.batch();
    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
        in existing.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  });

  testWidgets('the first snapshot comes from the server', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const FlutterfireOnLinuxApp());
    await pumpUntil(tester, statusContains('isFromCache: false'));
    expect(find.text('No items yet'), findsOneWidget);
  });

  testWidgets('add, edit and delete through the UI', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const FlutterfireOnLinuxApp());
    await pumpUntil(tester, statusContains('isFromCache: false'));

    await tester.enterText(byKey('titleField'), 'hello linux');
    await tester.tap(byKey('addButton'));
    await pumpUntil(tester, find.text('hello linux'));
    // The server acknowledged the write and resolved the server timestamp.
    await pumpUntil(tester, statusContains('hasPendingWrites: false'));
    await pumpUntil(tester, find.textContaining('created 20'));

    final QuerySnapshot<Map<String, dynamic>> added = await items
        .where('title', isEqualTo: 'hello linux')
        .get(const GetOptions(source: Source.server));
    expect(added.docs, hasLength(1));
    expect(added.docs.single['createdAt'], isA<Timestamp>());
    final DocumentReference<Map<String, dynamic>> ref =
        added.docs.single.reference;

    await tester.tap(byKey('edit-hello linux'));
    await pumpUntil(tester, byKey('editField'));
    await tester.enterText(byKey('editField'), 'hello linux (edited)');
    await tester.tap(byKey('saveEdit'));
    await pumpUntil(tester, find.text('hello linux (edited)'));
    expect(find.text('hello linux'), findsNothing);
    await pumpUntil(tester, statusContains('hasPendingWrites: false'));
    final DocumentSnapshot<Map<String, dynamic>> edited = await ref.get(
      const GetOptions(source: Source.server),
    );
    expect(edited['title'], 'hello linux (edited)');

    await tester.tap(byKey('delete-hello linux (edited)'));
    await pumpUntil(tester, find.text('No items yet'));
    await pumpUntil(tester, statusContains('hasPendingWrites: false'));
    final DocumentSnapshot<Map<String, dynamic>> deleted = await ref.get(
      const GetOptions(source: Source.server),
    );
    expect(deleted.exists, isFalse);
  });

  testWidgets('a batch, a transaction and a query', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const FlutterfireOnLinuxApp());
    await pumpUntil(tester, statusContains('isFromCache: false'));

    await tester.tap(byKey('batchButton'));
    await pumpUntil(tester, statusContains('3 docs'));
    await pumpUntil(tester, statusContains('hasPendingWrites: false'));

    // batch-3 goes from priority 3 to 4 in a transaction.
    await tester.tap(byKey('bump-batch-3'));
    await pumpUntil(tester, find.textContaining('priority 4'));
    await pumpUntil(tester, statusContains('hasPendingWrites: false'));

    await tester.tap(byKey('queryButton'));
    await pumpUntil(tester, find.text('batch-3 (4), batch-2 (2)'));
    expect(find.byKey(const ValueKey<String>('error')), findsNothing);
  });
}
