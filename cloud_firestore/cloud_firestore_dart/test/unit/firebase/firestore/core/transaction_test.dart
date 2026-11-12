import 'package:cloud_firestore_dart/src/firebase/firestore/core/transaction.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/delete_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/datastore.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';

class _FakeTransactionClient implements TransactionClient {
  _FakeTransactionClient(this.documents);

  final List<MaybeDocument> documents;
  List<Mutation> committed = <Mutation>[];

  @override
  Future<List<MaybeDocument>> lookup(List<DocumentKey> keys) async => documents;

  @override
  Future<List<MutationResult>> commit(List<Mutation> mutations) async {
    committed = mutations;
    return <MutationResult>[];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('writing a document that was read as missing requires it to not exist',
      () async {
    final DocumentKey docKey = key('foo/bar');
    final _FakeTransactionClient client =
        _FakeTransactionClient(<MaybeDocument>[deletedDoc('foo/bar', 0)]);
    final Transaction transaction = Transaction(client);

    await transaction.lookup(<DocumentKey>[docKey]);
    transaction.delete(docKey);
    await transaction.commit();

    final Mutation mutation = client.committed.single;
    expect(mutation, isA<DeleteMutation>());
    expect(mutation.precondition, Precondition(exists: false));
  });

  test('writing a document that was read as existing requires its version',
      () async {
    final DocumentKey docKey = key('foo/bar');
    final _FakeTransactionClient client =
        _FakeTransactionClient(<MaybeDocument>[
      doc('foo/bar', 5, map(<String>['a', 'b']))
    ]);
    final Transaction transaction = Transaction(client);

    await transaction.lookup(<DocumentKey>[docKey]);
    transaction.delete(docKey);
    await transaction.commit();

    expect(client.committed.single.precondition,
        Precondition(updateTime: version(5)));
  });

  test('reading the same missing document twice does not abort', () async {
    final DocumentKey docKey = key('foo/bar');
    final _FakeTransactionClient client =
        _FakeTransactionClient(<MaybeDocument>[deletedDoc('foo/bar', 3)]);
    final Transaction transaction = Transaction(client);

    await transaction.lookup(<DocumentKey>[docKey]);
    await transaction.lookup(<DocumentKey>[docKey]);
    transaction.delete(docKey);
    await transaction.commit();

    expect(client.committed.single.precondition, Precondition(exists: false));
  });
}
