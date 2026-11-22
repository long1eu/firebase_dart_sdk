// Server value resolution (JS core/util/ServerValues.ts, Android core/ServerValues.java).
import 'package:firebase_database_dart/src/core/compound_write.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/leaf_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:firebase_database_dart/src/core/util/server_values.dart';
import 'package:firebase_database_dart/src/core/write_id.dart';
import 'package:test/test.dart';

const Map<String, Object?> timestamp = <String, Object?>{'.sv': 'timestamp'};

Map<String, Object?> increment(num delta) => <String, Object?>{
  '.sv': <String, Object?>{'increment': delta},
};

final Map<String, Object?> serverValues = generateServerValues(timestamp: 1234);

Object resolveAgainst(Object value, Object? existing) =>
    resolveDeferredLeafValue(
      value,
      ExistingValueProvider(nodeFromJson(existing)),
      serverValues,
    );

void main() {
  test('generateServerValues holds the timestamp', () {
    expect(generateServerValues(timestamp: 42), <String, Object?>{
      'timestamp': 42,
    });
  });

  group('resolveDeferredLeafValue', () {
    test('plain values are returned as is', () {
      expect(resolveAgainst('x', null), 'x');
      expect(resolveAgainst(3, null), 3);
      expect(resolveAgainst(true, null), true);
    });

    test('timestamp resolves to the server time', () {
      expect(resolveAgainst(timestamp, null), 1234);
    });

    test('increment adds to an existing number', () {
      expect(resolveAgainst(increment(2), 40), 42);
      expect(resolveAgainst(increment(0.5), 1), 1.5);
      expect(resolveAgainst(increment(0.5), 0.5), 1);
    });

    test('increment of a missing or non-number value is the delta', () {
      expect(resolveAgainst(increment(5), null), 5);
      expect(resolveAgainst(increment(5), 'str'), 5);
      expect(resolveAgainst(increment(5), <String, Object?>{'a': 1}), 5);
    });

    test('integer increments stay integral within 2^53', () {
      final Object result = resolveAgainst(increment(1), 9007199254740990);
      expect(result, 9007199254740991);
      expect(result, isA<int>());
    });

    test('integer increments beyond 2^53 fall to double, as JS', () {
      final Object result = resolveAgainst(increment(2), 9007199254740991);
      // JS: 9007199254740991 + 2 === 9007199254740992 (doubles).
      expect(result, 9007199254740992.0);
      expect((result as num).toDouble(), 9007199254740991.0 + 2.0);
    });

    test('unknown server values are left unchanged', () {
      final Map<String, Object?> unknown = <String, Object?>{'.sv': 'other'};
      expect(identical(resolveAgainst(unknown, null), unknown), isTrue);
      final Map<String, Object?> badDelta = <String, Object?>{
        '.sv': <String, Object?>{'increment': 'x'},
      };
      expect(identical(resolveAgainst(badDelta, null), badDelta), isTrue);
    });
  });

  group('resolveDeferredValueSnapshot', () {
    test('resolves nested server values', () {
      final Node node = nodeFromJson(<String, Object?>{
        'a': timestamp,
        'b': <String, Object?>{'c': increment(1)},
        'd': 'plain',
      });
      final Node existing = nodeFromJson(<String, Object?>{
        'b': <String, Object?>{'c': 10},
      });
      final Node resolved = resolveDeferredValueSnapshot(
        node,
        existing,
        serverValues,
      );
      expect(resolved.toJson(), <String, Object?>{
        'a': 1234,
        'b': <String, Object?>{'c': 11},
        'd': 'plain',
      });
    });

    test('resolves a server value priority', () {
      final Node node = nodeFromJson(<String, Object?>{
        '.value': 'v',
        '.priority': timestamp,
      });
      final Node resolved = resolveDeferredValueSnapshot(
        node,
        ChildrenNode.empty,
        serverValues,
      );
      expect(resolved.priority, nodeFromJson(1234));
      expect((resolved as LeafNode).value, 'v');
    });

    test('a node without server values is returned as is', () {
      final Node node = nodeFromJson(<String, Object?>{'a': 1, 'b': 'x'});
      expect(
        identical(
          resolveDeferredValueSnapshot(node, ChildrenNode.empty, serverValues),
          node,
        ),
        isTrue,
      );
    });
  });

  group('resolveDeferredValueTree and Merge', () {
    test('reads existing data lazily at the right path', () {
      final List<Path> asked = <Path>[];
      Node? cache(Path path, List<WriteId> exclude) {
        asked.add(path);
        return path == Path('counter') ? nodeFromJson(7) : null;
      }

      final Node resolved = resolveDeferredValueTree(
        Path('counter'),
        nodeFromJson(increment(3)),
        cache,
        serverValues,
      );
      expect(resolved, nodeFromJson(10));
      expect(asked, <Path>[Path('counter')]);

      final Node untouched = resolveDeferredValueTree(
        Path('x'),
        nodeFromJson('plain'),
        cache,
        serverValues,
      );
      expect(untouched, nodeFromJson('plain'));
      expect(asked, hasLength(1), reason: 'no read without a server value');
    });

    test('a null cache counts as empty', () {
      final Node resolved = resolveDeferredValueTree(
        Path('a'),
        nodeFromJson(increment(4)),
        (Path path, List<WriteId> exclude) => null,
        serverValues,
      );
      expect(resolved, nodeFromJson(4));
    });

    test('merge resolves each write against its own path', () {
      final CompoundWrite merge = CompoundWrite.fromValue(<String, Object?>{
        'a': increment(1),
        'b/c': timestamp,
      });
      final CompoundWrite resolved = resolveDeferredValueMerge(
        merge,
        Path('root'),
        (Path path, List<WriteId> exclude) =>
            path == Path('root/a') ? nodeFromJson(5) : null,
        serverValues,
      );
      expect(resolved.getCompleteNode(Path('a')), nodeFromJson(6));
      expect(resolved.getCompleteNode(Path('b/c')), nodeFromJson(1234));
    });
  });
}
