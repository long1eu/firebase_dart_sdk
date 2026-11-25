// A server merge reaching a limit view whose sync point also holds a complete view (group S of
// rtdb/from_helper/reports/wide_seeds_round3_limit_classification.md). When one child of the
// merge moves a child out of the window, the window pulls the next child from the complete
// server cache; that cache must already hold the merge's earlier children, or the pulled child
// comes with values the same merge changed or removed (measured on the emulator for 245589 and
// 4614, JS 13.4.0 and Dart alike: rtdb/from_helper/reports/group_s_emulator.md).
//
// Each test plays the frames the client receives in one sequence of sync_tree_property_test.dart
// (as the round 3 branch generated it, data as its `_initial`: a {x {u 1}, y {u 2, .priority 2},
// .priority 1}), and checks the limit listener against the window of the server's data after the
// last update. The frames the limit listen got before the default listen was answered are
// folded into one tagged put of its window: the untagged put that answers the default listen
// replaces both caches of the limit view.
import 'package:firebase_database_dart/src/core/compound_write.dart';
import 'package:firebase_database_dart/src/core/connection/listen_hash_provider.dart';
import 'package:firebase_database_dart/src/core/database_error.dart';
import 'package:firebase_database_dart/src/core/event_registration.dart';
import 'package:firebase_database_dart/src/core/listen_provider.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/priority_index.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:firebase_database_dart/src/core/sync_tree.dart';
import 'package:firebase_database_dart/src/core/tag.dart';
import 'package:firebase_database_dart/src/core/view/change.dart';
import 'package:firebase_database_dart/src/core/view/event.dart';
import 'package:firebase_database_dart/src/core/view/query_params.dart';
import 'package:firebase_database_dart/src/core/view/query_spec.dart';
import 'package:test/test.dart';

Node n(Object? json) => nodeFromJson(json);
Path p(String path) => Path(path);

/// `/a` orderByPriority limitToFirst(2), the limit query of the property test.
final QuerySpec limitA = QuerySpec(
  p('a'),
  QueryParams.defaultParams.orderBy(priorityIndex).limitToFirst(2),
);

/// Starts nothing: the tests deliver the server's frames by hand.
final class _Provider implements ListenProvider {
  @override
  List<Event> startListening(
    QuerySpec query,
    Tag? tag,
    ListenHashProvider hash,
    ListenCompletion onComplete,
  ) => const <Event>[];

  @override
  void stopListening(QuerySpec query, Tag? tag) {}
}

/// A listener for every event type.
final class _Reg extends EventRegistration {
  _Reg(this.querySpec);

  @override
  final QuerySpec querySpec;

  @override
  bool respondsTo(EventType type) => true;

  @override
  DataEvent createEvent(Change change, QuerySpec query) => DataEvent(
    change.eventType,
    this,
    change.childKey == null || change.eventType == EventType.value
        ? query.path
        : query.path.child(change.childKey!),
    change.node,
    previousName: change.prevName,
  );

  @override
  void fireEvent(DataEvent event) {}

  @override
  void fireCancelEvent(DatabaseError error) {}

  @override
  EventRegistration clone(QuerySpec newQuery) => _Reg(newQuery);

  @override
  bool isSameListener(EventRegistration other) => identical(other, this);
}

/// A sync tree and the last value each listener got, in export form.
final class _Client {
  final SyncTree tree = SyncTree(listenProvider: _Provider());
  final Map<EventRegistration, Object?> values = <EventRegistration, Object?>{};

  void _take(List<Event> events) {
    for (final Event e in events) {
      if (e is DataEvent && e.eventType == EventType.value) {
        values[e.eventRegistration] = e.snapshot.toJson(exportFormat: true);
      }
    }
  }

  _Reg listen(QuerySpec query) {
    final _Reg reg = _Reg(query);
    _take(tree.addEventRegistration(reg));
    return reg;
  }

  void taggedPut(String path, Object? json) => _take(
    tree.applyTaggedQueryOverwrite(p(path), n(json), tree.tagForQuery(limitA)!),
  );

  void put(String path, Object? json) =>
      _take(tree.applyServerOverwrite(p(path), n(json)));

  void merge(String path, Map<String, Object?> json) => _take(
    tree.applyServerMerge(p(path), <Path, Node>{
      for (final MapEntry<String, Object?> e in json.entries)
        p(e.key): n(e.value),
    }),
  );

  void update(String path, Map<String, Object?> json, int writeId) => _take(
    tree.applyUserMerge(
      p(path),
      CompoundWrite.fromValue(json),
      CompoundWrite.fromValue(json),
      writeId,
      persist: false,
    ),
  );

  void ack(int writeId) => _take(
    tree.ackUserWrite(
      writeId,
      revert: false,
      persist: false,
      serverValues: const <String, Object?>{},
    ),
  );
}

const Map<String, Object?> _b = <String, Object?>{
  'x': <String, Object?>{'u': 1, '.priority': 2},
  '.priority': 3,
};

void main() {
  test('seed 245589: a child moved out by its new priority is not replaced by a child the same '
      'update moved away', () {
    // listen /a:{"l":2,"vf":"l"}; listen /:default; serve; serve (refuse a write);
    // serve (refuse a write); other update /a {"y/.priority":2,"z":{"v":3,"u":2}};
    // other update /a {".priority":null,"z":{"u":3,"v":{".value":3,".priority":1},
    //   ".priority":2},"y/.priority":3}
    final _Client c = _Client();
    final _Reg limit = c.listen(limitA);
    c.listen(QuerySpec.defaultAt(Path.empty));
    c.taggedPut('a', <String, Object?>{
      'x': <String, Object?>{'u': 1},
      'y': <String, Object?>{'u': 2, '.priority': 2},
    });
    c.put('', <String, Object?>{
      'a': <String, Object?>{
        'x': <String, Object?>{'u': 1},
        'y': <String, Object?>{'u': 2, '.priority': 2},
        '.priority': 1,
      },
      'b': _b,
    });
    c.merge('a', <String, Object?>{
      'y/.priority': 2,
      'z': <String, Object?>{'v': 3, 'u': 2},
    });
    expect(c.values[limit], <String, Object?>{
      'x': <String, Object?>{'u': 1},
      'z': <String, Object?>{'u': 2, 'v': 3},
    });
    c.merge('a', <String, Object?>{
      '.priority': null,
      'z': <String, Object?>{
        'u': 3,
        'v': <String, Object?>{'.value': 3, '.priority': 1},
        '.priority': 2,
      },
      'y/.priority': 3,
    });
    expect(c.values[limit], <String, Object?>{
      'x': <String, Object?>{'u': 1},
      'z': <String, Object?>{
        'u': 3,
        'v': <String, Object?>{'.value': 3, '.priority': 1},
        '.priority': 2,
      },
    });
  });

  test(
    'seed 4614: a child removed by the update does not come back into the window',
    () {
      // listen /a:{"l":2,"vf":"l"}; set /a/x/.priority 1; serve;
      // other update /a {"y":{"u":2},"z":{"v":{".value":1,".priority":1}}}; serve;
      // listen /a:default; serve; serve; other update /a {"z":null,"y/.priority":1,"x":null}
      // The own priority write is acknowledged before the default listen is answered; it is left
      // out, its value is in the data.
      final Map<String, Object?> before = <String, Object?>{
        'x': <String, Object?>{'u': 1, '.priority': 1},
        'y': <String, Object?>{'u': 2},
        'z': <String, Object?>{
          'v': <String, Object?>{'.value': 1, '.priority': 1},
        },
        '.priority': 1,
      };
      final _Client c = _Client();
      final _Reg limit = c.listen(limitA);
      c.taggedPut('a', <String, Object?>{'y': before['y'], 'z': before['z']});
      c.listen(QuerySpec.defaultAt(p('a')));
      c.put('a', before);
      c.merge('a', <String, Object?>{'z': null, 'y/.priority': 1, 'x': null});
      expect(c.values[limit], <String, Object?>{
        'y': <String, Object?>{'u': 2, '.priority': 1},
      });
    },
  );

  test(
    'seed 11541: a child pulled into the window keeps the leaf priority the same update '
    'wrote',
    () {
      // update /a {"y":{"v":2,".priority":1},"z":{"u":3}}; listen /a:default;
      // other update /a/x {".priority":2}; listen /a:{"l":2,"vf":"l"}; serve; serve;
      // other update /a {"x/u":{".value":1,".priority":2},"y/.priority":3}
      // The limit listen sends nothing: the default view at /a covers it.
      final _Client c = _Client();
      c.update('a', <String, Object?>{
        'y': <String, Object?>{'v': 2, '.priority': 1},
        'z': <String, Object?>{'u': 3},
      }, 1);
      c.listen(QuerySpec.defaultAt(p('a')));
      final _Reg limit = c.listen(limitA);
      c.ack(1);
      c.put('a', <String, Object?>{
        'x': <String, Object?>{'u': 1, '.priority': 2},
        'y': <String, Object?>{'v': 2, '.priority': 1},
        'z': <String, Object?>{'u': 3},
        '.priority': 1,
      });
      c.merge('a', <String, Object?>{
        'x/u': <String, Object?>{'.value': 1, '.priority': 2},
        'y/.priority': 3,
      });
      expect(c.values[limit], <String, Object?>{
        'z': <String, Object?>{'u': 3},
        'x': <String, Object?>{
          'u': <String, Object?>{'.value': 1, '.priority': 2},
          '.priority': 2,
        },
      });
    },
  );

  test(
    'seed 174519: the window takes the child that sorts next after the whole update',
    () {
      // listen /:default; listen /a:{"l":2,"vf":"l"};
      // update /a {"x":{"u":{".value":1,".priority":1},"v":2},"z":{"v":3,".priority":2}};
      // serve; serve;
      // other update /a {"z":{"v":{".value":2,".priority":2},"u":1,".priority":3},
      //   "x/.priority":3,"x/u":3}
      // The limit listen sends nothing: the default view at / covers it. The server answers the
      // root listen, then sends the own update to it as written, then acknowledges it.
      final Map<String, Object?> update = <String, Object?>{
        'x': <String, Object?>{
          'u': <String, Object?>{'.value': 1, '.priority': 1},
          'v': 2,
        },
        'z': <String, Object?>{'v': 3, '.priority': 2},
      };
      final _Client c = _Client();
      c.listen(QuerySpec.defaultAt(Path.empty));
      final _Reg limit = c.listen(limitA);
      c.update('a', update, 1);
      c.put('', <String, Object?>{
        'a': <String, Object?>{
          'x': <String, Object?>{'u': 1},
          'y': <String, Object?>{'u': 2, '.priority': 2},
          '.priority': 1,
        },
        'b': _b,
      });
      c.merge('a', update);
      c.ack(1);
      c.merge('a', <String, Object?>{
        'z': <String, Object?>{
          'v': <String, Object?>{'.value': 2, '.priority': 2},
          'u': 1,
          '.priority': 3,
        },
        'x/.priority': 3,
        'x/u': 3,
      });
      expect(c.values[limit], <String, Object?>{
        'y': <String, Object?>{'u': 2, '.priority': 2},
        'x': <String, Object?>{'u': 3, 'v': 2, '.priority': 3},
      });
    },
  );

  test(
    'seed 11541 with a write of this client pending: the pulled child shows the write over '
    'the newer server data',
    () {
      // As seed 11541, with `set /a/x/v 7` sent and not answered before the last update arrives.
      final _Client c = _Client();
      c.listen(QuerySpec.defaultAt(p('a')));
      final _Reg limit = c.listen(limitA);
      c.put('a', <String, Object?>{
        'x': <String, Object?>{'u': 1, '.priority': 2},
        'y': <String, Object?>{'v': 2, '.priority': 1},
        'z': <String, Object?>{'u': 3},
        '.priority': 1,
      });
      c._take(
        c.tree.applyUserOverwrite(
          p('a/x/v'),
          n(7),
          n(7),
          1,
          visible: true,
          persist: false,
        ),
      );
      c.merge('a', <String, Object?>{
        'x/u': <String, Object?>{'.value': 1, '.priority': 2},
        'y/.priority': 3,
      });
      expect(c.values[limit], <String, Object?>{
        'z': <String, Object?>{'u': 3},
        'x': <String, Object?>{
          'u': <String, Object?>{'.value': 1, '.priority': 2},
          'v': 7,
          '.priority': 2,
        },
      });
    },
  );

  test(
    'a merge sent to a listener above the query, with keys below its children',
    () {
      // listen /:default over the limit query; the merge at / writes `a/w/u` and `a/y/.priority`.
      // `w` sorts before `y`, so it changes outside the window, then enters it when `y` leaves.
      final _Client c = _Client();
      c.listen(QuerySpec.defaultAt(Path.empty));
      final _Reg limit = c.listen(limitA);
      c.put('', <String, Object?>{
        'a': <String, Object?>{
          'w': <String, Object?>{'u': 1, '.priority': 1},
          'x': <String, Object?>{'u': 1},
          'y': <String, Object?>{'u': 2},
        },
      });
      expect(c.values[limit], <String, Object?>{
        'x': <String, Object?>{'u': 1},
        'y': <String, Object?>{'u': 2},
      });
      c.merge('', <String, Object?>{'a/w/u': 4, 'a/y/.priority': 5});
      expect(c.values[limit], <String, Object?>{
        'x': <String, Object?>{'u': 1},
        'w': <String, Object?>{'u': 4, '.priority': 1},
      });
    },
  );

  test('a child leaving the window for a merge key the window did not hold pulls the next child '
      'with the values of the same merge', () {
    // A tagged merge after the default listen was answered (sent before the server took the
    // limit unlisten) filters the limit view's server cache to its window {p, q}. A pending
    // write puts s into the event window; the merge removes s (a key outside the server window,
    // second loop) and changes q, which the window then pulls.
    final _Client c = _Client();
    final _Reg limit = c.listen(limitA);
    c.listen(QuerySpec.defaultAt(Path.empty));
    final Map<String, Object?> window = <String, Object?>{
      'p': <String, Object?>{'u': 1, '.priority': 1},
      'q': <String, Object?>{'u': 1, '.priority': 2},
    };
    c.taggedPut('a', window);
    c.put('', <String, Object?>{
      'a': <String, Object?>{
        ...window,
        'r': <String, Object?>{'u': 1, '.priority': 3},
        's': <String, Object?>{'u': 1, '.priority': 4},
      },
    });
    c._take(
      c.tree.applyTaggedQueryMerge(p('a'), <Path, Node>{
        p('p/u'): n(1),
      }, c.tree.tagForQuery(limitA)!),
    );
    c._take(
      c.tree.applyUserOverwrite(
        p('a/s/.priority'),
        n(0),
        n(0),
        1,
        visible: true,
        persist: false,
      ),
    );
    expect(c.values[limit], <String, Object?>{
      's': <String, Object?>{'u': 1, '.priority': 0},
      'p': <String, Object?>{'u': 1, '.priority': 1},
    });
    c.merge('a', <String, Object?>{'q/u': 5, 's': null});
    expect(c.values[limit], <String, Object?>{
      'p': <String, Object?>{'u': 1, '.priority': 1},
      'q': <String, Object?>{'u': 5, '.priority': 2},
    });
  });

  test('seed 265 (two-pass review): a merge with no priority refills a limitToLast window with the '
      'value the same merge wrote', () {
    // listen /:default; serve {"a":{"x":3,"y":1}}; listen /a orderByPriority limitToLast(1);
    // other update /a {"y":null,"x":1}
    // The window is {y}. The merge sets x (outside the window) first, then removes y, and the
    // window pulls x: it must come with the value 1 of the same merge, not 3.
    final _Client c = _Client();
    c.listen(QuerySpec.defaultAt(Path.empty));
    final _Reg limit = c.listen(
      QuerySpec(
        p('a'),
        QueryParams.defaultParams.orderBy(priorityIndex).limitToLast(1),
      ),
    );
    c.put('', <String, Object?>{
      'a': <String, Object?>{'x': 3, 'y': 1},
    });
    expect(c.values[limit], <String, Object?>{'y': 1});
    c.merge('a', <String, Object?>{'y': null, 'x': 1});
    expect(c.values[limit], <String, Object?>{'x': 1});
  });

  test(
    'seed 20221 (two-pass review): a child removed by the merge does not enter the window and '
    'raises no child_added',
    () {
      // listen /:default; serve {"a":{"x":{"u":1,".priority":2},"y":1,"z":1}};
      // listen /a:{"l":2,"vf":"l"}; other update /a {"x":null,"z/.priority":3}
      // The window is {y, z}. The merge removes x (outside the window) first, then moves z behind
      // x's old place; z stays in the window, since x is gone.
      final _Client c = _Client();
      c.listen(QuerySpec.defaultAt(Path.empty));
      final _Reg limit = c.listen(limitA);
      c.put('', <String, Object?>{
        'a': <String, Object?>{
          'x': <String, Object?>{'u': 1, '.priority': 2},
          'y': 1,
          'z': 1,
        },
      });
      expect(c.values[limit], <String, Object?>{'y': 1, 'z': 1});
      final List<Event> events = c.tree.applyServerMerge(p('a'), <Path, Node>{
        p('x'): n(null),
        p('z/.priority'): n(3),
      });
      c._take(events);
      expect(c.values[limit], <String, Object?>{
        'y': 1,
        'z': <String, Object?>{'.value': 1, '.priority': 3},
      });
      expect(<String>[
        for (final Event e in events)
          if (e is DataEvent &&
              identical(e.eventRegistration, limit) &&
              e.eventType == EventType.childAdded)
            '${e.snapshotPath}',
      ], isEmpty);
    },
  );
}
