import 'dart:convert';
import 'dart:typed_data';

// not exported by storage_engine.dart
import 'package:firebase_database_dart/src/core/snap/indexes/path_index.dart';
// not exported by storage_engine.dart
import 'package:firebase_database_dart/src/core/view/query_params.dart';
import 'package:firebase_database_dart/storage_engine.dart';
import 'package:firebase_database_dart_sqlite/src/node_codec.dart';
import 'package:firebase_database_dart_sqlite/src/tracked_query_rows.dart';
import 'package:test/test.dart';

/// 2^53 + 1: the first integer a double can not hold.
const int beyondDouble = 9007199254740993;

/// The stored text of [params].
String encodeParams(QueryParams params) => TrackedQueryRows.encodeParams(
  QuerySpec.fromPathAndWireObject(Path.empty, params.toWireObject()),
);

/// Reads the stored form of [node] back as export JSON.
Object? roundTrip(Node node) =>
    NodeCodec.decodeNode(NodeCodec.encodeNode(node)).toJson(exportFormat: true);

void main() {
  group('PathKey', () {
    test('root and nested keys have a leading and a trailing slash', () {
      expect(PathKey.of(Path.empty), '/');
      expect(PathKey.of(Path('a/b')), '/a/b/');
      expect(PathKey.toPath('/a/b/'), Path('a/b'));
      expect(PathKey.toPath('/'), Path.empty);
    });

    test('the range end replaces the trailing slash with 0', () {
      expect(PathKey.rangeEnd('/'), '0');
      expect(PathKey.rangeEnd('/a/'), '/a0');
    });

    test('selfAndAncestors lists the path first and the root last', () {
      expect(PathKey.selfAndAncestors(Path('a/b')), <String>[
        '/a/b/',
        '/a/',
        '/',
      ]);
      expect(PathKey.selfAndAncestors(Path.empty), <String>['/']);
    });
  });

  // Mutation: in NodeCodec.encodeNode, encode `node.value` (the normalised read form) instead of
  // `node.toJson(exportFormat: true)`: 1.0 comes back as an int and priorities are lost.
  group('E-N2 numbers round-trip with their type', () {
    test('an int beyond 2^53 stays that int', () {
      final Object? back = roundTrip(nodeFromJson(beyondDouble));
      expect(back, isA<int>());
      expect(back, beyondDouble);
      final Object? max = roundTrip(nodeFromJson(9223372036854775807));
      expect(max, 9223372036854775807);
    });

    test('1.0 written by a server stays a double', () {
      final Object? back = roundTrip(nodeFromJson(1.0));
      expect(back, isA<double>());
      expect(back, 1.0);
    });

    test('-0.0 keeps its sign', () {
      final Object? back = roundTrip(nodeFromJson(-0.0));
      expect(back, isA<double>());
      expect((back! as double).isNegative, isTrue);
    });

    test('numbers inside maps, priorities and merges keep their type', () {
      final Node node = nodeFromJson(<String, Object?>{
        'big': beyondDouble,
        'one': 1.0,
        'zero': -0.0,
        'int': 3,
        'tiny': 1e-300,
        '.priority': 2.0,
      });
      final Map<String, Object?> back =
          roundTrip(node)! as Map<String, Object?>;
      expect(back['big'], allOf(isA<int>(), beyondDouble));
      expect(back['one'], isA<double>());
      expect((back['zero']! as double).isNegative, isTrue);
      expect(back['int'], allOf(isA<int>(), 3));
      expect(back['tiny'], 1e-300);
      expect(back['.priority'], isA<double>());

      final CompoundWrite merge = CompoundWrite.fromValue(<String, Object?>{
        'a/b': beyondDouble,
        'c': 1.0,
      });
      final Map<String, Object?> mergeBack = NodeCodec.decodeMerge(
        NodeCodec.encodeMerge(merge),
      ).toJson(exportFormat: true);
      expect(mergeBack['/a/b'], allOf(isA<int>(), beyondDouble));
      expect(mergeBack['/c'], isA<double>());
    });

    test('unresolved server values are kept', () {
      final Node node = nodeFromJson(<String, Object?>{
        't': <String, Object?>{'.sv': 'timestamp'},
        'n': <String, Object?>{
          '.sv': <String, Object?>{'increment': 1},
        },
      });
      expect(roundTrip(node), node.toJson(exportFormat: true));
    });
  });

  // Mutation: delete the `checkNesting(bytes);` line of NodeCodec.decodeJson: the 100 000-deep
  // value reaches the recursive nodeFromJson.
  group('bounded decoding', () {
    test('nesting at the limit decodes', () {
      final String value =
          '${'[' * NodeCodec.maxNestingDepth}1${']' * NodeCodec.maxNestingDepth}';
      expect(() => NodeCodec.decodeJson(utf8.encode(value)), returnsNormally);
    });

    test('nesting beyond the limit is a FormatException', () {
      const int depth = NodeCodec.maxNestingDepth + 1;
      final String value = '${'{"a":' * depth}1${'}' * depth}';
      expect(
        () => NodeCodec.decodeJson(utf8.encode(value)),
        throwsFormatException,
      );
    });

    test('100 000 nested arrays fail without a stack overflow', () {
      final Uint8List bytes = utf8.encode('${'[' * 100000}${']' * 100000}');
      expect(() => NodeCodec.decodeNode(bytes), throwsFormatException);
    });

    test('brackets inside strings do not count', () {
      final String inner = jsonEncode('[{' * 200);
      final Object? decoded = NodeCodec.decodeJson(utf8.encode(inner));
      expect(decoded, '[{' * 200);
      final String escaped = jsonEncode('\\"[[[[');
      expect(NodeCodec.decodeJson(utf8.encode(escaped)), '\\"[[[[');
    });

    test('a merge that is not an object is a FormatException', () {
      expect(
        () => NodeCodec.decodeMerge(utf8.encode('[1, 2]')),
        throwsFormatException,
      );
    });
  });

  // Mutation: in TrackedQueryRows.encodeParams, drop `_sortedKeys(...)` and encode the wire object
  // as built: the two orders give two texts.
  group('query params', () {
    test('one text per query whatever the map order', () {
      final QueryParams params = QueryParams.defaultParams
          .orderBy(PathIndex(Path('child')))
          .startAt(nodeFromJson('startVal'), ChildKey('startKey'))
          .endAt(nodeFromJson('endVal'), ChildKey('endKey'))
          .limitToLast(5);
      final String text = encodeParams(params);
      final Map<String, Object?> decoded =
          jsonDecode(text) as Map<String, Object?>;
      final List<String> keys = decoded.keys.toList();
      expect(keys, List<String>.of(keys)..sort());
      expect(QueryParams.fromWireObject(decoded), params);
      expect(encodeParams(QueryParams.defaultParams), '{}');
    });

    // The core's number rule: an integral double within 2^53 is the same query as that int (a
    // server cancel push must match it), so 1.0 and 1 share one wire object and one stored text.
    QueryParams startAt(Object bound) =>
        QueryParams.defaultParams.startAt(nodeFromJson(bound));

    QueryParams decode(String text) =>
        QueryParams.fromWireObject(jsonDecode(text) as Map<String, Object?>);

    test('an integral double bound is stored as the core writes it', () {
      final QueryParams params = startAt(1.0);
      final String text = encodeParams(params);
      expect(decode(text), params);
      expect(text, encodeParams(startAt(1)));
    });

    test('fractional and beyond-2^53 bounds keep their exact value', () {
      for (final Object bound in <Object>[1.5, beyondDouble]) {
        final QueryParams params = startAt(bound);
        final String text = encodeParams(params);
        expect(decode(text), params, reason: '$bound');
        final Map<String, Object?> wire =
            jsonDecode(text) as Map<String, Object?>;
        expect(wire['sp'], bound, reason: '$bound');
        expect(wire['sp'].runtimeType, bound.runtimeType, reason: '$bound');
      }
    });
  });
}
