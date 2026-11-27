// The ```dart samples in the doc comments of the write and transaction API (database_reference.dart,
// server_value.dart, on_disconnect.dart, transaction.dart, firebase_database_exception.dart), each
// copied as it stands into a test body and run against FakeDatabaseServer. The test plays the
// server: it answers listens and writes in the order they left. Where a sample shows a result, the
// test checks it.

import 'package:firebase_database_dart/firebase_database_dart.dart';
import 'package:test/test.dart';

import 'support/fake_time.dart';
import 'support/harness.dart';

/// Runs [body] in fake time on a harness that is online.
void _sample(String name, void Function(Harness h, FirebaseDatabase db) body) {
  test(name, () {
    fakeTime((FakeTime time) {
      final Harness h = Harness(time);
      body(h, h.db);
    });
  });
}

/// Starts [sample] and returns a function that says whether it has completed; an error from
/// [sample] fails the test.
bool Function() _start(Future<void> Function() sample) {
  bool done = false;
  sample().then<void>(
    (_) => done = true,
    onError: (Object e, StackTrace s) => fail('the sample failed: $e\n$s'),
  );
  return () => done;
}

/// The value of [ref] as the client holds it now.
Object? _localValue(Harness h, DatabaseReference ref) {
  Object? value;
  bool got = false;
  ref.once().then((DatabaseEvent e) {
    value = e.snapshot.value;
    got = true;
  });
  h.settle();
  expect(got, isTrue, reason: 'the client holds no value at ${ref.key}');
  return value;
}

/// Runs the `seats/left` sample of `DatabaseReference.runTransaction` on a location the client
/// has not cached, with [serverValue] on the server, and returns its result.
TransactionResult _seats(Harness h, FirebaseDatabase db, Object? serverValue) {
  if (serverValue != null) {
    h.server.push('seats/left', serverValue);
  }
  late TransactionResult result;
  final bool Function() done = _start(() async {
    // Sample: DatabaseReference.runTransaction, lib/src/api/database_reference.dart.
    final TransactionResult r = await db.ref('seats/left').runTransaction((
      Object? v,
    ) {
      // Nothing cached yet: commit null. When the server holds a value, this runs again with it.
      if (v == null) {
        return Transaction.success(null);
      }
      final int left = v as int;
      return left == 0 ? Transaction.abort() : Transaction.success(left - 1);
    });
    // End of sample.
    result = r;
  });
  h.settle();
  // The transaction's listen is answered before its put, as the server answers in order.
  h.server.answerListen('seats/left', serverValue);
  h.settle();
  // The first put holds null with the hash of no data.
  h.server.ackNextWrite();
  h.settle();
  if (!done()) {
    // The server held other data: it answered datastale and the handler ran again on it.
    h.server.ackNextWrite();
    h.settle();
  }
  expect(done(), isTrue);
  return result;
}

void main() {
  _sample('DatabaseReference class sample: push, set, update', (
    Harness h,
    FirebaseDatabase db,
  ) {
    // A listener keeps the written data in the client's cache, to read it back.
    h.listenAnswered('S', db.ref('posts').onValue, 'posts', null);
    late DatabaseReference pushed;
    final bool Function() done = _start(() async {
      // Sample: DatabaseReference (class), lib/src/api/database_reference.dart.
      final DatabaseReference post = db.ref('posts').push();
      await post.set(<String, Object?>{
        'title': 'Hello',
        'at': ServerValue.timestamp,
      });
      await post.update(<String, Object?>{'stats/views': 0});
      // End of sample.
      pushed = post;
    });
    h.settle();
    h.server.ackNextWrite();
    h.settle();
    h.server.ackNextWrite();
    h.settle();
    expect(done(), isTrue);
    expect(pushed.parent!.key, 'posts');
    expect(h.server.requests, <String>[
      'q /posts',
      'p /posts/${pushed.key}',
      'm /posts/${pushed.key}',
    ]);
    final Map<Object?, Object?> value =
        _localValue(h, pushed)! as Map<Object?, Object?>;
    expect(value['title'], 'Hello');
    expect(value['at'], isA<int>());
    expect(value['stats'], <String, Object?>{'views': 0});
  });

  _sample('DatabaseReference.push sample', (Harness h, FirebaseDatabase db) {
    final bool Function() done = _start(() async {
      // Sample: DatabaseReference.push, lib/src/api/database_reference.dart.
      await db.ref('messages').push().set(<String, Object?>{'text': 'hi'});
      // End of sample.
    });
    h.settle();
    expect(h.server.requests.single, startsWith('p /messages/'));
    h.server.ackNextWrite();
    h.settle();
    expect(done(), isTrue);
  });

  group('DatabaseReference.runTransaction sample, nothing cached', () {
    _sample('the server holds 5: commits 4', (Harness h, FirebaseDatabase db) {
      final TransactionResult r = _seats(h, db, 5);
      expect(r.committed, isTrue);
      expect(r.snapshot.value, 4);
      expect(
        h.server.requests.where((String r) => r.startsWith('p ')).length,
        2,
      );
    });

    _sample('the server holds 0: aborts', (Harness h, FirebaseDatabase db) {
      final TransactionResult r = _seats(h, db, 0);
      expect(r.committed, isFalse);
      expect(r.snapshot.value, 0);
    });

    _sample('the server holds nothing: commits null', (
      Harness h,
      FirebaseDatabase db,
    ) {
      final TransactionResult r = _seats(h, db, null);
      expect(r.committed, isTrue);
      expect(r.snapshot.value, isNull);
    });
  });

  _sample('ServerValue class sample: timestamp and increment', (
    Harness h,
    FirebaseDatabase db,
  ) {
    h.listenAnswered(
      'S',
      db.ref('posts/1').onValue,
      'posts/1',
      <String, Object?>{'views': 41},
    );
    final bool Function() done = _start(() async {
      // Sample: ServerValue (class), lib/src/api/server_value.dart.
      await db.ref('posts/1').update(<String, Object?>{
        'updatedAt': ServerValue.timestamp,
        'views': ServerValue.increment(1),
      });
      // End of sample.
    });
    h.settle();
    h.server.ackNextWrite();
    h.settle();
    expect(done(), isTrue);
    final Map<Object?, Object?> value =
        _localValue(h, db.ref('posts/1'))! as Map<Object?, Object?>;
    expect(value['views'], 42);
    expect(value['updatedAt'], isA<int>());
  });

  test('OnDisconnect class sample: registers on connect, applied on a drop', () {
    fakeTime((FakeTime time) {
      final Harness h = Harness(time, settled: false);
      final FirebaseDatabase db = h.db;
      const String uid = 'u1';
      final List<Object?> seen = <Object?>[];
      db
          .ref('status/$uid')
          .onValue
          .listen((DatabaseEvent e) => seen.add(e.snapshot.value));

      // Sample: OnDisconnect (class), lib/src/api/on_disconnect.dart.
      db.onConnected.listen((bool connected) async {
        // ignore: always_put_control_body_on_new_line, copied from the doc comment as it is.
        if (!connected) return;
        final DatabaseReference status = db.ref('status/$uid');
        await status.onDisconnect.set('offline');
        await status.set('online');
      });
      // End of sample.

      h.settle();
      h.server.answerListen('status/$uid', null);
      h.settle();
      expect(h.server.requests, contains('o /status/$uid'));
      h.server.ackNextOnDisconnect();
      h.settle();
      expect(h.server.requests.last, 'p /status/$uid');
      h.server.ackNextWrite();
      h.settle();
      h.goDown();
      expect(seen, <Object?>[null, 'online', 'offline']);
    });
  });

  group('Transaction class sample, nothing cached', () {
    for (final (Object? server, int expected) in <(Object?, int)>[
      (3, 4),
      (null, 1),
    ]) {
      _sample('the server holds $server: commits $expected', (
        Harness h,
        FirebaseDatabase db,
      ) {
        if (server != null) {
          h.server.push('counters/likes', server);
        }
        late TransactionResult got;
        final bool Function() done = _start(() async {
          // Sample: Transaction (class), lib/src/api/transaction.dart.
          final TransactionResult result = await db
              .ref('counters/likes')
              .runTransaction(
                (Object? current) =>
                    Transaction.success(((current as num?) ?? 0) + 1),
              );
          // End of sample.
          got = result;
        });
        h.settle();
        h.server.answerListen('counters/likes', server);
        h.settle();
        h.server.ackNextWrite();
        h.settle();
        if (!done()) {
          h.server.ackNextWrite();
          h.settle();
        }
        expect(done(), isTrue);
        expect(got.committed, isTrue);
        expect(got.snapshot.value, expected);
      });
    }
  });

  _sample('FirebaseDatabaseException class sample: permission-denied', (
    Harness h,
    FirebaseDatabase db,
  ) {
    final List<String> printed = <String>[];
    // The sample's print, captured.
    void print(String line) => printed.add(line);
    final bool Function() done = _start(() async {
      // Sample: FirebaseDatabaseException (class), lib/src/api/firebase_database_exception.dart.
      try {
        await db.ref('admin/config').set(<String, Object?>{'open': true});
      } on FirebaseDatabaseException catch (e) {
        if (e.code == 'permission-denied') {
          print('Not allowed.');
        } else {
          rethrow;
        }
      }
      // End of sample.
    });
    h.settle();
    h.server.failNextWrite('permission_denied');
    h.settle();
    expect(done(), isTrue);
    expect(printed, <String>['Not allowed.']);
  });
}
