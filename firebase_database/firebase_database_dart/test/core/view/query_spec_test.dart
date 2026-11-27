// QuerySpec (Android core/view/QuerySpec.java) and its ListenSpec form.
import 'package:firebase_database_dart/src/core/connection/listen_spec.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/path_index.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/priority_index.dart';
import 'package:firebase_database_dart/src/core/snap/node_from_json.dart';
import 'package:firebase_database_dart/src/core/view/query_params.dart';
import 'package:firebase_database_dart/src/core/view/query_spec.dart';
import 'package:test/test.dart';

void main() {
  test('default query at a path', () {
    final QuerySpec spec = QuerySpec.defaultAt(Path('a/b'));
    expect(spec.isDefault, isTrue);
    expect(spec.loadsAllData, isTrue);
    expect(spec.index, priorityIndex);
    final ListenSpec listen = spec.toListenSpec();
    expect(listen.path, '/a/b');
    expect(listen.queryObject, isEmpty);
    expect(listen.queryIdentifier, 'default');
    expect(listen.isDefault, isTrue);
    expect(listen.loadsAllData, isTrue);
    expect(listen.indexName, '.priority');
  });

  test('a limited query', () {
    final QueryParams params = QueryParams.defaultParams
        .orderBy(PathIndex(Path('age')))
        .startAt(nodeFromJson(30))
        .limitToFirst(10);
    final QuerySpec spec = QuerySpec(Path('users'), params);
    final ListenSpec listen = spec.toListenSpec();
    expect(listen.path, '/users');
    expect(listen.queryObject, <String, Object?>{
      'sp': 30,
      'sin': true,
      'l': 10,
      'vf': 'l',
      'i': 'age',
    });
    expect(
      listen.queryIdentifier,
      '{"i":"age","l":10,"sin":true,"sp":30,"vf":"l"}',
    );
    expect(listen.isDefault, isFalse);
    expect(listen.loadsAllData, isFalse);
    expect(listen.indexName, 'age');
  });

  test('root path is /', () {
    expect(QuerySpec.defaultAt(Path.empty).toListenSpec().path, '/');
  });

  test('fromPathAndWireObject and equality', () {
    final QueryParams params = QueryParams.defaultParams
        .orderBy(PathIndex(Path('age')))
        .limitToLast(3);
    final QuerySpec spec = QuerySpec(Path('p'), params);
    final QuerySpec parsed = QuerySpec.fromPathAndWireObject(
      Path('p'),
      params.toWireObject(),
    );
    expect(parsed, spec);
    expect(parsed.hashCode, spec.hashCode);
    expect(parsed == QuerySpec(Path('q'), params), isFalse);
    expect(spec == QuerySpec.defaultAt(Path('p')), isFalse);
    expect(spec.toString(), '/p:{"i":"age","l":3,"vf":"r"}');
  });

  test('toWireObject round-trips through fromPathAndWireObject', () {
    final Map<String, QuerySpec> specs = <String, QuerySpec>{
      'default': QuerySpec.defaultAt(Path('p')),
      'limit with orderByChild': QuerySpec(
        Path('p'),
        QueryParams.defaultParams
            .orderBy(PathIndex(Path('age')))
            .limitToFirst(2),
      ),
      'range': QuerySpec(
        Path('p'),
        QueryParams.defaultParams
            .orderBy(PathIndex(Path('age')))
            .startAt(nodeFromJson(18), ChildKey('a'))
            .endBefore(nodeFromJson('z')),
      ),
    };
    expect(specs['default']!.toWireObject(), isEmpty);
    for (final MapEntry<String, QuerySpec> entry in specs.entries) {
      final QuerySpec spec = entry.value;
      final Map<String, Object?> wire = spec.toWireObject();
      expect(wire, spec.params.toWireObject(), reason: entry.key);
      expect(
        QuerySpec.fromPathAndWireObject(spec.path, wire),
        spec,
        reason: entry.key,
      );
    }
  });
}
