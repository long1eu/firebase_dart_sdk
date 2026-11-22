// Own tests for OperationSource (Android core/operation/OperationSource.java).
import 'package:firebase_database_dart/src/core/operation/operation_source.dart';
import 'package:firebase_database_dart/src/core/view/query_params.dart';
import 'package:test/test.dart';

void main() {
  test('user', () {
    expect(OperationSource.user.fromUser, isTrue);
    expect(OperationSource.user.fromServer, isFalse);
    expect(OperationSource.user.tagged, isFalse);
    expect(OperationSource.user.queryParams, isNull);
  });

  test('server', () {
    expect(OperationSource.server.fromUser, isFalse);
    expect(OperationSource.server.fromServer, isTrue);
    expect(OperationSource.server.tagged, isFalse);
  });

  test('tagged query', () {
    final QueryParams params = QueryParams.defaultParams;
    final OperationSource source = OperationSource.forServerTaggedQuery(params);
    expect(source.fromServer, isTrue);
    expect(source.fromUser, isFalse);
    expect(source.tagged, isTrue);
    expect(source.queryParams, same(params));
  });
}
