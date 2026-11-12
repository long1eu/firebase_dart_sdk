import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/util.dart' as u;

const int n = 100000;
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
  print('${name.padRight(46)} median ${t[reps ~/ 2].toStringAsFixed(2).padLeft(9)} ms'
      '  min ${t.first.toStringAsFixed(2).padLeft(9)}  max ${t.last.toStringAsFixed(2).padLeft(9)}');
}

// ---- experiment copies (NOT the lib) ----
void hardAssertCopy(bool c, String m) {
  if (!c) throw AssertionError(m);
}

@pragma('vm:prefer-inline')
void hardAssertInline(bool c, String m) {
  if (!c) throw AssertionError(m);
}

int _dyn(dynamic a, dynamic b) => (a as Comparable<dynamic>).compareTo(b);
int typedStr(String a, String b) => a.compareTo(b);
int typedInt(int a, int b) => a.compareTo(b);
@pragma('vm:prefer-inline')
int typedStrInl(String a, String b) => a.compareTo(b);

void main() {
  final List<int> order = List<int>.generate(n, (int i) => (i * 7919) % n);
  final List<String> names = <String>[for (int i in order) 'doc${i.toString().padLeft(6, '0')}'];

  // (0) key construction (includes eager hardAssert message in ctor)
  List<DocumentKey> keys = <DocumentKey>[];
  report('DocumentKey.fromPathString x100k', () {
    keys = <DocumentKey>[for (String s in names) DocumentKey.fromPathString('coll/$s')];
  });

  // (1) map/set with DocumentKey ordering
  ImmutableSortedMap<DocumentKey, int> map = ImmutableSortedMap<DocumentKey, int>.emptyMap(DocumentKey.comparator);
  report('map insert 100k (DocumentKey.comparator)', () {
    map = ImmutableSortedMap<DocumentKey, int>.emptyMap(DocumentKey.comparator);
    for (int i = 0; i < n; i++) {
      map = map.insert(keys[i], i);
    }
  }, warm: 1);
  report('map lookup 100k (DocumentKey.comparator)', () {
    for (int i = 0; i < n; i++) {
      sink += map[keys[i]] ?? 0;
    }
  });
  report('map fromMap 100k (DocumentKey.comparator)', () {
    final Map<DocumentKey, int> m = <DocumentKey, int>{for (int i = 0; i < n; i++) keys[i]: i};
    map = ImmutableSortedMap<DocumentKey, int>.fromMap(m, DocumentKey.comparator);
  }, warm: 1);
  report('set insert 100k (DocumentKey.comparator)', () {
    ImmutableSortedSet<DocumentKey> s = ImmutableSortedSet<DocumentKey>(<DocumentKey>[], DocumentKey.comparator);
    for (int i = 0; i < n; i++) {
      s = s.insert(keys[i]);
    }
    sink += s.length;
  }, warm: 1);
  report('map insert 100k (u.comparator<DocumentKey>)', () {
    ImmutableSortedMap<DocumentKey, int> m = ImmutableSortedMap<DocumentKey, int>.emptyMap(u.comparator<DocumentKey>());
    for (int i = 0; i < n; i++) {
      m = m.insert(keys[i], i);
    }
    sink += m.length;
  }, warm: 1);

  // (2) dynamic vs typed comparator
  Comparator<String> dynS = u.comparator<String>();
  Comparator<int> dynI = u.comparator<num>();
  void ins<K>(Comparator<K> c, List<K> ks) {
    ImmutableSortedMap<K, int> m = ImmutableSortedMap<K, int>.emptyMap(c);
    for (int i = 0; i < ks.length; i++) {
      m = m.insert(ks[i], i);
    }
    sink += m.length;
  }
  report('String map insert 100k, u.comparator (dynamic)', () => ins<String>(dynS, names));
  report('String map insert 100k, typed comparator', () => ins<String>(typedStr, names));
  report('int map insert 100k, u.comparator (dynamic)', () => ins<int>(dynI, order));
  report('int map insert 100k, typed comparator', () => ins<int>(typedInt, order));
  report('String 10M raw compares, dynamic', () {
    int s = 0;
    for (int i = 0; i < 10000000; i++) {
      s += dynS(names[i % 1000], names[(i + 1) % 1000]);
    }
    sink += s;
  });
  report('String 10M raw compares, typed', () {
    int s = 0;
    for (int i = 0; i < 10000000; i++) {
      s += typedStr(names[i % 1000], names[(i + 1) % 1000]);
    }
    sink += s;
  });
  report('String 10M raw compares, typed prefer-inline', () {
    int s = 0;
    for (int i = 0; i < 10000000; i++) {
      s += typedStrInl(names[i % 1000], names[(i + 1) % 1000]);
    }
    sink += s;
  });

  // (3) hardAssert
  const int m = 10000000;
  report('hardAssert x10M constant msg (lib)', () {
    for (int i = 0; i < m; i++) {
      hardAssert(i >= 0, 'Not a document key path');
    }
  });
  report('hardAssert x10M interpolated msg (lib)', () {
    for (int i = 0; i < m; i++) {
      hardAssert(i >= 0, 'Not a document key path: $i ${names[i % 1000]}');
    }
  });
  final dynamic p = keys[0].path;
  report('hardAssert x1M interp. path.toString (lib)', () {
    for (int i = 0; i < 1000000; i++) {
      hardAssert(i >= 0, 'Not a document key path: $p');
    }
  });
  report('copy hardAssert x10M interpolated', () {
    for (int i = 0; i < m; i++) {
      hardAssertCopy(i >= 0, 'Not a document key path: $i ${names[i % 1000]}');
    }
  });
  report('copy hardAssert prefer-inline x10M interp.', () {
    for (int i = 0; i < m; i++) {
      hardAssertInline(i >= 0, 'Not a document key path: $i ${names[i % 1000]}');
    }
  });
  report('lazy: if(!c) hardAssert(...) x10M interp.', () {
    for (int i = 0; i < m; i++) {
      if (!(i >= 0)) hardAssert(false, 'Not a document key path: $i ${names[i % 1000]}');
    }
  });
  print('sink $sink');
}
