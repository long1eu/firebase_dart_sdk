// Port of Android RangeMergeTest.java.
import 'package:firebase_database_dart/src/core/connection/wire_range_merge.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:firebase_database_dart/src/core/snap/range_merge.dart';
import 'package:test/test.dart';

Node n(Object? json) => nodeFromJson(json);

void expectMerge(
  Object? node,
  String? start,
  String? end,
  Object? update,
  Object? expected,
) {
  final RangeMerge merge = RangeMerge(
    start == null ? null : Path(start),
    end == null ? null : Path(end),
    n(update),
  );
  expect(merge.applyTo(n(node)), n(expected));
}

const Map<String, Object?> barFooQuu = <String, Object?>{
  'bar': 'bar-value',
  'foo': 'foo-value',
  'quu': 'quu-value',
};

void main() {
  test('smoke test', () {
    expectMerge(
      <String, Object?>{
        'bar': 'bar-value',
        'foo': <String, Object?>{
          'a': <String, Object?>{'deep-a-1': 1, 'deep-a-2': 2},
          'b': 'b',
          'c': 'c',
          'd': 'd',
        },
        'quu': 'quu-value',
      },
      'foo/a/deep-a-1',
      'foo/c',
      <String, Object?>{
        'foo': <String, Object?>{
          'a': <String, Object?>{'deep-a-2': 'new-a-2', 'deep-a-3': 3},
          'b-2': 'new-b',
          'c': 'new-c',
        },
      },
      <String, Object?>{
        'bar': 'bar-value',
        'foo': <String, Object?>{
          'a': <String, Object?>{
            'deep-a-1': 1,
            'deep-a-2': 'new-a-2',
            'deep-a-3': 3,
          },
          'b-2': 'new-b',
          'c': 'new-c',
          'd': 'd',
        },
        'quu': 'quu-value',
      },
    );
  });

  test('start is exclusive', () {
    expectMerge(
      barFooQuu,
      'bar',
      'foo',
      <String, Object?>{'foo': 'new-foo-value'},
      <String, Object?>{
        'bar': 'bar-value',
        'foo': 'new-foo-value',
        'quu': 'quu-value',
      },
    );
  });

  test('start is exclusive but includes children', () {
    expectMerge(
      barFooQuu,
      'bar',
      'foo',
      <String, Object?>{
        'bar': <String, Object?>{'bar-child': 'bar-child-value'},
        'foo': 'new-foo-value',
      },
      <String, Object?>{
        'bar': <String, Object?>{'bar-child': 'bar-child-value'},
        'foo': 'new-foo-value',
        'quu': 'quu-value',
      },
    );
  });

  test('end is inclusive', () {
    expectMerge(
      barFooQuu,
      'bar',
      'foo',
      <String, Object?>{'baz': 'baz-value'},
      <String, Object?>{
        'bar': 'bar-value',
        'baz': 'baz-value',
        'quu': 'quu-value',
      },
    );
  });

  test('end is inclusive but excludes children', () {
    expectMerge(
      <String, Object?>{
        'bar': 'bar-value',
        'foo': <String, Object?>{'foo-child': 'foo-child-value'},
        'quu': 'quu-value',
      },
      'bar',
      'foo',
      <String, Object?>{'baz': 'baz-value'},
      <String, Object?>{
        'bar': 'bar-value',
        'baz': 'baz-value',
        'foo': <String, Object?>{'foo-child': 'foo-child-value'},
        'quu': 'quu-value',
      },
    );
  });

  test('can update leaf node', () {
    expectMerge(
      'leaf-value',
      null,
      'foo',
      <String, Object?>{'bar': 'bar-value'},
      <String, Object?>{'bar': 'bar-value'},
    );
  });

  test('can replace leaf node with leaf node', () {
    expectMerge('leaf-value', null, '/', 'new-leaf-value', 'new-leaf-value');
  });

  test('leafs are updated when ranges include deeper path', () {
    expectMerge(
      <String, Object?>{
        'foo': <String, Object?>{'bar': 'bar-value'},
      },
      'foo/',
      'foo/bar/deep',
      <String, Object?>{
        'foo': <String, Object?>{'bar': 'new-bar-value'},
      },
      <String, Object?>{
        'foo': <String, Object?>{'bar': 'new-bar-value'},
      },
    );
  });

  test('leafs are not updated when ranges are at deeper paths', () {
    expectMerge(
      <String, Object?>{
        'foo': <String, Object?>{'bar': 'bar-value'},
      },
      'foo/bar',
      'foo/bar/deep',
      <String, Object?>{
        'foo': <String, Object?>{'bar': 'new-bar-value'},
      },
      <String, Object?>{
        'foo': <String, Object?>{'bar': 'bar-value'},
      },
    );
  });

  test('updating entire range updates everything', () {
    final Map<String, Object?> update = <String, Object?>{
      'foo': 'foo-value',
      'bar': <String, Object?>{'child': 'bar-child-value'},
    };
    final RangeMerge merge = RangeMerge(null, null, n(update));
    expect(merge.applyTo(ChildrenNode.empty), n(update));
  });

  test('updating range with unbounded left post works', () {
    expectMerge(
      <String, Object?>{'bar': 'bar-value', 'foo': 'foo-value'},
      null,
      'bar',
      <String, Object?>{'bar': 'new-bar'},
      <String, Object?>{'bar': 'new-bar', 'foo': 'foo-value'},
    );
  });

  test('updating range with right post child of left post works', () {
    expectMerge(
      <String, Object?>{
        'foo': <String, Object?>{
          'a': 'a',
          'b': <String, Object?>{'1': '1', '2': '2'},
          'c': 'c',
        },
      },
      'foo',
      'foo/b/1',
      <String, Object?>{
        'foo': <String, Object?>{
          'a': 'new-a',
          'b': <String, Object?>{'1': 'new-1'},
        },
      },
      <String, Object?>{
        'foo': <String, Object?>{
          'a': 'new-a',
          'b': <String, Object?>{'1': 'new-1', '2': '2'},
          'c': 'c',
        },
      },
    );
  });

  test('right post child of left post works with integer keys', () {
    expectMerge(
      <String, Object?>{
        'foo': <String, Object?>{
          'a': 'a',
          'b': <String, Object?>{'1': '1', '2': '2', '10': '10'},
          'c': 'c',
        },
      },
      'foo',
      'foo/b/2',
      <String, Object?>{
        'foo': <String, Object?>{
          'a': 'new-a',
          'b': <String, Object?>{'1': 'new-1'},
        },
      },
      <String, Object?>{
        'foo': <String, Object?>{
          'a': 'new-a',
          'b': <String, Object?>{'1': 'new-1', '10': '10'},
          'c': 'c',
        },
      },
    );
  });

  test('updating leaf includes priority', () {
    expectMerge(
      barFooQuu,
      'bar',
      'foo',
      <String, Object?>{
        'foo': <String, Object?>{'.value': 'new-foo', '.priority': 'prio'},
      },
      <String, Object?>{
        'bar': 'bar-value',
        'foo': <String, Object?>{'.value': 'new-foo', '.priority': 'prio'},
        'quu': 'quu-value',
      },
    );
  });

  test('updating priority in children node works', () {
    expectMerge(
      <String, Object?>{'bar': 'bar-value', 'foo': 'foo-value'},
      null,
      'bar',
      <String, Object?>{'bar': 'new-bar', '.priority': 'prio'},
      <String, Object?>{
        'bar': 'new-bar',
        'foo': 'foo-value',
        '.priority': 'prio',
      },
    );
  });

  // Android @Ignore (b/34107586): priorities on empty nodes are ignored.
  test(
    'updating priority in children node works alone',
    () {
      expectMerge(
        <String, Object?>{'bar': 'bar-value', 'foo': 'foo-value'},
        null,
        '.priority',
        <String, Object?>{'.priority': 'prio'},
        <String, Object?>{
          'bar': 'bar-value',
          'foo': 'foo-value',
          '.priority': 'prio',
        },
      );
    },
    skip: 'Ignored upstream (Android b/34107586)',
  );

  test('updating priority on initially empty node does not break', () {
    expectMerge(
      <String, Object?>{},
      null,
      'foo',
      <String, Object?>{'.priority': 'prio', 'foo': 'foo-value'},
      <String, Object?>{'foo': 'foo-value', '.priority': 'prio'},
    );
  });

  test('priority is deleted when included in children range', () {
    expectMerge(
      <String, Object?>{
        'bar': 'bar-value',
        'foo': 'foo-value',
        '.priority': 'prio',
      },
      null,
      'bar',
      <String, Object?>{'bar': 'new-bar'},
      <String, Object?>{'bar': 'new-bar', 'foo': 'foo-value'},
    );
  });

  test('priority is included in open start', () {
    expectMerge(
      <String, Object?>{
        'foo': <String, Object?>{'bar': 'bar-value'},
      },
      null,
      'foo/bar',
      <String, Object?>{'.priority': 'prio', 'baz': 'baz'},
      <String, Object?>{'baz': 'baz', '.priority': 'prio'},
    );
  });

  test('priority is included in open end', () {
    expectMerge(
      'leaf-value',
      '/',
      null,
      <String, Object?>{'.priority': 'prio', 'foo': 'bar'},
      <String, Object?>{'foo': 'bar', '.priority': 'prio'},
    );
  });

  test('fromWire parses paths with and without a leading slash', () {
    final RangeMerge merge = RangeMerge.fromWire(
      const WireRangeMerge(
        exclusiveStart: 'ch/c4',
        inclusiveEnd: '/ch/c9',
        data: <String, Object?>{'x': 1},
      ),
    );
    expect(merge.exclusiveStart, Path('/ch/c4'));
    expect(merge.inclusiveEnd, Path('ch/c9'));
    expect(merge.snap, n(<String, Object?>{'x': 1}));
    final RangeMerge open = RangeMerge.fromWire(
      const WireRangeMerge(data: 'leaf'),
    );
    expect(open.exclusiveStart, isNull);
    expect(open.inclusiveEnd, isNull);
    expect(open.applyTo(n('old')), n('leaf'));
  });
}
