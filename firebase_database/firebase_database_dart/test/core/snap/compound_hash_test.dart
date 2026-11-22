// Port of Android CompoundHashTest.java, plus the vectors measured against the emulator
// (from_boss/rtdb_emulator_probe.md, "Addendum 3", part D).
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/compound_hash.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:firebase_database_dart/src/core/util/hash.dart';
import 'package:test/test.dart';

bool neverSplit(CompoundHashBuildState state) => false;

SplitStrategy splitAtPaths(List<String> paths) {
  final List<Path> pathList = paths.map(Path.new).toList();
  return (CompoundHashBuildState state) => pathList.contains(state.currentPath);
}

void assertWithinPercent(int expected, int actual, double percent) {
  final double lower = expected * (1 - percent / 100);
  final double upper = expected * (1 + percent / 100);
  expect(actual, greaterThan(lower));
  expect(actual, lessThan(upper));
}

void main() {
  test('empty node yields empty hash', () {
    final CompoundHash hash = CompoundHash.fromNode(ChildrenNode.empty);
    expect(hash.posts, isEmpty);
    expect(hash.hashes, <String>['']);
  });

  test('compound hash is always followed by empty hash', () {
    final Node node = nodeFromJson(<String, Object?>{'foo': 'bar'});
    final CompoundHash hash = CompoundHash.fromNode(node, neverSplit);
    expect(hash.posts, <Path>[Path('foo')]);
    expect(hash.hashes, <String>[sha1Base64('("foo":(string:"bar"))'), '']);
  });

  test('compound hash can split at priority', () {
    final Node node = nodeFromJson(<String, Object?>{
      'foo': <String, Object?>{
        '!beforePriority': 'before',
        '.priority': 'prio',
        'afterPriority': 'after',
      },
      'qux': 'qux',
    });
    final CompoundHash hash = CompoundHash.fromNode(
      node,
      splitAtPaths(<String>['foo/.priority']),
    );
    final String firstHash = sha1Base64(
      '("foo":("!beforePriority":(string:"before"),".priority":(string:"prio")))',
    );
    final String secondHash = sha1Base64(
      '("foo":("afterPriority":(string:"after")),"qux":(string:"qux"))',
    );
    expect(hash.posts, <Path>[Path('foo/.priority'), Path('qux')]);
    expect(hash.hashes, <String>[firstHash, secondHash, '']);
  });

  test('hashes priority leaf nodes', () {
    final Node node = nodeFromJson(<String, Object?>{
      'foo': <String, Object?>{'.value': 'bar', '.priority': 'baz'},
    });
    final CompoundHash hash = CompoundHash.fromNode(node, neverSplit);
    expect(hash.posts, <Path>[Path('foo')]);
    expect(hash.hashes, <String>[
      sha1Base64('("foo":(priority:string:"baz":string:"bar"))'),
      '',
    ]);
  });

  test('hashing follows Firebase key semantics', () {
    final Node node = nodeFromJson(<String, Object?>{
      '1': 'one',
      '2': 'two',
      '10': 'ten',
    });
    // 10 is after 2 in Firebase key order, but before it in string order.
    final CompoundHash hash = CompoundHash.fromNode(
      node,
      splitAtPaths(<String>['2']),
    );
    expect(hash.posts, <Path>[Path('2'), Path('10')]);
    expect(hash.hashes, <String>[
      sha1Base64('("1":(string:"one"),"2":(string:"two"))'),
      sha1Base64('("10":(string:"ten"))'),
      '',
    ]);
  });

  test('hashing on child boundaries works', () {
    final Node node = nodeFromJson(<String, Object?>{
      'bar': <String, Object?>{'deep': 'value'},
      'foo': <String, Object?>{'other-deep': 'value'},
    });
    final CompoundHash hash = CompoundHash.fromNode(
      node,
      splitAtPaths(<String>['bar/deep']),
    );
    expect(hash.posts, <Path>[Path('bar/deep'), Path('foo/other-deep')]);
    expect(hash.hashes, <String>[
      sha1Base64('("bar":("deep":(string:"value")))'),
      sha1Base64('("foo":("other-deep":(string:"value")))'),
      '',
    ]);
  });

  test('commas are set for nested children', () {
    final Node node = nodeFromJson(<String, Object?>{
      'bar': <String, Object?>{'deep': 'value'},
      'foo': <String, Object?>{'other-deep': 'value'},
    });
    final CompoundHash hash = CompoundHash.fromNode(node, neverSplit);
    expect(hash.posts, <Path>[Path('foo/other-deep')]);
    expect(hash.hashes, <String>[
      sha1Base64(
        '("bar":("deep":(string:"value")),"foo":("other-deep":(string:"value")))',
      ),
      '',
    ]);
  });

  test('quoted strings and keys', () {
    final Node node = nodeFromJson(<String, Object?>{
      r'"\"\': r'"\"\',
      '"': r'\',
    });
    final CompoundHash hash = CompoundHash.fromNode(node, neverSplit);
    expect(hash.posts, <Path>[
      Path.fromKeys(<ChildKey>[ChildKey(r'"\"\')]),
    ]);
    expect(hash.hashes, <String>[
      sha1Base64(r'("\"":(string:"\\"),"\"\\\"\\":(string:"\"\\\"\\"))'),
      '',
    ]);
  });

  test('numbers and booleans use the V1 text', () {
    final Node node = nodeFromJson(<String, Object?>{'a': 1, 'b': true});
    final CompoundHash hash = CompoundHash.fromNode(node, neverSplit);
    expect(
      hash.hashes.first,
      sha1Base64('("a":(number:3ff0000000000000),"b":(boolean:true))'),
    );
  });

  test('default split has sensible amount of hashes', () {
    Node node10k = ChildrenNode.empty;
    Node node100k = ChildrenNode.empty;
    Node node1M = ChildrenNode.empty;
    for (int i = 0; i < 500; i++) {
      node10k = node10k.updateImmediateChild(
        ChildKey('key-$i'),
        nodeFromJson('value'),
      );
    }
    for (int i = 0; i < 5000; i++) {
      node100k = node100k.updateImmediateChild(
        ChildKey('key-$i'),
        nodeFromJson('value'),
      );
    }
    for (int i = 0; i < 50000; i++) {
      node1M = node1M.updateImmediateChild(
        ChildKey('key-$i'),
        nodeFromJson('value'),
      );
    }
    assertWithinPercent(15, CompoundHash.fromNode(node10k).hashes.length, 10);
    assertWithinPercent(50, CompoundHash.fromNode(node100k).hashes.length, 10);
    assertWithinPercent(150, CompoundHash.fromNode(node1M).hashes.length, 10);
  });

  test('default split handles large leaf node at root', () {
    final Node leaf = nodeFromJson('x' * (50 * 1024));
    expect(CompoundHash.fromNode(leaf).hashes, hasLength(2));
  });

  group('emulator vectors (probe addendum 3, part D)', () {
    final Node ch = nodeFromJson(<String, Object?>{
      for (int i = 0; i < 10; i++) 'c$i': 'v-c$i',
    });

    test('two ranges c0..c4 and c5..c9', () {
      final CompoundHash hash = CompoundHash.fromNode(
        ch,
        splitAtPaths(<String>['c4']),
      );
      expect(hash.posts, <Path>[Path('c4'), Path('c9')]);
      expect(hash.hashes, <String>[
        '4d6YU/3zNzILkDJhvkzqyIRWRaY=',
        'ke0fHJ5hnDqBbjIwk6x7rjfH8OA=',
        '',
      ]);
    });

    test('one range over all ten children (matched by the emulator)', () {
      final CompoundHash hash = CompoundHash.fromNode(ch);
      expect(hash.posts, <Path>[Path('c9')]);
      expect(hash.hashes, <String>['XL5kD0b9INdGlWPLdBGo7ddOaXo=', '']);
    });
  });

  test('the default strategy splits a large node by itself', () {
    // 400 children of about 30 bytes: about 12 kB, threshold sqrt(12k * 100) ~ 1.1k characters.
    final Node node = nodeFromJson(<String, Object?>{
      for (int i = 0; i < 400; i++) 'child-$i': 'value-of-child-$i',
    });
    final CompoundHash hash = CompoundHash.fromNode(node);
    expect(hash.hashes.length, greaterThan(2));
    expect(hash.posts, hasLength(hash.hashes.length - 1));
    expect(hash.hashes.last, '');
    // Posts are strictly increasing leaf paths and the last one is the last leaf.
    for (int i = 1; i < hash.posts.length; i++) {
      expect(hash.posts[i - 1].compareTo(hash.posts[i]), lessThan(0));
    }
    // String keys sort as strings: 'child-99' is the last.
    expect(hash.posts.last, Path('child-99'));
  });
}
