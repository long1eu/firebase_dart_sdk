// The priority of a node emptied by a write below it, at node level. The server keeps it
// (production, rtdb/from_boss/prodkit_production_run3_2026-11-25.txt, check 38): readers see no
// value, the listen and get answers carry `{".priority": p}` for the node and inside its parent,
// a priority written there replaces it, the hash counts it, and a write at the node drops it.
//
// The expected hashes are computed from the JS SDK's `ChildrenNode.hash` and `LeafNode.hash` by
// hand (SHA-1, base64, of the texts in the comments), not by this client: `H5` below is the hash
// production accepted for the emptied node in check 38 (c).
import 'package:firebase_database_dart/src/core/compound_write.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/priority_index.dart';
import 'package:firebase_database_dart/src/core/snap/leaf_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:test/test.dart';

/// sha1('priority:number:4014000000000000:'): an emptied node with priority 5.
const String _h5 = 'Za4HQEOLkfDszOTdKHl8KWNgpRE=';

Node _node(Object? json) => nodeFromJson(json);

Node _set(Node root, String path, Object? json) =>
    root.updateChild(Path(path), nodeFromJson(json));

ChildrenNode _children(Node n) => n as ChildrenNode;

void main() {
  group('a node emptied below', () {
    test('keeps its priority hidden and gets it back when refilled', () {
      Node n = _node(<String, Object?>{'a': 1, '.priority': 5});
      n = n.updateImmediateChild(ChildKey('a'), ChildrenNode.empty);
      expect(n.isEmpty, isTrue);
      expect(n.value, isNull);
      expect(n.priority.isEmpty, isTrue);
      expect(n, ChildrenNode.empty);
      expect(n.hashCode, ChildrenNode.empty.hashCode);
      expect(n.toJson(exportFormat: true), isNull);
      expect(_children(n).keptPriority, LeafNode(5));
      expect(_children(n).toServerJson(), <String, Object?>{'.priority': 5});
      n = n.updateImmediateChild(ChildKey('b'), LeafNode(1));
      expect(n.toJson(exportFormat: true), <String, Object?>{
        'b': 1,
        '.priority': 5,
      });
    });

    test('inside its parent: a hidden child, refilled with its priority', () {
      Node p = _node(<String, Object?>{
        'n': <String, Object?>{'a': 1, '.priority': 5},
        'm': 1,
      });
      p = _set(p, 'n/a', null);
      expect(p.toJson(exportFormat: true), <String, Object?>{'m': 1});
      expect(p.hasChild(ChildKey('n')), isFalse);
      expect(p.numChildren, 1);
      final List<String> visited = <String>[];
      p.forEachChild(priorityIndex, (ChildKey key, Node _) {
        visited.add(key.name);
        return false;
      });
      expect(visited, <String>['m']);
      expect(p.getImmediateChild(ChildKey('n')).isEmpty, isTrue);
      expect(_children(p).toServerJson(), <String, Object?>{
        'm': 1,
        'n': <String, Object?>{'.priority': 5},
      });
      p = _set(p, 'n/b', 1);
      expect(
        p.getChild(Path('n')).toJson(exportFormat: true),
        <String, Object?>{'b': 1, '.priority': 5},
      );
      expect(_children(p).toServerJson(), <String, Object?>{
        'm': 1,
        'n': <String, Object?>{'b': 1, '.priority': 5},
      });
    });

    test('two levels emptied at once keep both priorities', () {
      Node root = _node(<String, Object?>{
        'p': <String, Object?>{
          'b': <String, Object?>{'x': 1, '.priority': 5},
          '.priority': 2,
        },
      });
      root = _set(root, 'p/b/x', null);
      expect(root.isEmpty, isTrue);
      expect(_children(root).toServerJson(), <String, Object?>{
        'p': <String, Object?>{
          'b': <String, Object?>{'.priority': 5},
          '.priority': 2,
        },
      });
      root = _set(root, 'p/b/x', 1);
      expect(root.toJson(exportFormat: true), <String, Object?>{
        'p': <String, Object?>{
          'b': <String, Object?>{'x': 1, '.priority': 5},
          '.priority': 2,
        },
      });
    });

    test('a write at the node, or at its parent, drops the hidden state', () {
      Node p = _set(
        _node(<String, Object?>{
          'n': <String, Object?>{'a': 1, '.priority': 5},
        }),
        'n/a',
        null,
      );
      expect(_children(p).holdsHiddenState, isTrue);
      final Node deleted = _set(p, 'n', null);
      expect(_children(deleted).holdsHiddenState, isFalse);
      expect(_children(deleted).toServerJson(), isNull);
      expect(
        _set(deleted, 'n/b', 1).toJson(exportFormat: true),
        <String, Object?>{
          'n': <String, Object?>{'b': 1},
        },
      );
      final Node overwritten = _set(p, '', <String, Object?>{'m': 1});
      expect(_children(overwritten).toServerJson(), <String, Object?>{'m': 1});
    });

    test('a priority written on it replaces the kept one; null drops it', () {
      Node p = _set(
        _node(<String, Object?>{
          'n': <String, Object?>{'a': 1, '.priority': 5},
        }),
        'n/a',
        null,
      );
      p = p.updateChild(Path('n/.priority'), LeafNode(9));
      expect(_children(p).toServerJson(), <String, Object?>{
        'n': <String, Object?>{'.priority': 9},
      });
      p = p.updateChild(Path('n/.priority'), ChildrenNode.empty);
      expect(_children(p).toServerJson(), isNull);
      expect(_children(p).holdsHiddenState, isFalse);
    });

    test('a priority on an empty node that keeps none is ignored', () {
      // Only hidden children, no priority of its own: the priority is not taken.
      final Node p = nodeFromServerJson(<String, Object?>{
        'n': <String, Object?>{'.priority': 5},
      });
      expect(p.updatePriority(LeafNode(3)), same(p));
      expect(ChildrenNode.keepsPriority(p), isFalse);
      expect(ChildrenNode.keepsPriority(p.getChild(Path('n'))), isTrue);
    });

    test('a merge applies the priority after the children', () {
      final Node n = _node(<String, Object?>{'a': 1, '.priority': 5});
      final Node merged = CompoundWrite.fromValue(<String, Object?>{
        'a': null,
        '.priority': 7,
      }).apply(n);
      expect(_children(merged).toServerJson(), <String, Object?>{
        '.priority': 7,
      });
      final Node added = CompoundWrite.empty
          .addWrite(Path(''), n)
          .addWrite(Path('a'), ChildrenNode.empty)
          .addWrite(Path('.priority'), LeafNode(9))
          .apply(ChildrenNode.empty);
      expect(_children(added).toServerJson(), <String, Object?>{
        '.priority': 9,
      });
    });

    test('withIndex and the priority index leave hidden children out', () {
      final Node p = nodeFromServerJson(<String, Object?>{
        'n': <String, Object?>{'.priority': 1},
        'm': <String, Object?>{'x': 1, '.priority': 2},
      }).withIndex(priorityIndex);
      expect(
        _children(p).childrenInOrder(priorityIndex).map((n) => n.name.name),
        <String>['m'],
      );
      expect(_children(p).toServerJson(), <String, Object?>{
        'm': <String, Object?>{'x': 1, '.priority': 2},
        'n': <String, Object?>{'.priority': 1},
      });
    });

    test('sameHidden tells hidden states apart', () {
      final Node a = nodeFromServerJson(<String, Object?>{
        'm': 1,
        'n': <String, Object?>{'.priority': 5},
      });
      final Node b = nodeFromServerJson(<String, Object?>{
        'm': 1,
        'n': <String, Object?>{'.priority': 6},
      });
      final Node c = nodeFromServerJson(<String, Object?>{'m': 1});
      expect(a, b);
      expect(ChildrenNode.sameHidden(a, b), isFalse);
      expect(ChildrenNode.sameHidden(a, c), isFalse);
      expect(
        ChildrenNode.sameHidden(
          a,
          nodeFromServerJson(<String, Object?>{
            'm': 1,
            'n': <String, Object?>{'.priority': 5},
          }),
        ),
        isTrue,
      );
      final Node deepA = _set(c, 'q', null).updateChild(Path('k'), a);
      final Node deepB = _set(c, 'q', null).updateChild(Path('k'), b);
      expect(ChildrenNode.sameHiddenAlong(deepA, deepB, Path('k/n')), isFalse);
      expect(ChildrenNode.sameHidden(deepA, deepB), isFalse);
    });
  });

  group('server JSON', () {
    test(
      'nodeFromServerJson keeps {".priority": p}; nodeFromJson does not',
      () {
        final Object json = <String, Object?>{
          'n': <String, Object?>{'.priority': 5.0},
        };
        expect(nodeFromJson(json), same(ChildrenNode.empty));
        final Node kept = nodeFromServerJson(json);
        expect(kept.isEmpty, isTrue);
        expect(_children(kept).toServerJson(), json);
        expect(
          _children(
            nodeFromServerJson(<String, Object?>{'.priority': 5}),
          ).keptPriority,
          LeafNode(5),
        );
        expect(
          nodeFromServerJson(<String, Object?>{}),
          same(ChildrenNode.empty),
        );
        expect(nodeFromServerJson(null), same(ChildrenNode.empty));
      },
    );

    test('a node without hidden state reads as with nodeFromJson', () {
      final Object json = <String, Object?>{
        'a': <String, Object?>{'x': 1, '.priority': 2},
        'b': <String, Object?>{'.value': 'v', '.priority': 'p'},
        '.priority': 1,
      };
      final Node server = nodeFromServerJson(json);
      expect(server, nodeFromJson(json));
      expect(server.hash(), nodeFromJson(json).hash());
      expect(_children(server).toServerJson(), json);
    });
  });

  group('hash counts the kept priority as the server does', () {
    test('an emptied node with priority 5', () {
      Node n = _node(<String, Object?>{'a': 1, '.priority': 5});
      n = n.updateImmediateChild(ChildKey('a'), ChildrenNode.empty);
      expect(n.hash(), _h5);
      expect(nodeFromServerJson(<String, Object?>{'.priority': 5}).hash(), _h5);
      expect(ChildrenNode.empty.hash(), '');
    });

    test('an emptied child inside its parent', () {
      // sha1(':n:' + H5)
      final Node p = _set(
        _node(<String, Object?>{
          'n': <String, Object?>{'a': 1, '.priority': 5},
        }),
        'n/a',
        null,
      );
      expect(p.hash(), 'W04ej2GuuDzu2hTCs+jRoY0hcTE=');
      // sha1(':m:' + sha1('number:3ff0000000000000') + ':n:' + H5): m has no priority and
      // sorts first.
      expect(_set(p, 'm', 1).hash(), 'XzWOy74sb2cqzi7dorD7AhCCaFY=');
    });

    test('nested', () {
      // sha1(':p:' + sha1(':n:' + H5))
      expect(
        nodeFromServerJson(<String, Object?>{
          'p': <String, Object?>{
            'n': <String, Object?>{'.priority': 5},
          },
        }).hash(),
        'AI4z5Vlk7k+r5/QS39pmM0Q3GtE=',
      );
      // An emptied p with priority 2 holding the emptied n:
      // sha1('priority:number:4000000000000000::n:' + H5)
      expect(
        nodeFromServerJson(<String, Object?>{
          'n': <String, Object?>{'.priority': 5},
          '.priority': 2,
        }).hash(),
        'W/V+dm/0RumaYa/wQyTvyiWNeyo=',
      );
    });

    test(
      'a hidden child sorts by its kept priority among the visible ones',
      () {
        // a {x: 1} priority 1, b emptied with priority 5, c {x: 1} priority 9:
        // sha1(':a:' + hash(a) + ':b:' + H5 + ':c:' + hash(c)).
        final Node r = nodeFromServerJson(<String, Object?>{
          'c': <String, Object?>{'x': 1, '.priority': 9},
          'b': <String, Object?>{'.priority': 5},
          'a': <String, Object?>{'x': 1, '.priority': 1},
        });
        expect(r.hash(), 'oJJpnIaW8ajlb3KSeifBWBnymfo=');
      },
    );
  });

  test('emptying and refilling 20000 prioritised children is not quadratic', () {
    // Each child keeps its priority when emptied, so the node holds 20000 hidden children. The
    // bound only catches quadratic behaviour (a copied map took 2.4 s and 11.4 s here).
    const int count = 20000;
    Node n = ChildrenNode.empty;
    for (int i = 0; i < count; i++) {
      n = n.updateImmediateChild(
        ChildKey('c$i'),
        _node(<String, Object?>{'x': 1, '.priority': i}),
      );
    }
    n = n.updatePriority(LeafNode(1));
    final Stopwatch empty = Stopwatch()..start();
    for (int i = 0; i < count; i++) {
      n = n.updateChild(Path('c$i/x'), ChildrenNode.empty);
    }
    empty.stop();
    expect(n.isEmpty, isTrue);
    expect(_children(n).keptPriority, LeafNode(1));
    final Stopwatch refill = Stopwatch()..start();
    for (int i = 0; i < count; i++) {
      n = n.updateChild(Path('c$i/y'), LeafNode(2));
    }
    refill.stop();
    expect(n.numChildren, count);
    expect(n.getChild(Path('c7/.priority')), LeafNode(7));
    expect(empty.elapsedMilliseconds, lessThan(2000));
    expect(refill.elapsedMilliseconds, lessThan(2000));
  });
}
