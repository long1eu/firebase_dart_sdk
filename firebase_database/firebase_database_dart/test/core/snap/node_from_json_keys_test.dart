// One ChildKey per distinct name within one nodeFromJson call.
import 'dart:convert';

import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:test/test.dart';

List<ChildKey> _keys(Node node) => <ChildKey>[
  for (final MapEntry<ChildKey, Node> e
      in (node as ChildrenNode).children.entries)
    e.key,
];

void main() {
  // Decoded text, so equal names are different string objects, as in a server message.
  final Object? json = jsonDecode(
    '{"r1":{"name":"a","n":{"name":1}},"r2":{"name":"b",".priority":2},'
    '"list":[{"name":"c"},{"name":"d"}]}',
  );

  test('a repeated name is one key in one call, at any depth', () {
    final Node node = nodeFromJson(json);
    final ChildKey name = _keys(node.getImmediateChild(ChildKey('r1'))).last;
    expect(name.name, 'name');
    final Node r1 = node.getImmediateChild(ChildKey('r1'));
    expect(
      identical(_keys(r1.getImmediateChild(ChildKey('n'))).single, name),
      isTrue,
    );
    expect(
      identical(_keys(node.getImmediateChild(ChildKey('r2'))).single, name),
      isTrue,
    );
    final Node list = node.getImmediateChild(ChildKey('list'));
    for (final ChildKey index in _keys(list)) {
      expect(
        identical(_keys(list.getImmediateChild(index)).single, name),
        isTrue,
      );
    }
  });

  test('the node is the same as without sharing', () {
    final Node node = nodeFromJson(json);
    expect(
      jsonEncode(node.toJson(exportFormat: true)),
      '{"list":{"0":{"name":"c"},"1":{"name":"d"}},'
      '"r1":{"n":{"name":1},"name":"a"},"r2":{"name":"b",".priority":2}}',
    );
    expect(node, nodeFromJson(jsonDecode(jsonEncode(json))));
    expect(node.hash, nodeFromJson(jsonDecode(jsonEncode(json))).hash);
  });

  test('two calls share nothing', () {
    final ChildKey a = _keys(nodeFromJson(jsonDecode('{"k":1}'))).single;
    final ChildKey b = _keys(nodeFromJson(jsonDecode('{"k":1}'))).single;
    expect(a, b);
    expect(identical(a, b), isFalse);
  });
}
