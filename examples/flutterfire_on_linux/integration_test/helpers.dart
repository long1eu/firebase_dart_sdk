import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Finder byKey(String key) => find.byKey(ValueKey<String>(key));

/// The status line, when its text contains [text].
Finder statusContains(String text) => find.byWidgetPredicate(
  (Widget widget) =>
      widget is Text &&
      widget.key == const ValueKey<String>('status') &&
      (widget.data ?? '').contains(text),
);

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
