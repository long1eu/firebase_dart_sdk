// Benchmarks for the chunk-4 COULD perf items (upstream commits 77aa34e,
// 482ac0e, 2a81fad). Run: `dart run bench_c4.dart` (JIT) and
// `dart compile exe bench_c4.dart` (AOT).
import 'dart:collection';

import 'package:cloud_firestore_vm/src/firebase/firestore/core/document_view_change.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/document_view_change_set.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/order_by.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/value/field_value.dart';

const int reps = 9;
int sink = 0;

void report(String name, void Function() f, {int warm = 2}) {
  for (int i = 0; i < warm; i++) {
    f();
  }
  final List<double> t = <double>[];
  for (int i = 0; i < reps; i++) {
    final Stopwatch sw = Stopwatch()..start();
    f();
    t.add(sw.elapsedMicroseconds / 1000);
  }
  t.sort();
  print('${name.padRight(52)} median ${t[reps ~/ 2].toStringAsFixed(2).padLeft(9)} ms'
      '  min ${t.first.toStringAsFixed(2).padLeft(9)}  max ${t.last.toStringAsFixed(2).padLeft(9)}');
}

Document doc(int i, int n) => Document(
      DocumentKey.fromPathString('coll/d${i.toString().padLeft(6, '0')}'),
      SnapshotVersion.none,
      DocumentState.synced,
      ObjectValue.fromMap(<String, FieldValue>{'n': IntegerValue(n)}),
    );

ObjectValue nested(int depth, int width, int seed) {
  if (depth == 0) {
    return ObjectValue.fromMap(<String, FieldValue>{'leaf': IntegerValue(seed)});
  }
  return ObjectValue.fromMap(<String, FieldValue>{
    for (int i = 0; i < width; i++) 'k$i': nested(depth - 1, width, seed + i),
  });
}

void main() {
  const int n = 20000;
  final List<Document> docs = <Document>[
    for (int i = 0; i < n; i++) doc(i, (i * 7919) % n)
  ];
  final Query query = Query(ResourcePath.fromString('coll'),
      explicitSortOrder: <OrderBy>[
        OrderBy.getInstance(OrderByDirection.ascending, FieldPath.fromSingleSegment('n'))
      ]);

  // (59) comparator hoisting, as in View.applyChanges' final sort.
  report('sort 20k docs, query.comparator in callback (old View code)', () {
    final List<Document> l = List<Document>.of(docs);
    l.sort((Document a, Document b) => query.comparator(a, b));
    sink += l.length;
  });
  report('sort 20k docs, hoisted comparator', () {
    final List<Document> l = List<Document>.of(docs);
    final Comparator<Document> c = query.comparator;
    l.sort(c);
    sink += l.length;
  });

  // (60) change set: sorted map (now) vs hash map (upstream change).
  final List<DocumentViewChange> changes = <DocumentViewChange>[
    for (int i = 0; i < n; i++)
      DocumentViewChange(DocumentViewChangeType.added, docs[(i * 7919) % n])
  ];
  report('DocumentViewChangeSet add 20k + getChanges (lib; was SplayTreeMap)', () {
    final DocumentViewChangeSet s = DocumentViewChangeSet();
    for (final DocumentViewChange c in changes) {
      s.addChange(c);
    }
    sink += s.getChanges().length;
  });
  report('experiment: HashMap add 20k + values.toList()', () {
    final HashMap<DocumentKey, DocumentViewChange> m =
        HashMap<DocumentKey, DocumentViewChange>();
    for (final DocumentViewChange c in changes) {
      final DocumentKey k = c.document.key;
      if (m[k] == null) {
        m[k] = c;
      }
    }
    sink += m.values.toList().length;
  });
  report('experiment: HashMap add 20k + toList + sort by key', () {
    final HashMap<DocumentKey, DocumentViewChange> m =
        HashMap<DocumentKey, DocumentViewChange>();
    for (final DocumentViewChange c in changes) {
      final DocumentKey k = c.document.key;
      if (m[k] == null) {
        m[k] = c;
      }
    }
    sink += (m.values.toList()..sort((DocumentViewChange a, DocumentViewChange b) => a.document.key.compareTo(b.document.key))).length;
  });

  // (77) ObjectValue equality / compare cost.
  final ObjectValue a = nested(8, 3, 0);
  final ObjectValue b = nested(8, 3, 0);
  report('ObjectValue == (depth 8, width 3, ~9.8k nodes)', () {
    sink += a == b ? 1 : 0;
  });
  final ObjectValue c = nested(16, 2, 0);
  final ObjectValue d = nested(16, 2, 0);
  report('ObjectValue == (depth 16, width 2, ~131k nodes)', () {
    sink += c == d ? 1 : 0;
  });
  for (final int w in <int>[1000, 4000]) {
    final ObjectValue fa = ObjectValue.fromMap(<String, FieldValue>{
      for (int i = 0; i < w; i++) 'f${i.toString().padLeft(6, '0')}': IntegerValue(i)
    });
    final ObjectValue fb = ObjectValue.fromMap(<String, FieldValue>{
      for (int i = 0; i < w; i++) 'f${i.toString().padLeft(6, '0')}': IntegerValue(i)
    });
    report('ObjectValue == (flat, $w fields)', () => sink += fa == fb ? 1 : 0);
    report('ObjectValue.compareTo (flat, $w fields)', () => sink += fa.compareTo(fb));
  }
  print('sink $sink');
}
