// Drives the app on the desktop device against the Database emulator:
//
//   flutter test integration_test/app_test.dart -d linux \
//     --dart-define=EMULATOR_PORT=9100 --dart-define=ROOT=ffdb-test
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterfire_database_on_linux/bootstrap.dart';
import 'package:flutterfire_database_on_linux/main.dart';
import 'package:integration_test/integration_test.dart';

Finder byKey(String key) => find.byKey(ValueKey<String>(key));

/// Pumps frames until [finder] finds something, or fails after [timeout].
/// `pumpAndSettle` does not fit: the network answers outside the frames.
Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final DateTime end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  fail('Timed out waiting for $finder');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(bootstrap);

  // Each test starts from an empty node.
  setUp(() => FirebaseDatabase.instance.ref(AppConfig.root).remove());

  testWidgets('push a note, count with a transaction, see presence', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const FlutterfireDatabaseOnLinuxApp());
    await pumpUntil(tester, find.text('Connected'));
    await pumpUntil(tester, find.text('No notes yet'));

    await tester.enterText(byKey('noteField'), 'hello from the test');
    await tester.tap(byKey('pushButton'));
    await pumpUntil(tester, find.text('hello from the test'));

    await tester.tap(byKey('counterButton'));
    await pumpUntil(tester, find.text('Counter: 1'));
    final DataSnapshot counter = await FirebaseDatabase.instance
        .ref('${AppConfig.root}/counter')
        .get();
    expect(counter.value, 1);

    await pumpUntil(tester, find.text('Online: 1 of 1'));
    final DataSnapshot me = await FirebaseDatabase.instance
        .ref('${AppConfig.root}/presence/${AppConfig.clientId}')
        .get();
    expect(me.child('online').value, true);
  });
}
