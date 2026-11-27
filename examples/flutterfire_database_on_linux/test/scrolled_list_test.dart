// Why the offline step of integration_test/app_test.dart runs in its own test,
// on an empty list. The page shows the notes newest first in a ListView. Once
// the list is scrolled down to the oldest row, a new note goes in at the top,
// above the viewport, and find.text (which skips rows out of view) does not
// find it, though the row is in the list. Same list as lib/notes_page.dart,
// no Firebase.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Finder get noteList => find.descendant(
  of: find.byType(ListView),
  matching: find.byType(Scrollable),
);

void main() {
  testWidgets('a note added above a scrolled list is not found until scrolled '
      'to', (WidgetTester tester) async {
    final List<String> notes = <String>[for (int i = 0; i < 10; i++) 'note $i'];
    late StateSetter setState;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: <Widget>[
              const SizedBox(height: 200),
              Expanded(
                child: StatefulBuilder(
                  builder: (BuildContext context, StateSetter set) {
                    setState = set;
                    return ListView(
                      children: <Widget>[
                        for (final String note in notes.reversed)
                          ListTile(
                            title: Text(note),
                            subtitle: const Text('linux-1'),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.text('note 0'),
      100,
      scrollable: noteList,
    );

    setState(() => notes.add('written offline'));
    await tester.pump();
    expect(find.text('written offline'), findsNothing);
    expect(find.text('written offline', skipOffstage: false), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('written offline'),
      -100,
      scrollable: noteList,
    );
    expect(find.text('written offline'), findsOneWidget);
  });
}
