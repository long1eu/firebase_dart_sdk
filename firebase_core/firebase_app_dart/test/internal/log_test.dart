import 'dart:async';

import 'package:firebase_app_dart/internal.dart';
import 'package:test/test.dart';

List<String> capture(void Function() body) {
  final List<String> lines = <String>[];
  runZoned(body,
      zoneSpecification: ZoneSpecification(
          print: (Zone self, ZoneDelegate parent, Zone zone, String line) =>
              lines.add(line)));
  return lines;
}

void main() {
  group('level', levelTests);

  group('printing', () {
    final InternalLogLevel original = Log.level;
    setUp(() => Log.level = InternalLogLevel.d);
    tearDown(() => Log.level = original);
    printingTests();
  });
}

void printingTests() {
  test('short messages are printed unchanged', () {
    final List<String> lines = capture(() => Log.d('tag', 'hello'));
    expect(lines.single, endsWith('||hello'));
  });

  test('very long messages are truncated', () {
    final String huge = 'x' * 10 * 1024 * 1024;
    final List<String> lines = capture(() => Log.d('tag', huge));
    expect(lines.single.length, lessThan(Log.maxMessageLength + 200));
    expect(lines.single, contains('<message truncated>'));
  });

  test('truncate keeps messages at the limit', () {
    final String exact = 'y' * Log.maxMessageLength;
    expect(Log.truncate(exact), exact);
    expect(Log.truncate('${exact}z'), isNot('${exact}z'));
  });
}

void levelTests() {
  final InternalLogLevel saved = Log.level;
  tearDown(() => Log.level = saved);

  test('default level is quiet (warning)', () {
    expect(InternalLogLevel.w, saved);
    expect(Log.isDebugEnabled, isFalse);
    expect(capture(() => Log.d('tag', 'x')), isEmpty);
    expect(capture(() => Log.i('tag', 'x')), isEmpty);
    expect(capture(() => Log.w('tag', 'x')), hasLength(1));
    expect(capture(() => Log.e('tag', 'x')), hasLength(1));
  });

  test('isDebugEnabled matches whether Log.d prints', () {
    for (final InternalLogLevel level in <InternalLogLevel>[
      InternalLogLevel.i,
      InternalLogLevel.d,
      InternalLogLevel.w,
      InternalLogLevel.e
    ]) {
      Log.level = level;
      expect(Log.isDebugEnabled, capture(() => Log.d('t', 'x')).isNotEmpty,
          reason: 'level ${level.compareTo(InternalLogLevel.i)}');
    }
  });
}
