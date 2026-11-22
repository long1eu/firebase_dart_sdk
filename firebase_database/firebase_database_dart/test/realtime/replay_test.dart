// Owner P. Unit tests of the replay state (replay.dart) and the request table
// (request_table.dart): pure Dart, no connection.
import 'dart:async';

import 'package:firebase_database_dart/src/core/connection/listen_hash_provider.dart';
import 'package:firebase_database_dart/src/realtime/replay.dart';
import 'package:firebase_database_dart/src/realtime/request_table.dart';
import 'package:test/test.dart';

import '../util/persistent_connection_harness.dart';

final class _CompoundHash implements ListenHashProvider {
  @override
  String simpleHash() => 'simple';

  @override
  bool shouldIncludeCompoundHash() => true;

  @override
  WireCompoundHash compoundHash() => const WireCompoundHash(
    posts: <String>['/a/b'],
    hashes: <String>['x', ''],
  );
}

void main() {
  group('RequestTable', () {
    test(
      'numbers start at 1 and grow, also for requests without a callback',
      () {
        final RequestTable table = RequestTable(
          timeout: const Duration(minutes: 1),
        );
        expect(table.add(null), 1);
        expect(table.add((_) {}), 2);
        expect(table.add(null), 3);
        expect(table.pending, 1);
        table.clear();
      },
    );

    test('complete runs the callback once; an unknown number is ignored', () {
      final RequestTable table = RequestTable(
        timeout: const Duration(minutes: 1),
      );
      final List<Object?> bodies = <Object?>[];
      final int r = table.add(bodies.add);
      expect(
        table.complete(r + 1, const <String, Object?>{'s': 'ok'}),
        isFalse,
      );
      expect(table.complete(r, const <String, Object?>{'s': 'ok'}), isTrue);
      expect(table.complete(r, const <String, Object?>{'s': 'ok'}), isFalse);
      expect(bodies, <Object?>[
        <String, Object?>{'s': 'ok'},
      ]);
      expect(table.pending, 0);
    });

    test(
      'a request without an answer times out once and leaves the table',
      () async {
        final RequestTable table = RequestTable(
          timeout: const Duration(milliseconds: 10),
        );
        int timeouts = 0;
        final List<Object?> bodies = <Object?>[];
        final int r = table.add(bodies.add, onTimeout: () => timeouts++);
        await Future<void>.delayed(const Duration(milliseconds: 40));
        expect(timeouts, 1);
        expect(table.complete(r, const <String, Object?>{'s': 'ok'}), isFalse);
        expect(bodies, isEmpty);
      },
    );

    test('an answered request never times out', () async {
      final RequestTable table = RequestTable(
        timeout: const Duration(milliseconds: 10),
      );
      int timeouts = 0;
      final int r = table.add((_) {}, onTimeout: () => timeouts++);
      table.complete(r, const <String, Object?>{'s': 'ok'});
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(timeouts, 0);
    });

    test('clear drops every entry and cancels every timer', () async {
      final RequestTable table = RequestTable(
        timeout: const Duration(milliseconds: 10),
      );
      int calls = 0;
      table
        ..add((_) => calls++, onTimeout: () => calls++)
        ..add((_) => calls++, onTimeout: () => calls++)
        ..clear();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(calls, 0);
      expect(table.pending, 0);
    });
  });

  group('ReplayQueues', () {
    ListenRecord record(String path, {int? tag}) => ListenRecord(
      tag == null ? defaultListen(path) : taggedListen(path),
      tag,
      CountingHash(''),
      (_, _) {},
    );

    test(
      'a second listen of the same path and query is refused; another query is not',
      () {
        final ReplayQueues queues = ReplayQueues();
        expect(queues.addListen(record('/a')), isTrue);
        expect(queues.addListen(record('/a')), isFalse);
        expect(queues.addListen(record('/a', tag: 1)), isTrue);
        expect(queues.listens, hasLength(2));
      },
    );

    test('hasListen is by identity: a replaced listen does not match', () {
      final ReplayQueues queues = ReplayQueues();
      final ListenRecord first = record('/a');
      queues.addListen(first);
      queues.removeListen('/a', 'default');
      final ListenRecord second = record('/a');
      queues.addListen(second);
      expect(queues.hasListen(first), isFalse);
      expect(queues.hasListen(second), isTrue);
    });

    test(
      'removeListensAt removes every query at the path and nothing else',
      () {
        final ReplayQueues queues = ReplayQueues()
          ..addListen(record('/a'))
          ..addListen(record('/a', tag: 2))
          ..addListen(record('/a/b'));
        expect(queues.removeListensAt('/a'), hasLength(2));
        expect(queues.listens.map((ListenRecord r) => r.spec.path), <String>[
          '/a/b',
        ]);
      },
    );

    test('listens replay in the order they were made', () {
      final ReplayQueues queues = ReplayQueues()
        ..addListen(record('/z'))
        ..addListen(record('/a'))
        ..addListen(record('/m'));
      expect(queues.listens.map((ListenRecord r) => r.spec.path), <String>[
        '/z',
        '/a',
        '/m',
      ]);
    });

    test(
      'only sent transaction puts are taken at a drop; the rest stays for the replay',
      () {
        final ReplayQueues queues = ReplayQueues();
        OutstandingWrite write(
          String path, {
          required bool tx,
          required bool sent,
        }) => OutstandingWrite(
          'p',
          <String, Object?>{'p': path},
          null,
          isTransaction: tx,
        )..sent = sent;
        queues.writes.addAll(<OutstandingWrite>[
          write('/sentTx', tx: true, sent: true),
          write('/unsentTx', tx: true, sent: false),
          write('/sentPut', tx: false, sent: true),
        ]);
        final List<OutstandingWrite> taken = queues.takeSentTransactions();
        expect(taken.map((OutstandingWrite w) => w.body['p']), <Object?>[
          '/sentTx',
        ]);
        expect(
          queues.writes.map((OutstandingWrite w) => w.body['p']),
          <Object?>['/unsentTx', '/sentPut'],
        );
        queues.markAllUnsent();
        expect(queues.writes.every((OutstandingWrite w) => !w.sent), isTrue);
      },
    );

    test(
      'the listen body has p and h; q and t only with a tag; ch when asked',
      () {
        expect(record('/a').wireBody(), <String, Object?>{'p': '/a', 'h': ''});
        expect(record('/a', tag: 3).wireBody(), <String, Object?>{
          'p': '/a',
          'h': '',
          'q': <String, Object?>{'i': 'age', 'l': 10, 'vf': 'l'},
          't': 3,
        });
        final ListenRecord compound = ListenRecord(
          defaultListen('/c'),
          null,
          _CompoundHash(),
          (_, _) {},
        );
        expect(compound.wireBody(), <String, Object?>{
          'p': '/c',
          'h': 'simple',
          'ch': <String, Object?>{
            'ps': <String>['/a/b'],
            'hs': <String>['x', ''],
          },
        });
      },
    );

    test('clear empties every queue', () {
      final ReplayQueues queues = ReplayQueues()..addListen(record('/a'));
      queues.writes.add(
        OutstandingWrite('p', <String, Object?>{}, null, isTransaction: false),
      );
      queues.onDisconnects.add(
        QueuedOnDisconnect('o', <String, Object?>{}, null),
      );
      queues.gets.add(OutstandingGet(<String, Object?>{}));
      unawaited(
        queues.gets.single.completer.future.then(
          (_) {},
          onError: (Object _) {},
        ),
      );
      queues.clear();
      expect(queues.listens, isEmpty);
      expect(queues.writes, isEmpty);
      expect(queues.onDisconnects, isEmpty);
      expect(queues.gets, isEmpty);
    });
  });
}
