// Owner P. Unit tests of the replay state (replay.dart) and the request table
// (request_table.dart): pure Dart, no connection.
import 'dart:async';

import 'package:fake_async/fake_async.dart';
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
    RequestTable table({void Function()? onSilence}) => RequestTable(
      timeout: const Duration(milliseconds: 100),
      onSilence: onSilence ?? () {},
    );

    test(
      'numbers start at 1 and grow, also for requests without a callback',
      () {
        final RequestTable requests = table();
        expect(requests.add(null), 1);
        expect(requests.add((_) {}), 2);
        expect(requests.add(null), 3);
        expect(requests.pending, 1);
        requests.clear();
      },
    );

    test('complete runs the callback once; an unknown number is ignored', () {
      final RequestTable requests = table();
      final List<Object?> bodies = <Object?>[];
      final int r = requests.add(bodies.add);
      expect(
        requests.complete(r + 1, const <String, Object?>{'s': 'ok'}),
        isFalse,
      );
      expect(requests.complete(r, const <String, Object?>{'s': 'ok'}), isTrue);
      expect(requests.complete(r, const <String, Object?>{'s': 'ok'}), isFalse);
      expect(bodies, <Object?>[
        <String, Object?>{'s': 'ok'},
      ]);
      expect(requests.pending, 0);
    });

    test('silence with a request waiting reports once per silent period', () {
      fakeAsync((FakeAsync async) {
        int silences = 0;
        final RequestTable requests = table(onSilence: () => silences++);
        requests.add((_) {});
        async.elapse(const Duration(milliseconds: 99));
        expect(silences, 0);
        async.elapse(const Duration(milliseconds: 2));
        expect(silences, 1);
        async.elapse(const Duration(seconds: 1));
        expect(silences, 1);
      });
    });

    test(
      'every inbound frame re-arms the timer: a long download never times out',
      () {
        fakeAsync((FakeAsync async) {
          int silences = 0;
          final RequestTable requests = table(onSilence: () => silences++);
          requests.add((_) {});
          for (int i = 0; i < 50; i++) {
            async.elapse(const Duration(milliseconds: 60));
            requests.linkActivity();
          }
          expect(silences, 0);
          async.elapse(const Duration(milliseconds: 101));
          expect(silences, 1);
        });
      },
    );

    test('nothing is timed while nothing waits; answers stop the timer', () {
      fakeAsync((FakeAsync async) {
        int silences = 0;
        final RequestTable requests = table(onSilence: () => silences++);
        requests
          ..add(null)
          ..linkActivity();
        async.elapse(const Duration(seconds: 1));
        expect(silences, 0);
        final int r = requests.add((_) {});
        requests.complete(r, const <String, Object?>{'s': 'ok'});
        async.elapse(const Duration(seconds: 1));
        expect(silences, 0);
      });
    });

    test('clear drops every entry and stops the timer', () {
      fakeAsync((FakeAsync async) {
        int calls = 0;
        final RequestTable requests = table(onSilence: () => calls++);
        requests
          ..add((_) => calls++)
          ..add((_) => calls++)
          ..clear();
        async.elapse(const Duration(seconds: 1));
        expect(calls, 0);
        expect(requests.pending, 0);
      });
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

    test(
      'sent onDisconnect requests are taken once at a drop, never replayed',
      () {
        final ReplayQueues queues = ReplayQueues();
        final QueuedOnDisconnect sent = QueuedOnDisconnect(
          'o',
          <String, Object?>{},
          null,
        );
        final QueuedOnDisconnect offline = QueuedOnDisconnect(
          'om',
          <String, Object?>{},
          null,
        );
        queues.sentOnDisconnects.add(sent);
        queues.onDisconnects.add(offline);
        expect(queues.takeSentOnDisconnects(), <QueuedOnDisconnect>[sent]);
        expect(queues.takeSentOnDisconnects(), isEmpty);
        expect(queues.onDisconnects, <QueuedOnDisconnect>[offline]);
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
