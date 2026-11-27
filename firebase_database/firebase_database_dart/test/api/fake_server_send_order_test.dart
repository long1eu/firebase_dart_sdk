// The fakes make a test answer writes in the order they left: answering a put, merge or
// onDisconnect request while one sent before it is unanswered throws, unless the test passes
// `outOfOrder: true`. After a reconnect puts and merges leave before the onDisconnect requests
// made offline, as `PersistentConnection._replay` sends them. That the server answers writes in
// send order is inferred from `rtdb_emulator_probe.md` addendum 2 item 4 (listens and gets
// answered in order; no write measured). The fakes do not check the order of listens and gets.

import 'package:firebase_database_dart/src/core/connection/server_actions.dart';
import 'package:firebase_database_dart/src/testing/fake_server_actions.dart';
import 'package:firebase_database_dart/src/testing/recording_server_actions_delegate.dart';
import 'package:test/test.dart';

import 'support/fake_time.dart';
import 'support/harness.dart';

void main() {
  void scenario(String name, void Function(Harness h) body) {
    test(name, () {
      fakeTime((FakeTime time) => body(Harness(time)));
    });
  }

  Matcher outOfOrderError(String answered, String earlier) => throwsA(
    isA<StateError>().having(
      (StateError e) => e.message,
      'message',
      allOf(contains("answers '$answered'"), contains("while '$earlier'")),
    ),
  );

  group('FakeDatabaseServer', () {
    scenario('ackLastWrite with an earlier write unanswered throws, naming '
        'both', (Harness h) {
      h.track('W1', h.ref('a').set(1));
      h.track('W2', h.ref('b').set(2));
      h.settle();
      expect(h.server.ackLastWrite, outOfOrderError('p /b', 'p /a'));
      expect(
        () => h.server.failLastWrite('permission_denied'),
        outOfOrderError('p /b', 'p /a'),
      );
      h.settle();
      expect(h.log, isEmpty);
    });

    scenario('ackNextWrite and failNextWrite answer the oldest write', (
      Harness h,
    ) {
      h.track('W1', h.ref('a').set(1));
      h.track('W2', h.ref('b').set(2));
      h.track('W3', h.ref('c').set(3));
      h.settle();
      h.server.ackNextWrite();
      h.server.failNextWrite('permission_denied');
      h.server.ackNextWrite();
      h.settle();
      expect(h.log, <String>['W1:ok', 'W2:E(permission-denied)', 'W3:ok']);
    });

    scenario('outOfOrder: true answers the newest write', (Harness h) {
      h.track('W1', h.ref('a').set(1));
      h.track('W2', h.ref('b').set(2));
      h.settle();
      h.server.ackLastWrite(outOfOrder: true);
      h.settle();
      expect(h.log, <String>['W2:ok']);
    });

    scenario('onDisconnect requests are ordered with writes', (Harness h) {
      h.track('O', h.ref('a').onDisconnect.set(0));
      h.track('W', h.ref('b').set(2));
      h.settle();
      expect(h.server.ackLastWrite, outOfOrderError('p /b', 'o /a'));
      h.server.ackNextOnDisconnect();
      h.server.ackNextWrite();
      h.settle();
      expect(h.log, <String>['O:ok', 'W:ok']);
    });

    scenario('the order of a listen against a later write is not checked', (
      Harness h,
    ) {
      h.listen('S', h.ref('a').onValue);
      h.settle();
      h.track('W', h.ref('b').set(2));
      h.settle();
      h.server.ackLastWrite();
      h.settle();
      h.server.answerListen('a', 1);
      h.settle();
      expect(h.log, <String>['W:ok', 'S:V(1)']);
    });

    scenario(
      'after a reconnect a set made offline leaves before an onDisconnect made offline',
      (Harness h) {
        h.goDown();
        h.track('O', h.ref('a').onDisconnect.set(0));
        h.track('W', h.ref('b').set(2));
        h.reconnect();
        final List<String> writes = <String>[
          for (final String r in h.server.requests)
            if (r.startsWith('p') || r.startsWith('o')) r,
        ];
        expect(writes, <String>['p /b', 'o /a']);
        expect(h.server.ackNextOnDisconnect, outOfOrderError('o /a', 'p /b'));
        h.server.ackNextWrite();
        h.server.ackNextOnDisconnect();
        h.settle();
        expect(h.log, <String>['W:ok', 'O:ok']);
      },
    );

    scenario(
      'a write resent after a drop is answered before the writes made offline',
      (Harness h) {
        h.track('X', h.ref('x').set(1));
        h.settle();
        h.goDown();
        h.track('O', h.ref('a').onDisconnect.set(0));
        h.track('Y', h.ref('y').set(2));
        h.reconnect();
        h.server.ackNextWrite();
        h.server.ackNextWrite();
        h.server.ackNextOnDisconnect();
        h.settle();
        expect(h.log, <String>['X:ok', 'Y:ok', 'O:ok']);
      },
    );
  });

  group('FakeServerActions', () {
    late FakeServerActions server;
    setUp(() {
      server = FakeServerActions(RecordingServerActionsDelegate())..connect();
    });

    test('respond to a later write throws; the oldest first works', () {
      final List<String> done = <String>[];
      server
        ..put('/a', 1, onComplete: (String s, Object? _) => done.add('a:$s'))
        ..merge('/b', <String, Object?>{
          'c': 2,
        }, onComplete: (String s, Object? _) => done.add('b:$s'));
      final ServerCall later = server.callsOf('merge').single;
      expect(
        () => server.respond(later),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            allOf(contains('merge /b'), contains('put /a')),
          ),
        ),
      );
      expect(server.ackLastWrite, throwsStateError);
      server
        ..ackNextWrite()
        ..ackNextWrite();
      expect(done, <String>['a:ok', 'b:ok']);
    });

    test('outOfOrder: true answers a later write', () {
      final List<String> done = <String>[];
      server
        ..put('/a', 1, onComplete: (String s, Object? _) => done.add('a:$s'))
        ..put('/b', 2, onComplete: (String s, Object? _) => done.add('b:$s'))
        ..failLastWrite('permission_denied', outOfOrder: true);
      expect(done, <String>['b:permission_denied']);
    });

    test('connect replays puts before onDisconnect requests made offline', () {
      final List<String> done = <String>[];
      server
        ..disconnect()
        ..onDisconnectPut(
          '/a',
          0,
          onComplete: (String s, Object? _) => done.add('a:$s'),
        )
        ..put('/b', 2, onComplete: (String s, Object? _) => done.add('b:$s'));
      expect(
        server.ackNextOnDisconnect,
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('No sent, unanswered request'),
          ),
        ),
      );
      server.connect();
      expect(
        server.ackNextOnDisconnect,
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            allOf(
              contains('ackNextOnDisconnect answers'),
              contains('onDisconnectPut /a'),
              contains('put /b'),
            ),
          ),
        ),
      );
      server
        ..ackNextWrite()
        ..ackNextOnDisconnect();
      expect(done, <String>['b:ok', 'a:ok']);
    });

    test('a write made offline cannot be answered before connect', () {
      server
        ..disconnect()
        ..put('/a', 1);
      expect(
        () => server.respond(server.callsOf('put').single),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains(
              'respond answers ServerCall(put /a) (call 0), which was not sent',
            ),
          ),
        ),
      );
    });

    test(
      'isConnected set by hand forgets and replays as disconnect and connect do',
      () {
        final List<String> done = <String>[];
        server
          ..onDisconnectPut(
            '/a',
            0,
            onComplete: (String s, Object? _) => done.add('a:$s'),
          )
          ..isConnected = false
          ..put('/b', 2, onComplete: (String s, Object? _) => done.add('b:$s'));
        expect(
          () => server.respond(server.callsOf('onDisconnectPut').single),
          throwsA(
            isA<StateError>().having(
              (StateError e) => e.message,
              'message',
              contains('sent before the last disconnect()'),
            ),
          ),
        );
        server
          ..isConnected = true
          ..ackNextWrite()
          ..ackNextOnDisconnect();
        expect(done, <String>['b:ok', 'a:ok']);
      },
    );

    test('disconnect answers a sent transaction put behind a plain put', () {
      final List<String> done = <String>[];
      server
        ..put('/a', 1, onComplete: (String s, Object? _) => done.add('a:$s'))
        ..put(
          '/b',
          2,
          hash: 'h',
          onComplete: (String s, Object? _) => done.add('b:$s'),
        )
        ..disconnect();
      expect(done, <String>['b:$statusDisconnect']);
    });
  });
}
