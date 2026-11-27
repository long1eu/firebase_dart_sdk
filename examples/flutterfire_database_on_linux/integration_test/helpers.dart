import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterfire_database_on_linux/bootstrap.dart';

Finder byKey(String key) => find.byKey(ValueKey<String>(key));

/// The connection chip, when it shows [label] (`Connected` or `Offline`).
Finder connection(String label) =>
    find.descendant(of: byKey('connection'), matching: find.text(label));

/// A reference under the app's root node.
DatabaseReference node(String path) =>
    FirebaseDatabase.instance.ref('${AppConfig.root}/$path');

/// The notes on the server whose text is [text], read with `get()`.
Future<List<DataSnapshot>> serverNotes(String text) async {
  final DataSnapshot notes = await node('notes').get();
  return notes.children
      .where((DataSnapshot n) => n.child('text').value == text)
      .toList();
}

/// Types [text] into the field [key], tapping it first. On Linux a tap on a
/// button takes the focus from the field and closes its text input
/// connection; the integration binding has no mock keyboard, so the tester
/// still believes the field is connected, and `enterText` into the same field
/// again is dropped (see test/note_field_test.dart). The tap reopens the
/// connection.
Future<void> typeInto(WidgetTester tester, String key, String text) async {
  await tester.tap(byKey(key));
  await tester.pump();
  await tester.enterText(byKey(key), text);
}

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
  final Iterable<Text> status = find
      .byKey(const ValueKey<String>('status'))
      .evaluate()
      .map((Element e) => e.widget as Text);
  fail(
    'Timed out waiting for $finder; status line: '
    '${status.map((Text t) => t.data).join()}',
  );
}
