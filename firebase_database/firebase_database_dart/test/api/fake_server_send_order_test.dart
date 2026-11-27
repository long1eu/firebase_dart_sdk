// The fakes answer writes in send order, as a server answers one connection's requests (emulator
// probe item 4): answering a put, merge or onDisconnect request while one sent before it is
// unanswered throws, unless the test passes `outOfOrder: true`. Listens and gets are not ordered.

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

    scenario('a listen may be answered after a later write', (Harness h) {
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
