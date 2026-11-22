// NodeSizeEstimator (Android core/utilities/NodeSizeEstimator.java; no upstream test).
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:firebase_database_dart/src/core/util/node_size_estimator.dart';
import 'package:test/test.dart';

void main() {
  test('leaves', () {
    expect(estimateSerializedNodeSize(ChildrenNode.empty), 4);
    expect(estimateSerializedNodeSize(nodeFromJson(1)), 8);
    expect(estimateSerializedNodeSize(nodeFromJson(1.5)), 8);
    expect(estimateSerializedNodeSize(nodeFromJson(true)), 4);
    expect(estimateSerializedNodeSize(nodeFromJson('abc')), 5);
  });

  test('leaf with priority adds the overhead and the priority', () {
    // 24 overhead + 5 ("abc") + 8 (number priority).
    expect(
      estimateSerializedNodeSize(
        nodeFromJson(<String, Object?>{'.value': 'abc', '.priority': 1}),
      ),
      37,
    );
  });

  test('children', () {
    // 1 + ("a": 1 + 4 + 8) + ("bb": 2 + 4 + 4) = 24.
    expect(
      estimateSerializedNodeSize(
        nodeFromJson(<String, Object?>{'a': 1, 'bb': true}),
      ),
      24,
    );
    // Plus 12 + 3 for the ".priority": "p" of the node.
    expect(
      estimateSerializedNodeSize(
        nodeFromJson(<String, Object?>{'a': 1, 'bb': true, '.priority': 'p'}),
      ),
      39,
    );
  });

  test('nodeCount counts leaves', () {
    expect(nodeCount(ChildrenNode.empty), 0);
    expect(nodeCount(nodeFromJson('x')), 1);
    expect(
      nodeCount(
        nodeFromJson(<String, Object?>{
          'a': 1,
          'b': <String, Object?>{'c': 2, 'd': 3},
        }),
      ),
      3,
    );
  });
}
