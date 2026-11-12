import 'package:cloud_firestore_dart/src/firebase/firestore/util/util.dart';
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;
import 'package:test/test.dart';

void main() {
  test('small messages are described as JSON', () {
    final proto.Value value = proto.Value(stringValue: 'abc');
    expect(describeForLog(value), contains('abc'));
  });

  test('large messages are replaced by a size marker', () {
    final proto.Value value = proto.Value(stringValue: 'x' * (200 * 1024));
    final String text = describeForLog(value);
    expect(text, startsWith('<Value truncated for logging'));
    expect(text, contains('KB'));
    expect(text.length, lessThan(200));
  });
}
