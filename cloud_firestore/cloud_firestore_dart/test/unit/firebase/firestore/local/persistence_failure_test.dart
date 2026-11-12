// Copyright 2018 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:test/test.dart';

import 'persistence_test_helpers.dart';

/// A failing transaction must release everything and leave the persistence usable.
void main() {
  const Duration hangTimeout = Duration(seconds: 5);

  Future<void> expectUsableAfterFailure(Persistence persistence) async {
    await expectLater(
        persistence.runTransaction('failing', () async {
          throw StateError('boom');
        }),
        throwsA(isA<StateError>()));

    // Would hang (semaphore never released) or fail an assert (sequence number never reset) before the fix.
    final int result = await persistence
        .runTransactionAndReturn<int>('second', () async => 42)
        .timeout(hangTimeout);
    expect(result, 42);

    // And a second failure followed by a success still works.
    await expectLater(
        persistence.runTransaction('failing again', () async {
          throw StateError('boom');
        }),
        throwsA(isA<StateError>()));
    expect(
        await persistence
            .runTransactionAndReturn<int>('third', () async => 7)
            .timeout(hangTimeout),
        7);
  }

  test('memory eager persistence survives a throwing transaction', () async {
    final Persistence persistence = await createEagerGCMemoryPersistence();
    await expectUsableAfterFailure(persistence);
    await persistence.shutdown();
  });

  test('memory lru persistence survives a throwing transaction', () async {
    final Persistence persistence = await createLRUMemoryPersistence();
    await expectUsableAfterFailure(persistence);
    await persistence.shutdown();
  });

  test('sqlite persistence survives a throwing transaction', () async {
    final Persistence persistence = await createSQLitePersistence();
    await expectUsableAfterFailure(persistence);
    await persistence.shutdown();
  });

  test('sqlite persistence releases the semaphore when ROLLBACK throws',
      () async {
    final persistence = await createSQLitePersistence();
    await expectLater(
        persistence.runTransaction('close and fail', () async {
          // Closing the database makes the ROLLBACK fail as well.
          persistence.database.close();
          throw StateError('boom');
        }),
        throwsA(isA<StateError>()));

    // The database is closed so this fails, but it must fail, not hang.
    await expectLater(
        persistence
            .runTransaction('after closed', () async {})
            .timeout(hangTimeout),
        throwsA(isNot(isA<TimeoutException>())));
  });
}
