// Hash helpers of lib/src/core/util/hash.dart.
import 'package:firebase_database_dart/src/core/util/hash.dart';
import 'package:test/test.dart';

void main() {
  test('sha1Base64', () {
    expect(sha1Base64(''), '2jmj7l5rSw0yVb/vlWAYkK/YBwk=');
    expect(sha1Base64('abc'), 'qZk+NkcGgWq6PiVxeFDCbJzQ2J0=');
  });

  test('utf8Length counts as @firebase/util stringLength', () {
    expect(utf8Length(''), 0);
    expect(utf8Length('a'), 1);
    expect(utf8Length('é'), 2);
    expect(utf8Length('€'), 3);
    expect(utf8Length('\u{1F600}'), 4);
    expect(utf8Length('a/\u{1F600}/é'), 9);
  });

  test('splitStringBySize', () {
    expect(splitStringBySize('abc', 3), <String>['abc']);
    expect(splitStringBySize('abc', 5), <String>['abc']);
    expect(splitStringBySize('abcdefg', 3), <String>['abc', 'def', 'g']);
    expect(splitStringBySize('abcdef', 3), <String>['abc', 'def']);
    expect(splitStringBySize('', 3), <String>['']);
  });

  test('stringHashV2Representation escapes only backslash and quote', () {
    expect(stringHashV2Representation('abc'), '"abc"');
    expect(stringHashV2Representation(r'a\b'), r'"a\\b"');
    expect(stringHashV2Representation('a"b'), r'"a\"b"');
    expect(stringHashV2Representation('a\nb'), '"a\nb"');
  });
}
