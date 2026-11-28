@TestOn('browser')
@Tags(<String>['browser'])
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:firebase_installations_dart/web.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

int _counter = 0;

/// A database name no other test (or earlier run in the same profile) uses.
String _freshName() =>
    'fis_test_${DateTime.now().microsecondsSinceEpoch}_${_counter++}';

Future<void> _deleteDatabase(String name) {
  final Completer<void> done = Completer<void>();
  final web.IDBOpenDBRequest request = web.window.indexedDB.deleteDatabase(
    name,
  );
  request.onsuccess = ((web.Event _) => done.complete()).toJS;
  request.onerror = ((web.Event _) => done.complete()).toJS;
  request.onblocked = ((web.Event _) {}).toJS;
  return done.future;
}

/// Two stores over one database, as two tabs (or two apps) of one page would have.
Future<(IndexedDbKeyValueStore, IndexedDbKeyValueStore)> _pair() async {
  final String name = _freshName();
  final IndexedDbKeyValueStore a = IndexedDbKeyValueStore(databaseName: name);
  final IndexedDbKeyValueStore b = IndexedDbKeyValueStore(databaseName: name);
  addTearDown(() async {
    await a.close();
    await b.close();
    await _deleteDatabase(name);
  });
  return (a, b);
}

void main() {
  test(
    '5.2.2 read of an absent key is null; write, update and delete round trip',
    () async {
      final (IndexedDbKeyValueStore a, _) = await _pair();
      expect(await a.read('k'), isNull);
      await a.write('k', 'v1');
      expect(await a.read('k'), 'v1');
      expect(await a.update('k', (String? current) => '$current+'), 'v1+');
      expect(await a.read('k'), 'v1+');
      await a.write('k', null);
      expect(await a.read('k'), isNull);
      expect(await a.update('k', (String? current) => null), isNull);
      expect(await a.read('k'), isNull);
    },
  );

  test('5.2.2 update is atomic between two stores in one page', () async {
    final (IndexedDbKeyValueStore a, IndexedDbKeyValueStore b) = await _pair();
    String increment(String? current) =>
        '${(int.tryParse(current ?? '') ?? 0) + 1}';

    final List<Future<String?>> updates = <Future<String?>>[];
    for (int i = 0; i < 25; i++) {
      updates
        ..add(a.update('counter', increment))
        ..add(b.update('counter', increment));
    }
    final List<String?> results = await Future.wait(updates);

    expect(await a.read('counter'), '50');
    expect(await b.read('counter'), '50');
    expect(
      results.map((String? value) => int.parse(value!)).toSet(),
      hasLength(50),
      reason: 'every update saw a different current value',
    );
  });

  test('5.2.2 a transform that throws writes nothing and rethrows', () async {
    final (IndexedDbKeyValueStore a, _) = await _pair();
    await a.write('k', 'before');
    await expectLater(
      a.update('k', (String? _) => throw const FormatException('boom')),
      throwsA(isA<FormatException>()),
    );
    expect(await a.read('k'), 'before');
    // The store keeps working after the aborted transaction.
    expect(await a.update('k', (String? current) => '$current!'), 'before!');
  });

  test(
    '5.2.2 on versionchange the connection closes itself, so an upgrade is not blocked',
    () async {
      final String name = _freshName();
      final IndexedDbKeyValueStore store = IndexedDbKeyValueStore(
        databaseName: name,
      );
      addTearDown(() async {
        await store.close();
        await _deleteDatabase(name);
      });
      await store.write('k', 'v');

      final Completer<web.IDBDatabase> upgraded = Completer<web.IDBDatabase>();
      final web.IDBOpenDBRequest request = web.window.indexedDB.open(name, 2);
      request.onsuccess = ((web.Event _) {
        upgraded.complete(request.result! as web.IDBDatabase);
      }).toJS;
      request.onerror = ((web.Event _) {
        upgraded.completeError(StateError('the upgrade failed'));
      }).toJS;

      final web.IDBDatabase database = await upgraded.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw StateError(
          'the upgrade to version 2 never completed: the store kept its connection open',
        ),
      );
      database.close();
      expect(database.version, 2);
    },
  );

  test(
    '5.2.2 changes emits the key another store wrote, never the value',
    () async {
      final (IndexedDbKeyValueStore a, IndexedDbKeyValueStore b) =
          await _pair();
      final Future<List<String>> seen = a.changes.take(2).toList();

      await b.write('first', 'secret-value-1');
      await b.update('second', (String? _) => 'secret-value-2');

      expect(await seen.timeout(const Duration(seconds: 10)), <String>[
        'first',
        'second',
      ]);
    },
  );

  test('5.2.2 a store does not announce its own writes to itself', () async {
    final (IndexedDbKeyValueStore a, _) = await _pair();
    final List<String> seen = <String>[];
    final StreamSubscription<String> subscription = a.changes.listen(seen.add);
    addTearDown(subscription.cancel);

    await a.write('mine', 'v');
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(seen, isEmpty);
  });

  test('5.2.2 a failed (aborted) update announces nothing', () async {
    final (IndexedDbKeyValueStore a, IndexedDbKeyValueStore b) = await _pair();
    final List<String> seen = <String>[];
    final StreamSubscription<String> subscription = a.changes.listen(seen.add);
    addTearDown(subscription.cancel);

    await expectLater(
      b.update('k', (String? _) => throw StateError('no')),
      throwsStateError,
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(seen, isEmpty);
  });

  test(
    '5.2.2 forged hints (not JSON, wrong shape, non-string key) are ignored',
    () async {
      final String name = _freshName();
      final IndexedDbKeyValueStore store = IndexedDbKeyValueStore(
        databaseName: name,
      );
      final web.BroadcastChannel forger = web.BroadcastChannel(name);
      addTearDown(() async {
        forger.close();
        await store.close();
        await _deleteDatabase(name);
      });
      final List<String> seen = <String>[];
      final Completer<void> sentinel = Completer<void>();
      final StreamSubscription<String> subscription = store.changes.listen((
        String key,
      ) {
        seen.add(key);
        if (key == 'sentinel') {
          sentinel.complete();
        }
      });
      addTearDown(subscription.cancel);

      for (final String forged in <String>[
        'not json',
        '',
        '[]',
        '"key"',
        'null',
        '42',
        '{}',
        '{"key": null}',
        '{"key": 5}',
        '{"key": ["a"]}',
        '{"key": {"a": 1}}',
        '{"k": "x"}',
        '{"key": "unterminated',
      ]) {
        forger.postMessage(forged.toJS);
      }
      forger.postMessage(42.toJS);
      forger.postMessage(null);
      forger.postMessage(<String, String>{'key': 'object-not-string'}.jsify());
      forger.postMessage('{"key":"sentinel"}'.toJS);
      await sentinel.future.timeout(const Duration(seconds: 10));

      expect(seen, <String>['sentinel']);
    },
  );

  test(
    '5.2.2 a well-formed hint from another page emits its key and nothing else',
    () async {
      final String name = _freshName();
      final IndexedDbKeyValueStore store = IndexedDbKeyValueStore(
        databaseName: name,
      );
      final web.BroadcastChannel other = web.BroadcastChannel(name);
      addTearDown(() async {
        other.close();
        await store.close();
        await _deleteDatabase(name);
      });
      final Future<String> first = store.changes.first;

      other.postMessage('{"key":"k","value":"v"}'.toJS);

      expect(await first.timeout(const Duration(seconds: 10)), 'k');
      expect(await store.read('k'), isNull, reason: 'a hint carries no value');
    },
  );

  test(
    '5.2.2 stores over different database names do not hear each other',
    () async {
      final (IndexedDbKeyValueStore a, _) = await _pair();
      final (IndexedDbKeyValueStore c, _) = await _pair();
      final List<String> seen = <String>[];
      final StreamSubscription<String> subscription = a.changes.listen(
        seen.add,
      );
      addTearDown(subscription.cancel);

      await c.write('k', 'v');
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(seen, isEmpty);
    },
  );

  test('5.2.2 after close, calls fail and changes completes', () async {
    final (IndexedDbKeyValueStore a, _) = await _pair();
    final Future<void> done = a.changes.drain<void>();
    await a.write('k', 'v');
    await a.close();
    await a.close();

    await done.timeout(const Duration(seconds: 10));
    await expectLater(a.read('k'), throwsStateError);
    await expectLater(a.write('k', 'w'), throwsStateError);
  });
}
