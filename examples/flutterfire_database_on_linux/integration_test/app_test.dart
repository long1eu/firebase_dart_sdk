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

/// Taps the field with [key], then types [text] into it. On Linux the tap on
/// Push unfocuses the note field and closes its text input connection; under
/// this binding enterText reopens it only when it targets another field than
/// the last enterText, so without the tap a second note into the same field
/// is dropped (see test/note_field_test.dart).
Future<void> typeInto(WidgetTester tester, String key, String text) async {
  await tester.tap(byKey(key));
  await tester.pump();
  await tester.enterText(byKey(key), text);
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

    await typeInto(tester, 'noteField', 'hello from the test');
    await tester.tap(byKey('pushButton'));
    await pumpUntil(tester, find.text('hello from the test'));

    // onChildChanged: edit the note through the dialog.
    final Finder edit = find.byWidgetPredicate(
      (Widget w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('edit-'),
    );
    await tester.tap(edit);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.enterText(byKey('editField'), 'edited by the test');
    await tester.tap(byKey('editSave'));
    await pumpUntil(tester, find.text('edited by the test'));
    expect(find.text('hello from the test'), findsNothing);

    // onChildAdded keeps the order and onChildRemoved drops the oldest: 11
    // notes through the field leave the 10 newest.
    for (int i = 0; i < 10; i++) {
      await typeInto(tester, 'noteField', 'note $i');
      await tester.tap(byKey('pushButton'));
      await pumpUntil(tester, find.text('note $i'));
    }
    for (int i = 0; i < 100; i++) {
      if (find.text('edited by the test').evaluate().isEmpty) {
        break;
      }
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('edited by the test'), findsNothing);
    // The list builds only the rows near the viewport; the oldest is last.
    await tester.scrollUntilVisible(
      find.text('note 0'),
      100,
      scrollable: find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('note 0'), findsOneWidget);

    await tester.tap(byKey('counterButton'));
    await pumpUntil(tester, find.text('Counter: 1'));
    final DataSnapshot counter = await FirebaseDatabase.instance
        .ref('${AppConfig.root}/counter')
        .get();
    expect(counter.value, 1);

    // ServerValue.increment(1), twice.
    await tester.tap(byKey('hitButton'));
    await pumpUntil(tester, find.text('Hits: 1'));
    await tester.tap(byKey('hitButton'));
    await pumpUntil(tester, find.text('Hits: 2'));

    // Offline: the note shows at once, the chip follows .info/connected, and
    // the note reaches the server on going online.
    await tester.tap(byKey('offlineSwitch'));
    await pumpUntil(
      tester,
      find.descendant(of: byKey('connection'), matching: find.text('Offline')),
    );
    await typeInto(tester, 'noteField', 'written offline');
    await tester.tap(byKey('pushButton'));
    await pumpUntil(tester, find.text('written offline'));
    await tester.tap(byKey('offlineSwitch'));
    await pumpUntil(tester, find.text('Connected'));
    final DataSnapshot notes = await FirebaseDatabase.instance
        .ref('${AppConfig.root}/notes')
        .get();
    expect(
      notes.children.map((DataSnapshot n) => n.child('text').value),
      contains('written offline'),
    );

    await pumpUntil(tester, find.text('Online: 1 of 1'));
    final DataSnapshot me = await FirebaseDatabase.instance
        .ref('${AppConfig.root}/presence/${AppConfig.clientId}')
        .get();
    expect(me.child('online').value, true);
  });
}
