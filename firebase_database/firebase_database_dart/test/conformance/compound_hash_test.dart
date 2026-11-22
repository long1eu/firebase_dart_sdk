// Ported from the Android SDK, firebase-database/src/androidTest/java/com/google/firebase/database/snapshot/CompoundHashTest.java
// (firebase-android-sdk 2cfdd0389, Apache-2.0; an instrumented test upstream, a unit test here).
//
// Disagreement: Android hashes with `Utilities.sha1HexDigest` (hex); the iOS test and the wire
// protocol (and the skeleton: "The base64 SHA-1 of each range") use base64, so the expected values
// are `sha1Base64` of the same texts. The Android integration test
// (CompoundHashingIntegrationTest) needs a live connection and is not ported.
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/compound_hash.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/util/hash.dart';
import 'package:test/test.dart';

import 'support.dart';

bool _neverSplit(CompoundHashBuildState state) => false;

SplitStrategy _splitAtPaths(List<String> paths) {
  final pathList = [for (final path in paths) p(path)];
  return (state) => pathList.contains(state.currentPath);
}

void main() {
  test('empty node yields empty hash', () {
    final hash = CompoundHash.fromNode(emptyNode);
    expect(hash.posts, isEmpty);
    expect(hash.hashes, ['']);
  });

  test('compound hash is always followed by empty hash', () {
    final node = nq("{'foo': 'bar'}");
    final hash = CompoundHash.fromNode(node, _neverSplit);
    final expected = sha1Base64('("foo":(string:"bar"))');
    expect(hash.posts, [p('foo')]);
    expect(hash.hashes, [expected, '']);
  });

  test('compound hash can split at priority', () {
    final node = nq(
      "{'foo': {'!beforePriority': 'before', '.priority': 'prio', 'afterPriority': 'after'}, 'qux': 'qux'}",
    );
    final hash = CompoundHash.fromNode(node, _splitAtPaths(['foo/.priority']));
    final first = sha1Base64(
      '("foo":("!beforePriority":(string:"before"),".priority":(string:"prio")))',
    );
    final second = sha1Base64(
      '("foo":("afterPriority":(string:"after")),"qux":(string:"qux"))',
    );
    expect(hash.posts, [p('foo/.priority'), p('qux')]);
    expect(hash.hashes, [first, second, '']);
  });

  test('hashes priority leaf nodes', () {
    final node = nq("{'foo': {'.value': 'bar', '.priority': 'baz'}}");
    final hash = CompoundHash.fromNode(node, _neverSplit);
    final expected = sha1Base64('("foo":(priority:string:"baz":string:"bar"))');
    expect(hash.posts, [p('foo')]);
    expect(hash.hashes, [expected, '']);
  });

  test('hashing follows Firebase key semantics', () {
    final node = nq("{'1': 'one', '2': 'two', '10': 'ten'}");
    // 10 is after 2 in Firebase key semantics, but would be before 2 in string semantics.
    final hash = CompoundHash.fromNode(node, _splitAtPaths(['2']));
    final first = sha1Base64('("1":(string:"one"),"2":(string:"two"))');
    final second = sha1Base64('("10":(string:"ten"))');
    expect(hash.posts, [p('2'), p('10')]);
    expect(hash.hashes, [first, second, '']);
  });

  test('hashing on child boundaries works', () {
    final node = nq(
      "{'bar': {'deep': 'value'}, 'foo': {'other-deep': 'value'}}",
    );
    final hash = CompoundHash.fromNode(node, _splitAtPaths(['bar/deep']));
    final first = sha1Base64('("bar":("deep":(string:"value")))');
    final second = sha1Base64('("foo":("other-deep":(string:"value")))');
    expect(hash.posts, [p('bar/deep'), p('foo/other-deep')]);
    expect(hash.hashes, [first, second, '']);
  });

  test('commas are set for nested children', () {
    final node = nq(
      "{'bar': {'deep': 'value'}, 'foo': {'other-deep': 'value'}}",
    );
    final hash = CompoundHash.fromNode(node, _neverSplit);
    final expected = sha1Base64(
      '("bar":("deep":(string:"value")),"foo":("other-deep":(string:"value")))',
    );
    expect(hash.posts, [p('foo/other-deep')]);
    expect(hash.hashes, [expected, '']);
  });

  test('quoted strings and keys', () {
    final node = n({r'"\"\': r'"\"\', '"': r'\'});
    final hash = CompoundHash.fromNode(node, _neverSplit);
    final expected = sha1Base64(
      r'("\"":(string:"\\"),"\"\\\"\\":(string:"\"\\\"\\"))',
    );
    expect(hash.posts, [
      Path.fromStrings([r'"\"\']),
    ]);
    expect(hash.hashes, [expected, '']);
  });

  Node build(int count) {
    var node = emptyNode;
    for (var i = 0; i < count; i++) {
      node = node.updateImmediateChild(ck('key-$i'), n('value'));
    }
    return node;
  }

  void expectWithinPercent(int expected, int actual, double percent) {
    final lower = expected * (1 - percent / 100);
    final upper = expected * (1 + percent / 100);
    expect(
      actual,
      greaterThan(lower),
      reason: 'range ($lower, $upper): $actual',
    );
    expect(actual, lessThan(upper), reason: 'range ($lower, $upper): $actual');
  }

  test('default split has sensible amount of hashes', () {
    // Roughly 15-20 bytes serialized per node: 10k, 100k and 1M in total.
    expectWithinPercent(
      15,
      CompoundHash.fromNode(build(500)).hashes.length,
      10,
    );
    expectWithinPercent(
      50,
      CompoundHash.fromNode(build(5000)).hashes.length,
      10,
    );
    expectWithinPercent(
      150,
      CompoundHash.fromNode(build(50000)).hashes.length,
      10,
    );
  });

  test('default split handles large leaf node at root', () {
    final leaf = n('x' * (50 * 1024), null);
    expect(CompoundHash.fromNode(leaf).hashes, hasLength(2));
  });
}
