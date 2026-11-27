// A range merge (`rm` push) the client cannot read or apply is logged with the error's type and
// a fixed reason, as a data push is, and does not throw out of the connection delegate: the
// connection stays up and a listener still gets the next update.

import 'package:firebase_database_dart/firebase_database_dart.dart';
import 'package:firebase_database_dart/src/api/firebase_database.dart'
    show firebaseDatabaseWithConnection;
import 'package:firebase_database_dart/src/core/connection/server_actions.dart';
import 'package:firebase_database_dart/src/core/connection/wire_range_merge.dart';
import 'package:firebase_database_dart/src/testing/fake_server_actions.dart';
import 'package:test/test.dart';

import 'support/fake_time.dart';
import 'support/harness.dart';

/// A bool priority is invalid: nodeFromJson throws an ArgumentError whose text quotes it.
const Map<String, Object?> _unreadable = <String, Object?>{
  '.value': 'secret-value',
  '.priority': true,
};

/// A connected database over a [FakeServerActions] whose logger records every message, with a
/// value listener on `/a` that the server answered with `{x: 1}`.
final class _Wire {
  _Wire(this.time) {
    db = firebaseDatabaseWithConnection(
      newTestApp(),
      connectionFactory: (ServerActionsDelegate delegate, DatabaseLogger? _) =>
          server..delegate = delegate,
      logger: (DatabaseLogLevel level, String message) =>
          messages.add('${level.name}: $message'),
    );
    time.elapse(Duration.zero);
    server.connect();
    time.elapse(Duration.zero);
    db
        .ref('a')
        .onValue
        .listen(
          (DatabaseEvent e) => values.add(e.snapshot.value),
          onError: (Object e) => values.add('error $e'),
        );
    time.elapse(Duration.zero);
    server
      ..deliverDataUpdate('/a', <String, Object?>{'x': 1})
      ..respond(server.callsOf('listen').single);
    time.elapse(Duration.zero);
  }

  final FakeTime time;
  final FakeServerActions server = FakeServerActions();
  final List<String> messages = <String>[];
  final List<Object?> values = <Object?>[];
  late final FirebaseDatabase db;

  /// The connection stays up and the listener on `/a` gets a normal push after the failure.
  void expectStillWorking() {
    expect(db.isConnected, isTrue);
    server.deliverDataUpdate('/a', <String, Object?>{'x': 2});
    time.elapse(Duration.zero);
    expect(values, <Object?>[
      <String, Object?>{'x': 1},
      <String, Object?>{'x': 2},
    ]);
  }

  void expectNoDataInLogs() {
    for (final String message in messages) {
      expect(message, isNot(contains('Invalid priority')), reason: message);
      expect(message, isNot(contains('secret-value')), reason: message);
    }
  }
}

void main() {
  void timed(String name, void Function(FakeTime time) body) {
    test(name, () => fakeTime(body));
  }

  timed('a range merge the client cannot read', (FakeTime time) {
    final _Wire w = _Wire(time);
    expect(
      () => w.server.deliverRangeMerge('/a', <WireRangeMerge>[
        const WireRangeMerge(data: _unreadable),
      ]),
      returnsNormally,
    );
    time.elapse(Duration.zero);
    expect(
      w.messages,
      contains(
        'error: FIREBASE INTERNAL ERROR at /a: the server sent a range merge the '
        'client cannot read (ArgumentError)',
      ),
    );
    w.expectNoDataInLogs();
    w.expectStillWorking();
  });

  // A tagged range merge whose path is not its query's path fails the sync tree's assert
  // ("Range merge for a different path"); tests run with asserts on.
  timed('a range merge the client cannot apply', (FakeTime time) {
    final _Wire w = _Wire(time);
    w.db.ref('b').orderByChild('x').limitToFirst(2).onValue.listen((_) {});
    time.elapse(Duration.zero);
    final int tag = w.server.callsOf('listen').last.tag!;
    expect(
      () => w.server.deliverRangeMerge('/a', <WireRangeMerge>[
        const WireRangeMerge(data: <String, Object?>{'x': 3}),
      ], tag: tag),
      returnsNormally,
    );
    time.elapse(Duration.zero);
    expect(
      w.messages,
      contains(
        'error: FIREBASE INTERNAL ERROR at /a: applying a server range merge failed, '
        'in the local cache or the client (_AssertionError)',
      ),
    );
    w.expectNoDataInLogs();
    w.expectStillWorking();
  });
}
