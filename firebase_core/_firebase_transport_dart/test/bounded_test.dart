import 'dart:convert';

import 'package:_firebase_transport_dart/_firebase_transport_dart.dart';
import 'package:test/test.dart';

/// One row of the `parseBoundedInt` table.
final class _Row {
  const _Row(
    this.label,
    this.value,
    this.expected, {
    this.min = 0,
    this.max = maxSafeInteger,
  });

  final String label;
  final Object? value;
  final int? expected;
  final int min;
  final int max;
}

final List<_Row> _rows = <_Row>[
  const _Row('JSON integer 0', 0, 0),
  const _Row('JSON integer 42', 42, 42),
  const _Row('digit string "42"', '42', 42),
  const _Row('leading zeros "007"', '007', 7),
  const _Row('1.0 (a whole double)', 1.0, 1),
  const _Row('1e3 as a number', 1e3, 1000),
  const _Row('2^53 − 1 as a number', maxSafeInteger, maxSafeInteger),
  const _Row('2^53 − 1 as text', '9007199254740991', maxSafeInteger),
  const _Row('2^53 as text', '9007199254740992', null),
  const _Row('2^53 as a double', 9007199254740992.0, null),
  const _Row('17 digits', '12345678901234567', null),
  const _Row('1.5', 1.5, null),
  const _Row('-1 (below min 0)', -1, null),
  const _Row('"-1"', '-1', null),
  const _Row('"+1"', '+1', null),
  const _Row('" 1"', ' 1', null),
  const _Row('"1 "', '1 ', null),
  const _Row('"\\t1"', '\t1', null),
  const _Row('empty string', '', null),
  const _Row('hex "0x10"', '0x10', null),
  const _Row('exponent text "1e3"', '1e3', null),
  const _Row('fraction text "1.0"', '1.0', null),
  const _Row('Arabic-Indic digit', '١', null),
  const _Row('full-width digit', '１', null),
  const _Row('NaN', double.nan, null),
  const _Row('infinity', double.infinity, null),
  const _Row('-infinity', double.negativeInfinity, null),
  const _Row('true', true, null),
  const _Row('null', null, null),
  const _Row('a list', <int>[1], null),
  const _Row('a map', <String, int>{'a': 1}, null),
  const _Row('min inclusive', 10, 10, min: 10, max: 20),
  const _Row('max inclusive', 20, 20, min: 10, max: 20),
  const _Row('above max', 21, null, min: 10, max: 20),
  const _Row('below min', 9, null, min: 10, max: 20),
  const _Row('"21" above max', '21', null, min: 10, max: 20),
  const _Row('negative number in a negative range', -5, -5, min: -10, max: 0),
  const _Row(
    '"-5" stays refused in a negative range (no signs)',
    '-5',
    null,
    min: -10,
    max: 0,
  ),
  const _Row(
    '2147483647 within int32 bounds',
    2147483647,
    2147483647,
    max: 2147483647,
  ),
  const _Row(
    '2147483648 above int32 bounds',
    2147483648,
    null,
    max: 2147483647,
  ),
];

void main() {
  group('parseBoundedInt, the same on the VM, dart2js and dart2wasm', () {
    for (final _Row row in _rows) {
      test('${row.label} → ${row.expected}', () {
        expect(
          parseBoundedInt(row.value, min: row.min, max: row.max),
          row.expected,
        );
      });
    }

    final Map<String, int?> decoded = <String, int?>{
      '1e400': null,
      '-1e400': null,
      '2147483647': 2147483647,
      '1.0': 1,
      '1e2': 100,
      '-0': 0,
      '0.5': null,
      '9007199254740993': null,
    };
    for (final MapEntry<String, int?> entry in decoded.entries) {
      test('JSON ${entry.key} as decoded by jsonDecode → ${entry.value}', () {
        expect(
          parseBoundedInt(jsonDecode(entry.key), min: 0, max: maxSafeInteger),
          entry.value,
        );
      });
    }
  });
}
