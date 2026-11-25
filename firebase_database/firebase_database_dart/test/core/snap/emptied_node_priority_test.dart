// The priority of a node emptied by a write below it, at node level. The server keeps it
// (production, rtdb/from_boss/prodkit_production_run3_2026-11-25.txt, check 38): readers see no
// value, the listen and get answers carry `{".priority": p}` for the node and inside its parent,
// a priority written there replaces it, the hash counts it, and a write at the node drops it.
//
// The expected hashes are computed from the JS SDK's `ChildrenNode.hash` and `LeafNode.hash` by
// hand (SHA-1, base64, of the texts in the comments), not by this client: `H5` below is the hash
// production accepted for the emptied node in check 38 (c).
import 'package:firebase_database_dart/src/core/compound_write.dart';
import 'package:firebase_database_dart/src/core/connection/wire_range_merge.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/compound_hash.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/priority_index.dart';
import 'package:firebase_database_dart/src/core/snap/leaf_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:firebase_database_dart/src/core/snap/range_merge.dart';
import 'package:firebase_database_dart/src/testing/json_server_model.dart';
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

    test('a node holding only emptied children takes a priority (Q2)', () {
      // Production check 39 Q2: n {c: {x: 1} priority 3}, remove n/c/x, put n/.priority 9:
      //   p n/.priority 9 answered {"s":"ok","d":""}
      //   get answered {"s":"ok","d":{".priority":9,"c":{".priority":3.0}}}
      Node n = _node(<String, Object?>{
        'c': <String, Object?>{'x': 1, '.priority': 3.0},
      });
      n = n.updateChild(Path('c/x'), ChildrenNode.empty);
      expect(ChildrenNode.takesPriority(n), isTrue);
      n = n.updateChild(Path('.priority'), LeafNode(9));
      expect(_children(n).toServerJson(), <String, Object?>{
        '.priority': 9,
        'c': <String, Object?>{'.priority': 3.0},
      });
      expect(ChildrenNode.takesPriority(ChildrenNode.empty), isFalse);
      expect(
        ChildrenNode.empty.updatePriority(LeafNode(3)),
        same(ChildrenNode.empty),
      );
    });

    group('one update: the children first, then the priority (Q1, Q6)', () {
      Object? merge(Object? node, Map<String, Object?> update) =>
          (CompoundWrite.fromValue(update).apply(nodeFromServerJson(node))
                  as ChildrenNode)
              .toServerJson();

      test('Q1: {a: 1} without a priority, {a: null, .priority: 7}: removed', () {
        // m n {"a":null,".priority":7} answered ok; get answered {"s":"ok","d":null}
        expect(
          merge(
            <String, Object?>{'a': 1},
            <String, Object?>{'a': null, '.priority': 7},
          ),
          isNull,
        );
      });

      test('Q1: {a: 1, b: 2}, {a: null, b: null, .priority: 7}: removed', () {
        // m n {"a":null,"b":null,".priority":7} answered ok; get answered {"s":"ok","d":null}
        expect(
          merge(
            <String, Object?>{'a': 1, 'b': 2},
            <String, Object?>{'a': null, 'b': null, '.priority': 7},
          ),
          isNull,
        );
      });

      test('Q1 control: with priority 5, {a: null, .priority: 7}: kept 7', () {
        // get answered {"s":"ok","d":{".priority":7}}
        expect(
          merge(
            <String, Object?>{'a': 1, '.priority': 5},
            <String, Object?>{'a': null, '.priority': 7},
          ),
          <String, Object?>{'.priority': 7},
        );
      });

      test('Q6: the deep form per node', () {
        // p {x: {a: 1}}, update at p {x/a: null, x/.priority: 3}: get answered {"d":null}
        expect(
          merge(
            <String, Object?>{
              'x': <String, Object?>{'a': 1},
            },
            <String, Object?>{'x/a': null, 'x/.priority': 3},
          ),
          isNull,
        );
        // Control, x with priority 5: get answered {"d":{"x":{".priority":3}}}
        expect(
          merge(
            <String, Object?>{
              'x': <String, Object?>{'a': 1, '.priority': 5},
            },
            <String, Object?>{'x/a': null, 'x/.priority': 3},
          ),
          <String, Object?>{
            'x': <String, Object?>{'.priority': 3},
          },
        );
      });

      test(
        'own priority next to a deeper priority null that removes the last child',
        () {
          // Property seeds 59755 and 76701. b = {x: {v: 2, .priority: 1}}, no priority of its
          // own; update /b {".priority": 2, "x/v": null, "x/.priority": null}. The client
          // finishes x's subtree first: x is removed, b is left with nothing and its priority
          // is dropped. The shared server model applies the priorities in the update's key
          // order: b takes 2 while x still holds its kept priority, and keeps it when x goes.
          // Unmeasured: one raw `m` of this update (in both key orders), then `g b`.
          final Object? client = merge(
            <String, Object?>{
              'x': <String, Object?>{'v': 2, '.priority': 1},
            },
            <String, Object?>{'.priority': 2, 'x/v': null, 'x/.priority': null},
          );
          final JsonServerModel model =
              JsonServerModel(<String, Object?>{
                'b': <String, Object?>{
                  'x': <String, Object?>{'v': 2, '.priority': 1},
                },
              })..write('b', <String, Object?>{
                '.priority': 2,
                'x/v': null,
                'x/.priority': null,
              }, merge: true);
          expect(client, isNull);
          expect(model.export('b', hidden: true), client);
        },
        skip:
            "server order unmeasured: a node's own priority next to a deeper "
            'priority in one update (property M9)',
      );

      test('a refilling update keeps the priority (production check 22)', () {
        expect(
          merge(
            <String, Object?>{'a': 1, '.priority': 0},
            <String, Object?>{'a': null, 'b': 1},
          ),
          <String, Object?>{'b': 1, '.priority': 0},
        );
      });

      test('layered writes keep a priority written on a node with a value', () {
        final Node n = _node(<String, Object?>{'a': 1, '.priority': 5});
        final Node added = CompoundWrite.empty
            .addWrite(Path(''), n)
            .addWrite(Path('a'), ChildrenNode.empty)
            .addWrite(Path('.priority'), LeafNode(9))
            .apply(ChildrenNode.empty);
        expect(_children(added).toServerJson(), <String, Object?>{
          '.priority': 9,
        });
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

  group('range merges (rm) carry and drop kept priorities', () {
    final Map<String, Object?> server = <String, Object?>{
      'a': 1,
      'n': <String, Object?>{'.priority': 5},
      'z': 2,
    };
    Node apply(Object? cache, String? start, String? end, Object? data) =>
        RangeMerge.fromWire(
          WireRangeMerge(exclusiveStart: start, inclusiveEnd: end, data: data),
        ).applyTo(nodeFromServerJson(cache));

    test('a full range carrying {".priority": 5}', () {
      final Node got = apply(
        <String, Object?>{'a': 1, 'z': 2},
        null,
        null,
        server,
      );
      expect(_children(got).toServerJson(), server);
      expect(got.hash(), nodeFromServerJson(server).hash());
    });

    test('a partial range carrying {".priority": 5}', () {
      // (/a, /y] holds n and its priority (/n/.priority sorts after /n).
      final Node got = apply(
        <String, Object?>{'a': 1, 'z': 2},
        '/a',
        '/y',
        <String, Object?>{
          'n': <String, Object?>{'.priority': 5},
        },
      );
      expect(_children(got).toServerJson(), server);
      expect(got.hash(), nodeFromServerJson(server).hash());
    });

    test('a partial range from a server that dropped the kept priority', () {
      final Node got = apply(server, '/a', '/y', null);
      expect(_children(got).toServerJson(), <String, Object?>{'a': 1, 'z': 2});
      expect(
        got.hash(),
        nodeFromServerJson(<String, Object?>{'a': 1, 'z': 2}).hash(),
      );
    });

    test('a partial range that keeps a node emptied in the range', () {
      // The cache's n is visible; the server emptied it and sends it with its priority.
      final Node got = apply(
        <String, Object?>{
          'a': 1,
          'n': <String, Object?>{'x': 1, '.priority': 5},
          'z': 2,
        },
        '/a',
        '/y',
        <String, Object?>{
          'n': <String, Object?>{'.priority': 5},
        },
      );
      expect(_children(got).toServerJson(), server);
    });
  });

  group('compound hash: kept priorities as .priority leaves (Q5)', () {
    // Production check 39 Q5. The node, as the get answered (the kit writes "<540 x>" for 540
    // times "x"):
    //   {"a":"<540 x>","b":{".priority":5.0},"c":"<540 y>",
    //    "d":{"e":"<100 z>","f":{".priority":2.0},"g":"<100 k>"}}
    // simple hash as stored sRWxeuBc4owa0z6qxwPow1Q1CxI=, without kept priorities
    // +84ymKWvp0jIfve/rTLAuK+XFJw=. With the kept priorities as a .priority leaf the server
    // answered `rm []`; without them, an rm carrying b and d/f.
    final Map<String, Object?> q5 = <String, Object?>{
      'a': 'x' * 540,
      'b': <String, Object?>{'.priority': 5.0},
      'c': 'y' * 540,
      'd': <String, Object?>{
        'e': 'z' * 100,
        'f': <String, Object?>{'.priority': 2.0},
        'g': 'k' * 100,
      },
    };

    List<String> posts(CompoundHash h) => <String>[
      for (final Path p in h.posts) p.toString(),
    ];

    test('the client sends the form the server matches', () {
      final Node node = nodeFromServerJson(q5);
      expect(node.hash(), 'sRWxeuBc4owa0z6qxwPow1Q1CxI=');
      final CompoundHash hash = CompoundHash.fromNode(node);
      // ch {"ps":["/a","/c","/d/g"],"hs":["Y2j5JgavfCS4TsxyLghrO4yezUU=",
      //   "Y/Yk/xh7wSVKRow59iWoMK7lwMc=","65bojvyWrdrpx2wZii9Kk5oefY0=",""]} -> rm []
      expect(posts(hash), <String>['/a', '/c', '/d/g']);
      expect(hash.hashes, <String>[
        'Y2j5JgavfCS4TsxyLghrO4yezUU=',
        'Y/Yk/xh7wSVKRow59iWoMK7lwMc=',
        '65bojvyWrdrpx2wZii9Kk5oefY0=',
        '',
      ]);
    });

    test(
      'without the kept priorities: the form the server answers with an rm',
      () {
        final Node node = nodeFromJson(q5);
        expect(node.hash(), '+84ymKWvp0jIfve/rTLAuK+XFJw=');
        final CompoundHash hash = CompoundHash.fromNode(node);
        expect(posts(hash), <String>['/a', '/c', '/d/g']);
        expect(hash.hashes, <String>[
          'Y2j5JgavfCS4TsxyLghrO4yezUU=',
          '0trf09srj8To3oUB2Z+bCgm3Ilk=',
          'ReHoXLVbiUHHW1axbsdmfIcj91s=',
          '',
        ]);
      },
    );

    test('a node that only keeps a priority hashes as its .priority leaf', () {
      final CompoundHash hash = CompoundHash.fromNode(
        nodeFromServerJson(<String, Object?>{'.priority': 5}),
      );
      expect(hash.hashes, hasLength(2));
      expect(hash.hashes.first, isNot(''));
    });
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
