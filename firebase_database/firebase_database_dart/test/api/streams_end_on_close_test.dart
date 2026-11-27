// A close() or an app deletion is not a failure: every stream the client hands out ends with done
// and no error event, so a listener without onError survives it. Futures still fail with
// database-closed, and a stream still gets an error for a real failure.

import 'dart:async';

import 'package:firebase_database_dart/firebase_database_dart.dart';
import 'package:test/test.dart';

import 'support/fake_time.dart';
import 'support/harness.dart';

/// The streams under test, each listened to without onError.
final Map<String, Stream<Object?> Function(FirebaseDatabase db)> _streams =
    <String, Stream<Object?> Function(FirebaseDatabase db)>{
      'onConnected': (FirebaseDatabase db) => db.onConnected,
      'onValue': (FirebaseDatabase db) => db.ref('a').onValue,
      'onChildAdded': (FirebaseDatabase db) => db.ref('a').onChildAdded,
      'onChildChanged': (FirebaseDatabase db) => db.ref('a').onChildChanged,
      'onChildMoved': (FirebaseDatabase db) => db.ref('a').onChildMoved,
      'onChildRemoved': (FirebaseDatabase db) => db.ref('a').onChildRemoved,
      'onChildEvents': (FirebaseDatabase db) => db.ref('a').onChildEvents,
      'query onValue': (FirebaseDatabase db) =>
          db.ref('q').orderByChild('n').limitToFirst(2).onValue,
    };

/// Listens to every stream of [_streams] without onError, inside a zone that records uncaught
/// errors in [uncaught]; logs `name:event` and `name:done`.
void _listenAll(Harness h, List<Object> uncaught) {
  runZonedGuarded(() {
    for (final MapEntry<String, Stream<Object?> Function(FirebaseDatabase)> e
        in _streams.entries) {
      e
          .value(h.db)
          .listen(
            (Object? _) => h.log.add('${e.key}:event'),
            onDone: () => h.log.add('${e.key}:done'),
          );
    }
  }, (Object error, StackTrace _) => uncaught.add(error));
  h.settle();
  // One listen answered (the default listen at `a`, which every `a` stream shares).
  h.server.answerListen('a', <String, Object?>{'x': 1});
  h.settle();
}

/// Every stream logged done, and nothing reached the zone's error handler.
void _expectAllDone(Harness h, List<Object> uncaught) {
  expect(uncaught, isEmpty);
  for (final String name in _streams.keys) {
    expect(h.named(name).last, '$name:done', reason: name);
    expect(
      h.named(name).where((String e) => e.endsWith(':done')),
      hasLength(1),
    );
  }
  expect(h.log.where((String e) => e.contains('E(')), isEmpty);
}

void _scenario(String name, void Function(Harness h) body) {
  test(name, () => fakeTime((FakeTime time) => body(Harness(time))));
}

void main() {
  _scenario('close(): every stream ends with done, no uncaught error', (
    Harness h,
  ) {
    final List<Object> uncaught = <Object>[];
    _listenAll(h, uncaught);
    expect(h.named('onConnected'), <String>['onConnected:event']);
    expect(h.named('onValue'), <String>['onValue:event']);

    unawaited(h.db.close());
    h.settle();
    h.elapse(const Duration(minutes: 1));
    _expectAllDone(h, uncaught);
    expect(h.db.isConnected, isFalse);
  });

  _scenario('app deleted: every stream ends with done, no uncaught error', (
    Harness h,
  ) {
    final List<Object> uncaught = <Object>[];
    _listenAll(h, uncaught);

    h.app.delete();
    h.settle();
    _expectAllDone(h, uncaught);
    expect(h.db.isConnected, isFalse);
  });

  _scenario('a listen refused by the server still delivers its error', (
    Harness h,
  ) {
    h.listen('S', h.ref('s').onValue);
    h.settle();
    h.server.failListen('s', 'permission_denied');
    h.settle();
    expect(h.log, <String>['S:E(permission-denied)', 'S:done']);
  });

  _scenario('a listen cancelled by the server still delivers its error', (
    Harness h,
  ) {
    h.listenAnswered('S', h.ref('s').onValue, 's', 1);
    h.server.cancelListen('s', 'permission_denied');
    h.settle();
    expect(h.log, <String>['S:V(1)', 'S:E(permission-denied)', 'S:done']);
  });

  _scenario('pending Futures still fail with database-closed', (Harness h) {
    h.track('W', h.ref('w').set(1));
    h.trackValue('G', h.ref('g').get());
    h.trackEvent('O', h.ref('o').once());
    h.trackTransaction(
      'T',
      h.ref('t').runTransaction((Object? v) => Transaction.success(1)),
    );
    h.track('D', h.ref('d').onDisconnect.set(1));
    h.settle();
    expect(h.log, isEmpty);

    unawaited(h.db.close());
    h.settle();
    expect(
      h.log,
      unorderedEquals(<String>[
        'W:E(database-closed)',
        'G:E(database-closed)',
        'O:E(database-closed)',
        'T:E(database-closed)',
        'D:E(database-closed)',
      ]),
    );
  });

  _scenario('streams listened to after close end with done and no error', (
    Harness h,
  ) {
    unawaited(h.db.close());
    h.settle();
    final List<Object> uncaught = <Object>[];
    runZonedGuarded(() {
      h.db.onConnected.listen(
        (bool c) => h.log.add('C:$c'),
        onDone: () => h.log.add('C:done'),
      );
      h
          .ref('a')
          .onValue
          .listen(
            (DatabaseEvent _) => h.log.add('S:event'),
            onDone: () => h.log.add('S:done'),
          );
    }, (Object error, StackTrace _) => uncaught.add(error));
    h.settle();
    expect(uncaught, isEmpty);
    expect(h.log, unorderedEquals(<String>['C:done', 'S:done']));
    expect(h.server.requests.where((String r) => r.startsWith('q ')), isEmpty);
  });
}
