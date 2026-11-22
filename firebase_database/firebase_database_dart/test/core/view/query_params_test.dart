// QueryParams: the wire object and query identifier must equal the JS SDK's
// (queryParamsGetQueryObject, ObjectToUniqueKey), plus a
// port of Android QueryParamsTest.java.
import 'dart:convert';

import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/key_index.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/path_index.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/priority_index.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/value_index.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:firebase_database_dart/src/core/view/query_params.dart';
import 'package:test/test.dart';

Node n(Object? json) => nodeFromJson(json);

QueryParams get def => QueryParams.defaultParams;

QueryParams byChild(String path) => def.orderBy(PathIndex(Path(path)));

void main() {
  group('default', () {
    test('is default, loads all data, empty wire object', () {
      expect(def.isDefault, isTrue);
      expect(def.loadsAllData, isTrue);
      expect(def.index, priorityIndex);
      expect(def.toWireObject(), isEmpty);
      expect(def.toQueryIdentifier(), 'default');
    });

    test('a plain orderBy loads all data but is not the default query', () {
      final QueryParams q = byChild('age');
      expect(q.loadsAllData, isTrue);
      expect(q.isDefault, isFalse);
      expect(q.toWireObject(), <String, Object?>{'i': 'age'});
      expect(q.toQueryIdentifier(), '{"i":"age"}');
    });
  });

  group('wire object and identifier (JS)', () {
    test('protocol spec example: orderByChild startAfter limitToFirst', () {
      final QueryParams q = byChild('age').startAfter(n(30)).limitToFirst(10);
      final Map<String, Object?> wire = q.toWireObject();
      expect(wire, <String, Object?>{
        'sp': 30,
        'sn': '[MAX_NAME]',
        'sin': false,
        'l': 10,
        'vf': 'l',
        'i': 'age',
      });
      // JS key order: start, end, limit, index.
      expect(wire.keys, <String>['sp', 'sn', 'sin', 'l', 'vf', 'i']);
      expect(
        q.toQueryIdentifier(),
        '{"i":"age","l":10,"sin":false,"sn":"[MAX_NAME]","sp":30,"vf":"l"}',
      );
    });

    test('startAt with key, endAt with key', () {
      final QueryParams q = def
          .startAt(n(1), ChildKey('a'))
          .endAt(n('z'), ChildKey('b'));
      expect(q.toWireObject(), <String, Object?>{
        'sp': 1,
        'sn': 'a',
        'sin': true,
        'ep': 'z',
        'en': 'b',
        'ein': true,
      });
      expect(
        q.toQueryIdentifier(),
        '{"ein":true,"en":"b","ep":"z","sin":true,"sn":"a","sp":1}',
      );
    });

    test('limitToLast on the value index', () {
      final QueryParams q = def.orderBy(valueIndex).limitToLast(3);
      expect(q.toWireObject(), <String, Object?>{
        'l': 3,
        'vf': 'r',
        'i': '.value',
      });
      expect(q.toQueryIdentifier(), '{"i":".value","l":3,"vf":"r"}');
      expect(q.isViewFromLeft, isFalse);
    });

    test('a null bound is sent as null', () {
      final QueryParams q = def.startAt(ChildrenNode.empty);
      expect(q.toWireObject(), <String, Object?>{'sp': null, 'sin': true});
      expect(q.toQueryIdentifier(), '{"sin":true,"sp":null}');
    });

    test('numbers and strings are written as JSON.stringify does', () {
      expect(def.startAt(n(1.5)).toQueryIdentifier(), '{"sin":true,"sp":1.5}');
      expect(
        def.startAt(n(-0.25)).toQueryIdentifier(),
        '{"sin":true,"sp":-0.25}',
      );
      expect(
        def.startAt(n('a"b\\c\n\u0001')).toQueryIdentifier(),
        r'{"sin":true,"sp":"a\"b\\c\n\u0001"}',
      );
      expect(
        def.startAt(n(true)).toQueryIdentifier(),
        '{"sin":true,"sp":true}',
      );
      expect(
        byChild('a/b').toQueryIdentifier(),
        '{"i":"a/b"}',
        reason: 'child path index joined by /',
      );
      expect(def.orderBy(keyIndex).toQueryIdentifier(), '{"i":".key"}');
    });

    test('jsStringify and objectToUniqueKey match JS', () {
      expect(jsStringify(1.0), '1');
      expect(jsStringify(-0.0), '0');
      expect(jsStringify(1e21), '1e+21');
      expect(jsStringify(1e20), '100000000000000000000');
      // Above 2^53 JavaScript prints the shortest digits, not the exact binary value.
      expect(jsStringify(123456789012345683968.0), '123456789012345680000');
      expect(jsStringify(-18446744073709551616.0), '-18446744073709552000');
      expect(jsStringify(9007199254740992.0), '9007199254740992');
      expect(jsStringify(4503599627370497.0), '4503599627370497');
      expect(jsStringify(1.5e-7), '1.5e-7');
      expect(jsStringify(double.nan), 'null');
      expect(jsStringify('\ud800'), r'"\ud800"');
      expect(jsStringify('\u{1F600}'), '"\u{1F600}"');
      expect(
        objectToUniqueKey(<String, Object?>{
          'b': 1,
          'a': <String, Object?>{'d': 2, 'c': 3},
        }),
        '{"a":{"c":3,"d":2},"b":1}',
      );
      expect(objectToUniqueKey(<String, Object?>{}), '{}');
      expect(objectToUniqueKey('x'), '"x"');
    });

    test('identifier is the canonical JSON of the wire object', () {
      final QueryParams q = byChild(
        'age',
      ).startAt(n(20), ChildKey('b')).endBefore(n(30)).limitToFirst(2);
      final Map<String, Object?> sorted = Map<String, Object?>.fromEntries(
        q.toWireObject().entries.toList()..sort(
          (MapEntry<String, Object?> a, MapEntry<String, Object?> b) =>
              a.key.compareTo(b.key),
        ),
      );
      expect(q.toQueryIdentifier(), jsonEncode(sorted));
    });
  });

  group(
    'startAfter / endBefore always carry a name with sin/ein (addendum 1b)',
    () {
      test('startAfter without key on a non-key index sends sn [MAX_NAME]', () {
        for (final QueryParams base in <QueryParams>[
          def,
          def.orderBy(valueIndex),
          byChild('age'),
        ]) {
          final QueryParams q = base.startAfter(n(20));
          final Map<String, Object?> wire = q.toWireObject();
          expect(wire['sin'], false);
          expect(wire['sn'], '[MAX_NAME]');
          expect(q.indexStartName, ChildKey.max);
          expect(q.startInclusive, isFalse);
        }
      });

      test('endBefore without key on a non-key index sends en [MIN_NAME]', () {
        final QueryParams q = byChild('age').endBefore(n(30));
        final Map<String, Object?> wire = q.toWireObject();
        expect(wire['ein'], false);
        expect(wire['en'], '[MIN_NAME]');
        expect(q.indexEndName, ChildKey.min);
        expect(q.endInclusive, isFalse);
      });

      test('with a key, the key is the name', () {
        expect(
          byChild('age').startAfter(n(20), ChildKey('b')).toWireObject(),
          <String, Object?>{'sp': 20, 'sn': 'b', 'sin': false, 'i': 'age'},
        );
        expect(
          byChild('age').endBefore(n(20), ChildKey('b')).toWireObject(),
          <String, Object?>{'ep': 20, 'en': 'b', 'ein': false, 'i': 'age'},
        );
      });

      test('on the key index the value is the key: no name (JS, and the '
          'emulator honours {"i":".key","sp":"b","sin":false})', () {
        final QueryParams q = def.orderBy(keyIndex).startAfter(n('b'));
        expect(q.toWireObject(), <String, Object?>{
          'sp': 'b',
          'sin': false,
          'i': '.key',
        });
        expect(q.indexStartName, ChildKey.min);
        final QueryParams e = def.orderBy(keyIndex).endBefore(n('b'));
        expect(e.toWireObject(), <String, Object?>{
          'ep': 'b',
          'ein': false,
          'i': '.key',
        });
      });

      test(
        'startAt after startAfter is inclusive again and drops the sentinel',
        () {
          final QueryParams q = byChild('age').startAfter(n(1)).startAt(n(2));
          expect(q.toWireObject(), <String, Object?>{
            'sp': 2,
            'sin': true,
            'i': 'age',
          });
        },
      );
    },
  );

  group('integral doubles as bounds (addendum 2)', () {
    test('1.0 and 1 give the same wire object and identifier', () {
      final QueryParams asDouble = byChild(
        'n',
      ).startAt(n(1.0)).endAt(n(5.0), ChildKey('k'));
      final QueryParams asInt = byChild(
        'n',
      ).startAt(n(1)).endAt(n(5), ChildKey('k'));
      expect(asDouble.toWireObject(), asInt.toWireObject());
      expect(asDouble.toQueryIdentifier(), asInt.toQueryIdentifier());
      expect(
        asDouble.toQueryIdentifier(),
        '{"ein":true,"en":"k","ep":5,"i":"n","sin":true,"sp":1}',
      );
      expect(
        jsonEncode(asDouble.toWireObject()),
        jsonEncode(asInt.toWireObject()),
      );
      expect(asDouble, asInt);
      expect(asDouble.hashCode, asInt.hashCode);
    });
  });

  group('accessors', () {
    test('names default to MIN and MAX', () {
      final QueryParams q = def.startAt(n(1)).endAt(n(2));
      expect(q.indexStartName, ChildKey.min);
      expect(q.indexEndName, ChildKey.max);
      expect(q.indexStartValue, n(1));
      expect(q.indexEndValue, n(2));
    });

    test('limits and anchoring', () {
      final QueryParams q = def.limitToFirst(5);
      expect(q.hasLimit, isTrue);
      expect(q.limit, 5);
      expect(q.hasAnchoredLimit, isTrue);
      expect(q.isViewFromLeft, isTrue);
      expect(q.loadsAllData, isFalse);
    });

    test('isValid (Android)', () {
      expect(def.startAt(n(1)).endAt(n(2)).limitToFirst(1).isValid, isTrue);
      final QueryParams legacy = QueryParams.fromWireObject(<String, Object?>{
        'sp': 1,
        'ep': 2,
        'l': 1,
      });
      expect(legacy.hasAnchoredLimit, isFalse);
      expect(legacy.isValid, isFalse);
    });

    test('a wire limit without vf is anchored by the start (JS limit())', () {
      final QueryParams startOnly = QueryParams.fromWireObject(
        <String, Object?>{'sp': 1, 'l': 2},
      );
      expect(startOnly.isViewFromLeft, isTrue);
      expect(startOnly.toWireObject()['vf'], 'l');
      final QueryParams none = QueryParams.fromWireObject(<String, Object?>{
        'l': 2,
      });
      expect(none.isViewFromLeft, isFalse);
      expect(none.toWireObject()['vf'], 'r');
    });
  });

  group('Android QueryParamsTest', () {
    void roundTrip(QueryParams params) {
      final Map<String, Object?> json =
          jsonDecode(jsonEncode(params.toWireObject())) as Map<String, Object?>;
      final QueryParams parsed = QueryParams.fromWireObject(json);
      expect(parsed, params);
      expect(parsed.hashCode, params.hashCode);
      expect(parsed.toWireObject(), params.toWireObject());
    }

    test('startAt null is serializable', () {
      final QueryParams params = def.startAt(
        ChildrenNode.empty,
        ChildKey('key'),
      );
      expect(QueryParams.fromWireObject(params.toWireObject()), params);
      expect(params.hasStart, isTrue);
    });

    test('endAt null is serializable', () {
      final QueryParams params = def.endAt(ChildrenNode.empty, ChildKey('key'));
      expect(QueryParams.fromWireObject(params.toWireObject()), params);
      expect(params.hasEnd, isTrue);
    });

    test('query params round trip through JSON', () {
      roundTrip(def);
      roundTrip(def.startAt(n(100.0)));
      roundTrip(def.startAt(n(100.4)));
      roundTrip(def.startAt(n('one hundred')));
      roundTrip(
        def
            .startAt(n(100.0), ChildKey('a'))
            .endAt(n('one hundred'), ChildKey('b'))
            .limitToFirst(5),
      );
      roundTrip(def.startAt(n(100.0), ChildKey('a')).limitToLast(5));
    });

    test('round trip keeps exclusive bounds, sentinels and indexes', () {
      roundTrip(byChild('age').startAfter(n(20)).endBefore(n(30)));
      roundTrip(def.orderBy(keyIndex).startAfter(n('b')).limitToFirst(1));
      roundTrip(def.orderBy(valueIndex).endBefore(n(true), ChildKey('x')));
      roundTrip(byChild('a/b').limitToLast(2));
      final QueryParams parsed = QueryParams.fromWireObject(
        byChild('age').startAfter(n(20)).toWireObject(),
      );
      expect(parsed.indexStartName, ChildKey.max);
      expect(parsed.startInclusive, isFalse);
      expect(parsed.index, PathIndex(Path('age')));
    });
  });

  test('equality follows the query identifier', () {
    expect(byChild('a').limitToFirst(1), byChild('a').limitToFirst(1));
    expect(
      byChild('a').limitToFirst(1) == byChild('a').limitToLast(1),
      isFalse,
    );
    expect(byChild('a') == byChild('b'), isFalse);
    expect(def.startAt(n(1)) == def.startAfter(n(1)), isFalse);
  });
}
