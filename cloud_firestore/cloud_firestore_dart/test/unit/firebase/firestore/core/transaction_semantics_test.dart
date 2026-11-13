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

import 'dart:typed_data';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/transaction.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/delete_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/patch_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/set_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/verify_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/no_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/datastore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/user_data_converter.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';

/// Unit-level port of the semantics covered by upstream's (integration)
/// TransactionTest: preconditions derived from reads, "read requires write",
/// "no reads after writes" and the single-use rule.
class _FakeTransactionClient implements TransactionClient {
  _FakeTransactionClient(this.documents);

  List<MaybeDocument> documents;
  List<Mutation> committed = <Mutation>[];
  int commits = 0;

  @override
  Future<List<MaybeDocument>> lookup(
    List<DocumentKey> keys, {
    Uint8List? transaction,
  }) async => documents;

  @override
  Future<List<MutationResult>> commit(List<Mutation> mutations) async {
    commits++;
    committed = mutations;
    return <MutationResult>[];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final UserDataConverter converter = UserDataConverter(
    DatabaseId.forProject('project'),
  );
  final DocumentKey docKey = key('foo/bar');

  Matcher firestoreError(FirestoreErrorCode code, [String? text]) =>
      isA<FirestoreError>()
          .having((FirestoreError e) => e.code, 'code', code)
          .having(
            (FirestoreError e) => e.message,
            'message',
            text == null ? isNotNull : contains(text),
          );

  test('a blind set has no precondition', () async {
    final _FakeTransactionClient client = _FakeTransactionClient(
      <MaybeDocument>[],
    );
    final Transaction tx = Transaction(client)
      ..set(docKey, converter.parseSetData(<String, Object?>{'a': 1}));
    await tx.commit();

    expect(client.committed.single, isA<SetMutation>());
    expect(client.committed.single.precondition, Precondition.none);
  });

  test('a blind update requires the document to exist', () async {
    final _FakeTransactionClient client = _FakeTransactionClient(
      <MaybeDocument>[],
    );
    final Transaction tx = Transaction(client)
      ..update(docKey, converter.parseUpdateData(<String, Object?>{'a': 1}));
    await tx.commit();

    expect(client.committed.single, isA<PatchMutation>());
    expect(client.committed.single.precondition, Precondition(exists: true));
  });

  test('a blind delete has no precondition', () async {
    final _FakeTransactionClient client = _FakeTransactionClient(
      <MaybeDocument>[],
    );
    final Transaction tx = Transaction(client)..delete(docKey);
    await tx.commit();

    expect(client.committed.single, isA<DeleteMutation>());
    expect(client.committed.single.precondition, Precondition.none);
  });

  test('set after reading an existing document uses its version', () async {
    final _FakeTransactionClient client = _FakeTransactionClient(
      <MaybeDocument>[
        doc('foo/bar', 7, map(<String>['a', 'b'])),
      ],
    );
    final Transaction tx = Transaction(client);
    await tx.lookup(<DocumentKey>[docKey]);
    tx.set(docKey, converter.parseSetData(<String, Object?>{'a': 1}));
    await tx.commit();

    expect(
      client.committed.single.precondition,
      Precondition(updateTime: version(7)),
    );
  });

  test(
    'set after reading a missing document requires it to not exist',
    () async {
      final _FakeTransactionClient client = _FakeTransactionClient(
        <MaybeDocument>[deletedDoc('foo/bar', 0)],
      );
      final Transaction tx = Transaction(client);
      await tx.lookup(<DocumentKey>[docKey]);
      tx.set(docKey, converter.parseSetData(<String, Object?>{'a': 1}));
      await tx.commit();

      expect(client.committed.single.precondition, Precondition(exists: false));
    },
  );

  test('update after reading an existing document uses its version', () async {
    final _FakeTransactionClient client = _FakeTransactionClient(
      <MaybeDocument>[
        doc('foo/bar', 7, map(<String>['a', 'b'])),
      ],
    );
    final Transaction tx = Transaction(client);
    await tx.lookup(<DocumentKey>[docKey]);
    tx.update(docKey, converter.parseUpdateData(<String, Object?>{'a': 1}));
    await tx.commit();

    expect(
      client.committed.single.precondition,
      Precondition(updateTime: version(7)),
    );
  });

  test(
    'updating a document that was read as missing fails the commit',
    () async {
      final _FakeTransactionClient client = _FakeTransactionClient(
        <MaybeDocument>[deletedDoc('foo/bar', 0)],
      );
      final Transaction tx = Transaction(client);
      await tx.lookup(<DocumentKey>[docKey]);
      tx.update(docKey, converter.parseUpdateData(<String, Object?>{'a': 1}));

      await expectLater(
        tx.commit(),
        throwsA(
          firestoreError(FirestoreErrorCode.invalidArgument, 'doesn\'t exist'),
        ),
      );
      expect(client.commits, 0);
    },
  );

  test(
    'only the first write to a document uses the read precondition',
    () async {
      final _FakeTransactionClient client = _FakeTransactionClient(
        <MaybeDocument>[
          doc('foo/bar', 7, map(<String>['a', 'b'])),
        ],
      );
      final Transaction tx = Transaction(client);
      await tx.lookup(<DocumentKey>[docKey]);
      tx
        ..set(docKey, converter.parseSetData(<String, Object?>{'a': 1}))
        ..set(docKey, converter.parseSetData(<String, Object?>{'a': 2}))
        ..delete(docKey);
      await tx.commit();

      expect(client.committed.length, 3);
      expect(
        client.committed[0].precondition,
        Precondition(updateTime: version(7)),
      );
      expect(client.committed[1].precondition, Precondition.none);
      expect(client.committed[2].precondition, Precondition.none);
    },
  );

  test(
    'documents that were read but not written are verified at commit',
    () async {
      final _FakeTransactionClient client = _FakeTransactionClient(
        <MaybeDocument>[
          doc('foo/bar', 7, map(<String>['a', 'b'])),
        ],
      );
      final Transaction tx = Transaction(client);
      await tx.lookup(<DocumentKey>[docKey]);
      await tx.commit();

      expect(client.commits, 1);
      expect(tx.committed, isTrue);
      expect(client.committed.single, isA<VerifyMutation>());
      expect(client.committed.single.key, docKey);
      expect(
        client.committed.single.precondition,
        Precondition(updateTime: version(7)),
      );
    },
  );

  test(
    'a document read that does not exist is verified with exists: false',
    () async {
      final _FakeTransactionClient client = _FakeTransactionClient(
        <MaybeDocument>[
          NoDocument(docKey, version(0), hasCommittedMutations: false),
        ],
      );
      final Transaction tx = Transaction(client);
      await tx.lookup(<DocumentKey>[docKey]);
      await tx.commit();

      expect(client.committed.single, isA<VerifyMutation>());
      expect(client.committed.single.precondition, Precondition(exists: false));
    },
  );

  test(
    'reading one document and writing another verifies the one read',
    () async {
      final _FakeTransactionClient client = _FakeTransactionClient(
        <MaybeDocument>[
          doc('foo/bar', 7, map(<String>['a', 'b'])),
        ],
      );
      final Transaction tx = Transaction(client);
      await tx.lookup(<DocumentKey>[docKey]);
      tx.set(
        key('foo/other'),
        converter.parseSetData(<String, Object?>{'a': 1}),
      );
      await tx.commit();

      expect(client.committed.length, 2);
      expect(client.committed[0], isA<SetMutation>());
      expect(client.committed[0].key, key('foo/other'));
      expect(client.committed[1], isA<VerifyMutation>());
      expect(client.committed[1].key, docKey);
      expect(
        client.committed[1].precondition,
        Precondition(updateTime: version(7)),
      );
    },
  );

  test('a document that was read and written is not also verified', () async {
    final _FakeTransactionClient client = _FakeTransactionClient(
      <MaybeDocument>[
        doc('foo/bar', 7, map(<String>['a', 'b'])),
      ],
    );
    final Transaction tx = Transaction(client);
    await tx.lookup(<DocumentKey>[docKey]);
    tx.delete(docKey);
    await tx.commit();

    expect(client.committed.single, isA<DeleteMutation>());
  });

  test('lookups after writes are rejected', () async {
    final _FakeTransactionClient client = _FakeTransactionClient(
      <MaybeDocument>[],
    );
    final Transaction tx = Transaction(client)
      ..set(docKey, converter.parseSetData(<String, Object?>{'a': 1}));

    await expectLater(
      tx.lookup(<DocumentKey>[docKey]),
      throwsA(
        firestoreError(
          FirestoreErrorCode.invalidArgument,
          'require all reads to be executed before all writes',
        ),
      ),
    );
    // As in the JS SDK, the transaction cannot commit afterwards.
    await expectLater(
      tx.commit(),
      throwsA(
        firestoreError(
          FirestoreErrorCode.invalidArgument,
          'require all reads to be executed before all writes',
        ),
      ),
    );
    expect(client.commits, 0);
  });

  test(
    'a document read twice at different versions aborts the transaction',
    () async {
      final _FakeTransactionClient client = _FakeTransactionClient(
        <MaybeDocument>[
          doc('foo/bar', 7, map(<String>['a', 'b'])),
        ],
      );
      final Transaction tx = Transaction(client);
      await tx.lookup(<DocumentKey>[docKey]);

      client.documents = <MaybeDocument>[
        doc('foo/bar', 8, map(<String>['a', 'b'])),
      ];
      await expectLater(
        tx.lookup(<DocumentKey>[docKey]),
        throwsA(firestoreError(FirestoreErrorCode.aborted)),
      );
    },
  );

  test('reading the same document twice at the same version is fine', () async {
    final _FakeTransactionClient client = _FakeTransactionClient(
      <MaybeDocument>[
        doc('foo/bar', 7, map(<String>['a', 'b'])),
      ],
    );
    final Transaction tx = Transaction(client);
    await tx.lookup(<DocumentKey>[docKey]);
    await tx.lookup(<DocumentKey>[docKey]);
    tx.delete(docKey);
    await tx.commit();

    expect(
      client.committed.single.precondition,
      Precondition(updateTime: version(7)),
    );
  });

  test('a transaction cannot be used after commit', () async {
    final _FakeTransactionClient client = _FakeTransactionClient(
      <MaybeDocument>[],
    );
    final Transaction tx = Transaction(client)..delete(docKey);
    await tx.commit();
    expect(tx.committed, isTrue);

    expect(tx.commit, throwsA(anything));
    expect(() => tx.lookup(<DocumentKey>[docKey]), throwsA(anything));
    expect(() => tx.delete(docKey), throwsStateError);
    expect(client.commits, 1);
  });

  test('mutations are committed in the order they were written', () async {
    final _FakeTransactionClient client = _FakeTransactionClient(
      <MaybeDocument>[],
    );
    final Transaction tx = Transaction(client)
      ..set(key('foo/a'), converter.parseSetData(<String, Object?>{'a': 1}))
      ..delete(key('foo/b'))
      ..update(
        key('foo/c'),
        converter.parseUpdateData(<String, Object?>{'a': 1}),
      );
    await tx.commit();

    expect(
      client.committed.map((Mutation m) => m.key.path.canonicalString),
      <String>['foo/a', 'foo/b', 'foo/c'],
    );
  });

  // Read-only transactions: see read_only_transaction_test.dart.
}
