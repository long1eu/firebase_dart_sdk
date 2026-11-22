// transformValue (FlutterFire write values to the client) and mutableCopy
// (client values to FlutterFire): pure functions, no rig.

import 'package:firebase_database_dart_platform/src/values.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('transformValue', () {
    test('stringifies non-String keys at every depth, inside lists too', () {
      final Object? out = transformValue(<Object?, Object?>{
        1: 'a',
        true: <Object?, Object?>{2.5: 'b'},
        'list': <Object?>[
          <Object?, Object?>{3: 'c'},
          4,
        ],
      });
      expect(out, <String, Object?>{
        '1': 'a',
        'true': <String, Object?>{'2.5': 'b'},
        'list': <Object?>[
          <String, Object?>{'3': 'c'},
          4,
        ],
      });
      final Map<String, Object?> map = out! as Map<String, Object?>;
      expect(map['true'], isA<Map<String, Object?>>());
      expect(
        (map['list']! as List<Object?>).first,
        isA<Map<String, Object?>>(),
      );
    });

    test('a key collision keeps the later entry', () {
      expect(
        transformValue(<Object?, Object?>{1: 'a', '1': 'b'}),
        <String, Object?>{'1': 'b'},
      );
    });

    test('keeps null values, server values, .priority and scalars', () {
      final Map<String, Object?> value = <String, Object?>{
        'gone': null,
        'at': <String, Object?>{'.sv': 'timestamp'},
        'n': <String, Object?>{'.value': 1, '.priority': 2},
        's': 'x',
        'b': false,
        'd': 1.5,
      };
      expect(transformValue(value), value);
      expect(transformValue(null), isNull);
      expect(transformValue(7), 7);
      expect(transformValue('s'), 's');
    });

    test('returns a fresh structure the caller may change afterwards', () {
      final Map<String, Object?> inner = <String, Object?>{'x': 1};
      final Map<String, Object?> input = <String, Object?>{'inner': inner};
      final Map<String, Object?> out =
          transformValue(input)! as Map<String, Object?>;
      inner['x'] = 2;
      expect(out, <String, Object?>{
        'inner': <String, Object?>{'x': 1},
      });
      expect(out, isNot(same(input)));
    });
  });

  group('mutableCopy', () {
    test('copies unmodifiable maps and lists into mutable native types', () {
      final Map<String, Object?> client = Map<String, Object?>.unmodifiable(
        <String, Object?>{
          'a': List<Object?>.unmodifiable(<Object?>[1, null, 'x']),
          'b': Map<String, Object?>.unmodifiable(<String, Object?>{'c': true}),
        },
      );
      final Object? copy = mutableCopy(client);
      expect(copy, isA<Map<Object?, Object?>>());
      expect(copy, isNot(isA<Map<String, Object?>>()));
      final Map<Object?, Object?> map = copy! as Map<Object?, Object?>;
      expect(map['a'], isA<List<Object?>>());
      expect(map['b'], isA<Map<Object?, Object?>>());
      map['new'] = 1;
      (map['a']! as List<Object?>).add(2);
      (map['b']! as Map<Object?, Object?>)['d'] = 3;
      expect(client['a'], <Object?>[1, null, 'x']);
      expect(client.containsKey('new'), isFalse);
    });

    test('keeps the key order of the client', () {
      final Map<Object?, Object?> copy =
          mutableCopy(<String, Object?>{'2': 0, '10': 1, 'a': 2})!
              as Map<Object?, Object?>;
      expect(copy.keys, <Object?>['2', '10', 'a']);
    });

    test('returns scalars and null as they are', () {
      expect(mutableCopy(null), isNull);
      expect(mutableCopy(1), 1);
      expect(mutableCopy(1.5), 1.5);
      expect(mutableCopy('s'), 's');
      expect(mutableCopy(true), isTrue);
    });
  });
}
