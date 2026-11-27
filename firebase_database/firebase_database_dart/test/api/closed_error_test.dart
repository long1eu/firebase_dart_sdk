// The error of a closed database: one code and one message, whether the call came after close
// (the API layer refuses it) or was pending at close (Repo fails it).

import 'dart:async';

import 'package:firebase_database_dart/firebase_database_dart.dart';
import 'package:test/test.dart';

import 'support/fake_time.dart';
import 'support/harness.dart';

void main() {
  test('a call after close and a write pending at close fail alike', () {
    fakeTime((FakeTime time) {
      final Harness h = Harness(time);
      final List<FirebaseDatabaseException> errors =
          <FirebaseDatabaseException>[];
      void collect(Future<void> future) => unawaited(
        future.catchError(
          (Object e) => errors.add(e as FirebaseDatabaseException),
        ),
      );

      collect(h.ref('pending').set(1));
      h.settle();
      unawaited(h.db.close());
      h.settle();
      collect(h.ref('after').set(2));
      h.settle();

      expect(errors, hasLength(2));
      for (final FirebaseDatabaseException e in errors) {
        expect(e.code, 'database-closed');
        expect(e.message, 'The database was closed.');
        expect(e.serverStatus, isNull);
        expect(e.cause, isNull);
      }
    });
  });
}
