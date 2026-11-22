// Ported from the Android SDK, firebase-database/src/test/java/com/google/firebase/database/core/RangeMergeTest.java
// (firebase-android-sdk 2cfdd0389, Apache-2.0). The iOS twin FRangeMergeTest.m
// (firebase-ios-sdk cef246fea) repeats these cases with the same data; it is not ported twice.
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/range_merge.dart';
import 'package:test/test.dart';

import 'support.dart';

void expectMerge(String node, RangeMergeSpec spec, String expected) {
  final merge = RangeMerge(spec.start, spec.end, nq(spec.update));
  expect(merge.applyTo(nq(node)), nq(expected));
}

/// The bounds and the update of a range merge.
class RangeMergeSpec {
  RangeMergeSpec(String? start, String? end, this.update)
    : start = start == null ? null : p(start),
      end = end == null ? null : p(end);

  final Path? start;
  final Path? end;
  final String update;
}

void main() {
  test('smoke test', () {
    expectMerge(
      "{'bar': 'bar-value', 'foo': { 'a': {'deep-a-1': 1, 'deep-a-2':2}, 'b': 'b', 'c': 'c', 'd': 'd'}, 'quu': 'quu-value'}",
      RangeMergeSpec(
        'foo/a/deep-a-1',
        'foo/c',
        "{'foo': { 'a': {'deep-a-2':'new-a-2', 'deep-a-3':3}, 'b-2': 'new-b', 'c': 'new-c' }}",
      ),
      "{'bar': 'bar-value', 'foo': { 'a': {'deep-a-1': 1, 'deep-a-2':'new-a-2', 'deep-a-3':3}, 'b-2': 'new-b', 'c': 'new-c', 'd': 'd'}, 'quu': 'quu-value'}",
    );
  });

  test('start is exclusive', () {
    expectMerge(
      "{'bar': 'bar-value', 'foo': 'foo-value', 'quu': 'quu-value'}",
      RangeMergeSpec('bar', 'foo', "{'foo': 'new-foo-value' }"),
      "{'bar': 'bar-value', 'foo': 'new-foo-value', 'quu': 'quu-value'}",
    );
  });

  test('start is exclusive but includes children', () {
    expectMerge(
      "{'bar': 'bar-value', 'foo': 'foo-value', 'quu': 'quu-value'}",
      RangeMergeSpec(
        'bar',
        'foo',
        "{'bar': {'bar-child': 'bar-child-value'}, 'foo': 'new-foo-value' }",
      ),
      "{'bar': { 'bar-child': 'bar-child-value'}, 'foo': 'new-foo-value', 'quu': 'quu-value'}",
    );
  });

  test('end is inclusive', () {
    // foo should be deleted
    expectMerge(
      "{'bar': 'bar-value', 'foo': 'foo-value', 'quu': 'quu-value'}",
      RangeMergeSpec('bar', 'foo', "{'baz': 'baz-value' }"),
      "{'bar': 'bar-value', 'baz': 'baz-value', 'quu': 'quu-value'}",
    );
  });

  test('end is inclusive but excludes children', () {
    expectMerge(
      "{'bar': 'bar-value', 'foo': {'foo-child': 'foo-child-value'}, 'quu': 'quu-value'}",
      RangeMergeSpec('bar', 'foo', "{'baz': 'baz-value' }"),
      "{'bar': 'bar-value', 'baz': 'baz-value', 'foo': {'foo-child': 'foo-child-value'}, 'quu': 'quu-value'}",
    );
  });

  test('can update leaf node', () {
    final merge = RangeMerge(null, p('foo'), nq("{'bar': 'bar-value' }"));
    expect(merge.applyTo(n('leaf-value')), nq("{'bar': 'bar-value'}"));
  });

  test('can replace leaf node with leaf node', () {
    final merge = RangeMerge(null, p('/'), n('new-leaf-value'));
    expect(merge.applyTo(n('leaf-value')), n('new-leaf-value'));
  });

  test('leafs are updated when ranges include deeper path', () {
    expectMerge(
      "{'foo': {'bar': 'bar-value'}}",
      RangeMergeSpec(
        'foo/',
        'foo/bar/deep',
        "{'foo': {'bar': 'new-bar-value'}}",
      ),
      "{'foo': {'bar': 'new-bar-value'}}",
    );
  });

  test('leafs are not updated when ranges are at deeper paths', () {
    expectMerge(
      "{'foo': {'bar': 'bar-value'}}",
      RangeMergeSpec(
        'foo/bar',
        'foo/bar/deep',
        "{'foo': {'bar': 'new-bar-value'}}",
      ),
      "{'foo': {'bar': 'bar-value'}}",
    );
  });

  test('updating entire range updates everything', () {
    final merge = RangeMerge(
      null,
      null,
      nq("{'foo': 'foo-value', 'bar': {'child':'bar-child-value'}}"),
    );
    expect(
      merge.applyTo(emptyNode),
      nq("{'foo': 'foo-value', 'bar': {'child':'bar-child-value'}}"),
    );
  });

  test('updating range with unbounded left post works', () {
    expectMerge(
      "{'bar': 'bar-value', 'foo': 'foo-value'}",
      RangeMergeSpec(null, 'bar', "{'bar': 'new-bar'}"),
      "{'bar': 'new-bar', 'foo': 'foo-value'}",
    );
  });

  test('updating range with right post child of left post works', () {
    expectMerge(
      "{'foo': {'a': 'a', 'b': {'1': '1', '2': '2'}, 'c': 'c'}}",
      RangeMergeSpec(
        'foo',
        'foo/b/1',
        "{'foo': {'a': 'new-a', 'b': {'1': 'new-1'}}}",
      ),
      "{'foo': {'a': 'new-a', 'b': {'1': 'new-1', '2': '2'}, 'c': 'c'}}",
    );
  });

  test(
    'updating range with right post child of left post works with integer keys',
    () {
      expectMerge(
        "{'foo': {'a': 'a', 'b': {'1': '1', '2': '2', '10': '10'}, 'c': 'c'}}",
        RangeMergeSpec(
          'foo',
          'foo/b/2',
          "{'foo': {'a': 'new-a', 'b': {'1': 'new-1'}}}",
        ),
        "{'foo': {'a': 'new-a', 'b': {'1': 'new-1', '10': '10'}, 'c': 'c'}}",
      );
    },
  );

  test('updating leaf includes priority', () {
    expectMerge(
      "{'bar': 'bar-value', 'foo': 'foo-value', 'quu': 'quu-value'}",
      RangeMergeSpec(
        'bar',
        'foo',
        "{'foo': { '.value': 'new-foo', '.priority': 'prio' }}",
      ),
      "{'bar': 'bar-value', 'foo': { '.value': 'new-foo', '.priority': 'prio' }, 'quu': 'quu-value'}",
    );
  });

  test('updating priority in children node works', () {
    expectMerge(
      "{'bar': 'bar-value', 'foo': 'foo-value'}",
      RangeMergeSpec(null, 'bar', "{'bar': 'new-bar', '.priority': 'prio' }"),
      "{'bar': 'new-bar', 'foo': 'foo-value', '.priority': 'prio'}",
    );
  });

  test(
    'updating priority in children node works alone',
    () {
      expectMerge(
        "{'bar': 'bar-value', 'foo': 'foo-value'}",
        RangeMergeSpec(null, '.priority', "{'.priority': 'prio' }"),
        "{'bar': 'bar-value', 'foo': 'foo-value', '.priority': 'prio'}",
      );
    },
    skip:
        'Ignored upstream (b/34107586): priorities on empty nodes are ignored',
  );

  test('updating priority on initially empty node does not break', () {
    expectMerge(
      '{}',
      RangeMergeSpec(null, 'foo', "{'.priority': 'prio', 'foo': 'foo-value' }"),
      "{'foo': 'foo-value', '.priority': 'prio'}",
    );
  });

  test('priority is deleted when included in children range', () {
    // Deletes the priority.
    expectMerge(
      "{'bar': 'bar-value', 'foo': 'foo-value', '.priority': 'prio'}",
      RangeMergeSpec(null, 'bar', "{'bar': 'new-bar'}"),
      "{'bar': 'new-bar', 'foo': 'foo-value'}",
    );
  });

  test('priority is included in open start', () {
    expectMerge(
      "{'foo': {'bar': 'bar-value'}}",
      RangeMergeSpec(null, 'foo/bar', "{'.priority': 'prio', 'baz': 'baz' }"),
      "{'baz': 'baz', '.priority': 'prio'}",
    );
  });

  test('priority is included in open end', () {
    final merge = RangeMerge(
      p('/'),
      null,
      nq("{'.priority': 'prio', 'foo': 'bar' }"),
    );
    expect(
      merge.applyTo(n('leaf-value')),
      nq("{'foo': 'bar', '.priority': 'prio'}"),
    );
  });
}
