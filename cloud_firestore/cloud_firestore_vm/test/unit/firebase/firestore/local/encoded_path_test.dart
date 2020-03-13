// File created by
// Lung Razvan <long1eu>
// on 29/09/2018
import 'dart:async';

import 'package:cloud_firestore_vm/src/firebase/firestore/local/encoded_path.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/database.dart';
import 'package:test/test.dart';

import 'mock/database_mock.dart';

// ignore_for_file: prefer_interpolation_to_compose_strings

void main() {
  const String _sep = '\u0001\u0001';
  Database db;

  setUp(() async {
    db = await DatabaseMock.create(
        'firebase/firestore/local/encoded_path_test.db');
    await db.execute('CREATE TABLE keys (key TEXT PRIMARY KEY)');
  });

  tearDown(() => db.close());

  ResourcePath _path([List<String> segments = const <String>[]]) {
    return ResourcePath.fromSegments(segments);
  }

  Future<void> _assertEncoded(String expected, ResourcePath path) async {
    final String encoded = EncodedPath.encode(path);
    expect(encoded, expected);
    final ResourcePath decoded = EncodedPath.decodeResourcePath(encoded);
    expect(decoded, path);

    // Verify that the value round trips through the SQLite API too.
    await db.execute('INSERT INTO keys VALUES (?)', <String>[encoded]);
    final List<Map<String, dynamic>> result =
        await db.query('SELECT key FROM keys WHERE key = ?', <String>[encoded]);

    expect(result, isNotEmpty);
    expect(result.first.values.first, expected);
  }

  Future<void> _assertOrdered(List<ResourcePath> paths) async {
    await db.execute('DELETE FROM keys');

    // Compute the encoded forms of all the given paths
    final List<String> encoded = List<String>(paths.length);
    for (int i = 0; i < paths.length; i++) {
      encoded[i] = EncodedPath.encode(paths[i]);
    }

    // Insert those all into a table, but backwards
    await db.execute('BEGIN;');
    for (int i = encoded.length; i-- > 0;) {
      await db.execute('INSERT INTO keys VALUES (?)', <String>[encoded[i]]);
    }
    await db.execute('COMMIT;');

    // Read the values out, requiring SQLite to order the keys
    final List<String> selected = List<String>(paths.length);
    final List<Map<String, dynamic>> result =
        await db.query('SELECT key FROM keys ORDER BY key', null);

    int i = 0;
    for (Map<String, dynamic> row in result) {
      final String key = row.values.first;
      selected[i] = key;
      i++;
    }

    // Finally, verify all the orderings.
    for (int i = 0; i < paths.length; i++) {
      for (int j = 0; j < encoded.length; j++) {
        if (i < j) {
          expect(paths[i].compareTo(paths[j]), -1);
          expect(encoded[i].compareTo(encoded[j]), -1);
          expect(selected[i].compareTo(selected[j]), -1);
        } else if (i > j) {
          expect(paths[i].compareTo(paths[j]), 1);
          expect(encoded[i].compareTo(encoded[j]), 1);
          expect(selected[i].compareTo(selected[j]), 1);
        } else {
          expect(paths[i], paths[j]);
          expect(encoded[i], encoded[j]);
          expect(selected[i], selected[j]);
        }
      }
    }
  }

  void _assertPrefixSuccessorEquals(String expected, ResourcePath path) {
    expect(EncodedPath.prefixSuccessor(EncodedPath.encode(path)), expected);
  }

  test('testEncodesResourcePaths', () async {
    await _assertEncoded(_sep, _path());

    await _assertEncoded('\u0001\u0010' + _sep, _path(<String>['\u0000']));
    await _assertEncoded('\u0001\u0011' + _sep, _path(<String>['\u0001']));
    await _assertEncoded('\u0002' + _sep, _path(<String>['\u0002']));

    await _assertEncoded(
        'foo\u0001\u0010' + _sep, _path(<String>['foo\u0000']));
    await _assertEncoded(
        '\u0001\u0010foo' + _sep, _path(<String>['\u0000foo']));

    // Server specials that we don't care about here.
    await _assertEncoded('.' + _sep, _path(<String>['.']));
    await _assertEncoded('..' + _sep, _path(<String>['..']));
    await _assertEncoded('/' + _sep, _path(<String>['/']));

    await _assertEncoded(
        'a' + _sep + 'b' + _sep + 'c' + _sep, _path(<String>['a', 'b', 'c']));
    await _assertEncoded(
        'a/b' +
            _sep +
            'b.c' +
            _sep +
            'c\u0001\u0010d' +
            _sep +
            'd\u0001\u0011e' +
            _sep,
        _path(<String>['a/b', 'b.c', 'c\u0000d', 'd\u0001e']));
  });

  test('testOrdersResourcePaths', () async {
    await _assertOrdered(<ResourcePath>[
      _path(),
      _path(<String>['\u0000']),
      _path(<String>['\u0001']),
      _path(<String>['\u0002']),
      _path(<String>['\t']),
      _path(<String>[' ']),
      _path(<String>['%']),
      _path(<String>['.']),
      _path(<String>['/']),
      _path(<String>['0']),
      _path(<String>['z']),
      _path(<String>['~'])
    ]);

    await _assertOrdered(<ResourcePath>[
      _path(),
      _path(<String>['foo']),
      _path(<String>['foo', '']),
      _path(<String>['foo', 'bar']),
      _path(<String>['foo/', 'bar']),
      _path(<String>['foob']),
      _path(<String>['foobar']),
      _path(<String>['food'])
    ]);
  });

  test('testPrefixSuccessor', () {
    _assertPrefixSuccessorEquals('\u0001\u0002', _path());
    _assertPrefixSuccessorEquals(
        'foo${_sep}bar\u0001\u0002', _path(<String>['foo', 'bar']));
  });
}
