// Why integration_test/app_test.dart taps the note field before each
// enterText. On Linux a tap outside a text field (the Push button) unfocuses
// it and closes its text input connection. Without the mock keyboard (as
// under IntegrationTestWidgetsFlutterBinding), enterText reopens it only when
// it targets another field than the previous enterText did, so a second
// enterText into the same field is dropped: the field stays empty and the
// page's push does nothing. Same row as lib/notes_page.dart, no Firebase.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Finder byKey(String key) => find.byKey(ValueKey<String>(key));

Future<List<String>> pushTwice(
  WidgetTester tester, {
  required bool tapField,
}) async {
  final TextEditingController text = TextEditingController();
  addTearDown(text.dispose);
  final List<String> pushed = <String>[];
  // As under IntegrationTestWidgetsFlutterBinding: no mock keyboard.
  tester.testTextInput.unregister();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                key: const ValueKey<String>('noteField'),
                controller: text,
              ),
            ),
            FilledButton(
              key: const ValueKey<String>('pushButton'),
              onPressed: () {
                if (text.text.isNotEmpty) {
                  pushed.add(text.text);
                }
                text.clear();
              },
              child: const Text('Push'),
            ),
          ],
        ),
      ),
    ),
  );
  for (int i = 0; i < 2; i++) {
    if (tapField) {
      await tester.tap(byKey('noteField'));
      await tester.pump();
    }
    await tester.enterText(byKey('noteField'), 'note $i');
    await tester.tap(byKey('pushButton'));
    await tester.pump();
  }
  return pushed;
}

void main() {
  final TargetPlatformVariant linux = TargetPlatformVariant.only(
    TargetPlatform.linux,
  );

  testWidgets('without a tap on the field the second note is lost', (
    WidgetTester tester,
  ) async {
    expect(await pushTwice(tester, tapField: false), <String>['note 0']);
  }, variant: linux);

  testWidgets('a tap on the field first pushes both notes', (
    WidgetTester tester,
  ) async {
    expect(await pushTwice(tester, tapField: true), <String>[
      'note 0',
      'note 1',
    ]);
  }, variant: linux);
}
