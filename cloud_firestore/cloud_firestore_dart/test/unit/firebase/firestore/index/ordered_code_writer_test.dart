import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/index/index_entry.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/index/ordered_code_writer.dart';
import 'package:fixnum/fixnum.dart';
import 'package:test/test.dart';

/// Port of ordered_code_writer.test.ts of the JS SDK (whose expected bytes
/// "are taken from the Android reference implementation"), plus the signed
/// long encoding, which only the Android writer has.
class ValueTestCase<T> {
  const ValueTestCase(this.val, this.ascString, this.descString);

  final T val;
  final String ascString;
  final String descString;
}

const List<ValueTestCase<double>> numberTestCases = <ValueTestCase<double>>[
  ValueTestCase<double>(
      double.negativeInfinity, '070fffffffffffff', 'f8f0000000000000'),
  // Number.MIN_SAFE_INTEGER
  ValueTestCase<double>(
      -9007199254740991, '083cc0000000000000', 'f7c33fffffffffffff'),
  ValueTestCase<double>(-2, '083fffffffffffffff', 'f7c000000000000000'),
  ValueTestCase<double>(-1, '08400fffffffffffff', 'f7bff0000000000000'),
  ValueTestCase<double>(-0.1, '084046666666666665', 'f7bfb999999999999a'),
  ValueTestCase<double>(-0.0, '087fffffffffffffff', 'f78000000000000000'),
  ValueTestCase<double>(0, '088000000000000000', 'f77fffffffffffffff'),
  ValueTestCase<double>(
      double.minPositive, '088000000000000001', 'f77ffffffffffffffe'),
  ValueTestCase<double>(0.1, '08bfb999999999999a', 'f74046666666666665'),
  ValueTestCase<double>(1, '08bff0000000000000', 'f7400fffffffffffff'),
  ValueTestCase<double>(2, '08c000000000000000', 'f73fffffffffffffff'),
  ValueTestCase<double>(4, '08c010000000000000', 'f73fefffffffffffff'),
  ValueTestCase<double>(8, '08c020000000000000', 'f73fdfffffffffffff'),
  ValueTestCase<double>(16, '08c030000000000000', 'f73fcfffffffffffff'),
  ValueTestCase<double>(32, '08c040000000000000', 'f73fbfffffffffffff'),
  ValueTestCase<double>(64, '08c050000000000000', 'f73fafffffffffffff'),
  ValueTestCase<double>(128, '08c060000000000000', 'f73f9fffffffffffff'),
  ValueTestCase<double>(255, '08c06fe00000000000', 'f73f901fffffffffff'),
  ValueTestCase<double>(256, '08c070000000000000', 'f73f8fffffffffffff'),
  ValueTestCase<double>(257, '08c070100000000000', 'f73f8fefffffffffff'),
  // Number.MAX_SAFE_INTEGER
  ValueTestCase<double>(
      9007199254740991, '08c33fffffffffffff', 'f73cc0000000000000'),
  ValueTestCase<double>(
      double.infinity, '08fff0000000000000', 'f7000fffffffffffff'),
  ValueTestCase<double>(double.nan, '08fff8000000000000', 'f70007ffffffffffff'),
];

const List<ValueTestCase<String>> stringTestCases = <ValueTestCase<String>>[
  ValueTestCase<String>('', '0001', 'fffe'),
  ValueTestCase<String>('\u0000', '00ff0001', 'ff00fffe'),
  ValueTestCase<String>('\u0000\u0000', '00ff00ff0001', 'ff00ff00fffe'),
  ValueTestCase<String>('abc', '6162630001', '9e9d9cfffe'),
  ValueTestCase<String>(
      'xy¢z𠜎€𠜱あ𠝹',
      '7879c2a27af0a09c8ee282acf0a09cb1e38182f0a09db90001',
      '87863d5d850f5f63711d7d530f5f634e1c7e7d0f5f6246fffe'),
  ValueTestCase<String>('¬˚ß∂∆ç', 'c2accb9ac39fe28882e28886c3a70001',
      '3d5334653c601d777d1d77793c58fffe'),
  ValueTestCase<String>('œ∑´´ß™£', 'c593e28891c2b4c2b4c39fe284a2c2a30001',
      '3a6c1d776e3d4b3d4b3c601d7b5d3d5cfffe'),
  ValueTestCase<String>(
      'πåçasdlß¬µœ∑âsldalskdåßµ∂π',
      'cf80c3a5c3a76173646cc39fc2acc2b5c593e28891c3a2736c64616c736b64c3a5c39fc2b5e28882cf800001',
      '307f3c5a3c589e8c9b933c603d533d4a3a6c1d776e3c5d8c939b9e938c949b3c5a3c603d4a1d777d307ffffe'),
  ValueTestCase<String>(
      '†¥¬´´`', 'e280a0c2a5c2acc2b4c2b4600001', '1d7f5f3d5a3d533d4b3d4b9ffffe'),
];

const List<ValueTestCase<String>> bytesTestCases = <ValueTestCase<String>>[
  ValueTestCase<String>('', '0001', 'fffe'),
  ValueTestCase<String>('00', '00ff0001', 'ff00fffe'),
  ValueTestCase<String>('0000', '00ff00ff0001', 'ff00ff00fffe'),
  ValueTestCase<String>('0001', '00ff010001', 'ff00fefffe'),
  ValueTestCase<String>('0041', '00ff410001', 'ff00befffe'),
  ValueTestCase<String>('00ff', '00ffff000001', 'ff0000fffffe'),
  ValueTestCase<String>('01', '010001', 'fefffe'),
  ValueTestCase<String>('0100', '0100ff0001', 'feff00fffe'),
  ValueTestCase<String>('6f776c', '6f776c0001', '908893fffe'),
  ValueTestCase<String>('ff', 'ff000001', '00fffffe'),
  ValueTestCase<String>('ff00', 'ff0000ff0001', '00ffff00fffe'),
  ValueTestCase<String>('ff01', 'ff00010001', '00fffefffe'),
  ValueTestCase<String>('ffff', 'ff00ff000001', '00ff00fffffe'),
  ValueTestCase<String>('ffffff', 'ff00ff00ff000001', '00ff00ff00fffffe'),
];

/// The signed number format of OrderedCode: the first bits are the sign and,
/// in unary, the length; then the value in big-endian two's complement.
/// The JS SDK has no such test (it writes every number as a double) and
/// neither has the Android SDK, so the expected bytes were computed with a
/// separate transcription of `OrderedCodeWriter.writeSignedLongAscending`.
final List<ValueTestCase<Int64>> signedLongTestCases = <ValueTestCase<Int64>>[
  ValueTestCase<Int64>(
      Int64.MIN_VALUE, '003f8000000000000000', 'ffc07fffffffffffffff'),
  ValueTestCase<Int64>(Int64(-4294967296), '0700000000', 'f8ffffffff'),
  ValueTestCase<Int64>(Int64(-8193), '1fdfff', 'e02000'),
  ValueTestCase<Int64>(Int64(-8192), '2000', 'dfff'),
  ValueTestCase<Int64>(Int64(-65), '3fbf', 'c040'),
  ValueTestCase<Int64>(Int64(-64), '40', 'bf'),
  ValueTestCase<Int64>(Int64(-1), '7f', '80'),
  ValueTestCase<Int64>(Int64(0), '80', '7f'),
  ValueTestCase<Int64>(Int64(1), '81', '7e'),
  ValueTestCase<Int64>(Int64(2), '82', '7d'),
  ValueTestCase<Int64>(Int64(63), 'bf', '40'),
  ValueTestCase<Int64>(Int64(64), 'c040', '3fbf'),
  ValueTestCase<Int64>(Int64(999), 'c3e7', '3c18'),
  ValueTestCase<Int64>(Int64(8191), 'dfff', '2000'),
  ValueTestCase<Int64>(Int64(8192), 'e02000', '1fdfff'),
  ValueTestCase<Int64>(Int64(2147483647), 'f87fffffff', '0780000000'),
  ValueTestCase<Int64>(Int64(4294967296), 'f900000000', '06ffffffff'),
  ValueTestCase<Int64>(
      Int64.MAX_VALUE, 'ffc07fffffffffffffff', '003f8000000000000000'),
];

Uint8List fromHex(String hexString) {
  final Uint8List bytes = Uint8List(hexString.length ~/ 2);
  for (int i = 0; i < hexString.length; i += 2) {
    bytes[i ~/ 2] = int.parse(hexString.substring(i, i + 2), radix: 16);
  }
  return bytes;
}

String toHex(List<int> bytes) =>
    bytes.map((int b) => b.toRadixString(16).padLeft(2, '0')).join();

({Uint8List asc, Uint8List desc}) getBytes(Object? val, {bool bytes = false}) {
  final OrderedCodeWriter ascWriter = OrderedCodeWriter();
  final OrderedCodeWriter descWriter = OrderedCodeWriter();
  if (val is double) {
    ascWriter.writeDoubleAscending(val);
    descWriter.writeDoubleDescending(val);
  } else if (val is Int64) {
    ascWriter.writeSignedLongAscending(val);
    descWriter.writeSignedLongDescending(val);
  } else if (bytes) {
    ascWriter.writeBytesAscending(fromHex(val! as String));
    descWriter.writeBytesDescending(fromHex(val as String));
  } else {
    ascWriter.writeUtf8Ascending(val! as String);
    descWriter.writeUtf8Descending(val as String);
  }
  return (asc: ascWriter.encodedBytes(), desc: descWriter.encodedBytes());
}

void verifyEncoding<T>(List<ValueTestCase<T>> testCases, {bool bytes = false}) {
  for (final ValueTestCase<T> testCase in testCases) {
    final ({Uint8List asc, Uint8List desc}) encoded =
        getBytes(testCase.val, bytes: bytes);
    expect(toHex(encoded.asc), testCase.ascString,
        reason: 'Ascending for ${testCase.val}');
    expect(toHex(encoded.desc), testCase.descString,
        reason: 'Descending for ${testCase.val}');
  }
}

void verifyOrdering<T>(List<ValueTestCase<T>> testCases, {bool bytes = false}) {
  for (int i = 0; i < testCases.length; ++i) {
    for (int j = i; j < testCases.length; ++j) {
      final T left = testCases[i].val;
      final ({Uint8List asc, Uint8List desc}) leftBytes =
          getBytes(left, bytes: bytes);
      final T right = testCases[j].val;
      final ({Uint8List asc, Uint8List desc}) rightBytes =
          getBytes(right, bytes: bytes);
      expect(compareByteArrays(leftBytes.asc, rightBytes.asc).sign,
          i == j ? 0 : -1,
          reason: 'Ascending order: $left vs $right');
      expect(compareByteArrays(leftBytes.desc, rightBytes.desc).sign,
          i == j ? 0 : 1,
          reason: 'Descending order: $left vs $right');
    }
  }
}

void main() {
  test('converts numbers to bits', () => verifyEncoding(numberTestCases));

  test('orders numbers correctly', () => verifyOrdering(numberTestCases));

  test('converts strings to bits', () => verifyEncoding(stringTestCases));

  test('orders strings correctly', () => verifyOrdering(stringTestCases));

  test('converts bytes to bits',
      () => verifyEncoding(bytesTestCases, bytes: true));

  test('orders bytes correctly',
      () => verifyOrdering(bytesTestCases, bytes: true));

  test('converts signed longs to bits',
      () => verifyEncoding(signedLongTestCases));

  test('orders signed longs correctly',
      () => verifyOrdering(signedLongTestCases));

  test('a descending encoding is the complement of the ascending one', () {
    for (final ValueTestCase<Int64> testCase in signedLongTestCases) {
      final ({Uint8List asc, Uint8List desc}) encoded = getBytes(testCase.val);
      expect(encoded.desc, encoded.asc.map((int b) => ~b & 0xff).toList(),
          reason: '${testCase.val}');
    }
  });

  test('encodes infinity', () {
    final OrderedCodeWriter writer = OrderedCodeWriter()
      ..writeInfinityAscending();
    expect(toHex(writer.encodedBytes()), 'ffff');

    writer
      ..reset()
      ..writeInfinityDescending();
    expect(toHex(writer.encodedBytes()), '0000');
  });

  test('seeds bytes', () {
    final OrderedCodeWriter writer = OrderedCodeWriter()
      ..seed(fromHex('01'))
      ..writeInfinityAscending()
      ..seed(fromHex('02'));
    expect(toHex(writer.encodedBytes()), '01ffff02');
  });

  test('grows the buffer for large values', () {
    final Uint8List large = Uint8List(5000)..fillRange(0, 5000, 0x41);
    final OrderedCodeWriter writer = OrderedCodeWriter()
      ..writeBytesAscending(large)
      ..writeBytesAscending(large);
    final Uint8List encoded = writer.encodedBytes();
    expect(encoded.length, 2 * (5000 + 2));
    expect(encoded.sublist(0, 5000), large);
    expect(encoded.sublist(5000, 5002), <int>[0x00, 0x01]);
  });

  test('encodedBytes is a copy', () {
    final OrderedCodeWriter writer = OrderedCodeWriter()
      ..writeUtf8Ascending('a');
    final Uint8List first = writer.encodedBytes();
    writer
      ..reset()
      ..writeUtf8Ascending('b');
    expect(toHex(first), '610001');
    expect(toHex(writer.encodedBytes()), '620001');
  });
}
