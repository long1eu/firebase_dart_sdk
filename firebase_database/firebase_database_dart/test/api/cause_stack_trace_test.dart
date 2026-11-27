// The public exception of a local error carries where its cause was thrown as its stackTrace,
// beside the cause; the stack trace is never part of toString.

import 'package:firebase_database_dart/firebase_database_dart.dart';
import 'package:firebase_database_dart/src/api/user_value.dart' show toApiError;
import 'package:firebase_database_dart/src/core/database_error.dart';
import 'package:test/test.dart';

void main() {
  test('toApiError keeps the cause and its stack trace', () {
    final StateError cause = StateError('x');
    final StackTrace trace = StackTrace.current;
    final Object converted = toApiError(
      DatabaseError.local(
        DatabaseErrorCode.userCodeException,
        'The transaction update function threw an exception.',
        cause: cause,
        causeStackTrace: trace,
      ),
    );

    expect(converted, isA<FirebaseDatabaseException>());
    final FirebaseDatabaseException e = converted as FirebaseDatabaseException;
    expect(e.cause, same(cause));
    expect(e.stackTrace, same(trace));
    expect(e.toString(), isNot(contains('cause_stack_trace_test.dart')));
  });

  test('an error without a cause has no stack trace', () {
    final Object converted = toApiError(
      DatabaseError.fromStatus('permission_denied'),
    );

    expect((converted as FirebaseDatabaseException).stackTrace, isNull);
  });
}
