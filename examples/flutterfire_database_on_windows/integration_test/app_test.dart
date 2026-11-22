// Drives the app on the desktop device against the Database emulator:
//
//   flutter test integration_test/app_test.dart -d windows \
//     --dart-define=EMULATOR_PORT=9100 --dart-define=ROOT=ffdb-test
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterfire_database_on_windows/bootstrap.dart';
import 'package:flutterfire_database_on_windows/main.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers.dart';

/// Pushes a note through the field and the Push button.
Future<void> pushNote(WidgetTester tester, String text) async {
  await typeInto(tester, 'noteField', text);
  await tester.tap(byKey('pushButton'));
  await pumpUntil(tester, find.text(text));
}

/// The scrollable of the list of notes (the text field has one too).
Finder get noteList => find.descendant(
  of: find.byType(ListView),
  matching: find.byType(Scrollable),
);

/// Whether the row with [upper] is shown above the row with [lower].
bool isAbove(WidgetTester tester, String upper, String lower) =>
    tester.getTopLeft(find.text(upper)).dy <
    tester.getTopLeft(find.text(lower)).dy;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(bootstrap);

  // Each test starts from an empty node, so that the counters and the
  // presence have known values.
  setUp(() => FirebaseDatabase.instance.ref(AppConfig.root).remove());

  testWidgets('connects and shows the empty list', (WidgetTester tester) async {
    await tester.pumpWidget(const FlutterfireDatabaseOnWindowsApp());
    await pumpUntil(tester, connection('Connected'));
    await pumpUntil(tester, find.text('No notes yet'));
  });

  testWidgets('push, edit and delete through the UI', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const FlutterfireDatabaseOnWindowsApp());
    await pumpUntil(tester, connection('Connected'));

    await pushNote(tester, 'hello windows');
    final List<DataSnapshot> pushed = await serverNotes('hello windows');
    expect(pushed, hasLength(1));
    expect(pushed.single.child('createdAt').value, isA<int>());
    final String key = pushed.single.key!;

    // onChildChanged: the same row shows the new text.
    await tester.tap(byKey('edit-$key'));
    await pumpUntil(tester, byKey('editField'));
    await typeInto(tester, 'editField', 'edited on windows');
    await tester.tap(byKey('editSave'));
    await pumpUntil(
      tester,
      find.descendant(
        of: byKey('note-$key'),
        matching: find.text('edited on windows'),
      ),
    );
    expect(find.text('hello windows'), findsNothing);
    expect(await serverNotes('edited on windows'), hasLength(1));

    // onChildRemoved: the row leaves the list.
    await tester.tap(byKey('delete-$key'));
    await pumpUntil(tester, find.text('No notes yet'));
    expect(byKey('note-$key'), findsNothing);
    expect((await node('notes').get()).exists, isFalse);
  });

  testWidgets('the order is kept and the oldest leaves the window of 10', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const FlutterfireDatabaseOnWindowsApp());
    await pumpUntil(tester, connection('Connected'));

    for (int i = 0; i < 11; i++) {
      await pushNote(tester, 'note $i');
    }
    await pumpUntil(tester, find.text('Last 10 notes (newest first)'));
    expect(isAbove(tester, 'note 10', 'note 9'), isTrue);
    // The list is lazy: the oldest rows are built only once scrolled to.
    await tester.scrollUntilVisible(
      find.text('note 1'),
      100,
      scrollable: noteList,
    );
    expect(isAbove(tester, 'note 2', 'note 1'), isTrue);
    await tester.drag(noteList, const Offset(0, -2000));
    await tester.pump();
    expect(find.text('note 0'), findsNothing);
  });

  testWidgets('counters, presence, and a note pushed offline', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const FlutterfireDatabaseOnWindowsApp());
    await pumpUntil(tester, connection('Connected'));

    await tester.tap(byKey('counterButton'));
    await pumpUntil(tester, find.text('Counter: 1'));
    await tester.tap(byKey('counterButton'));
    await pumpUntil(tester, find.text('Counter: 2'));
    expect((await node('counter').get()).value, 2);

    // ServerValue.increment(1), twice.
    await tester.tap(byKey('hitButton'));
    await pumpUntil(tester, find.text('Hits: 1'));
    await tester.tap(byKey('hitButton'));
    await pumpUntil(tester, find.text('Hits: 2'));
    expect((await node('hits').get()).value, 2);

    // Offline: the note shows at once, the chip follows .info/connected, and
    // the note reaches the server on going online.
    await tester.tap(byKey('offlineSwitch'));
    await pumpUntil(tester, connection('Offline'));
    await pushNote(tester, 'written offline');
    await tester.tap(byKey('offlineSwitch'));
    await pumpUntil(tester, connection('Connected'));
    expect(await serverNotes('written offline'), hasLength(1));

    // The presence entry is written again on the new connection.
    await pumpUntil(tester, find.text('Online: 1 of 1'));
    final DataSnapshot me = await node('presence/${AppConfig.clientId}').get();
    expect(me.child('online').value, true);
  });
}
