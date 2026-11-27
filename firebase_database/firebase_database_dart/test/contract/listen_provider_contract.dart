// Contract of ListenProvider (lib/src/core/listen_provider.dart) as Repo implements it over
// ServerActions: RepoListenProvider must turn QuerySpec and Tag into the seam's JSON forms and map
// statuses to DatabaseError. listen_provider_contract_test.dart runs it against
// RepoListenProvider over FakeServerActions. Needs the data layer and Repo filled. No main here:
// other packages import this file.
import 'package:firebase_database_dart/src/core/connection/listen_hash_provider.dart';
import 'package:firebase_database_dart/src/core/database_error.dart';
import 'package:firebase_database_dart/src/core/listen_provider.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/tag.dart';
import 'package:firebase_database_dart/src/core/view/event.dart';
import 'package:firebase_database_dart/src/core/view/query_params.dart';
import 'package:firebase_database_dart/src/core/view/query_spec.dart';
import 'package:firebase_database_dart/src/testing/fake_server_actions.dart';
import 'package:test/test.dart';

final class _EmptyHash implements ListenHashProvider {
  @override
  String simpleHash() => '';

  @override
  bool shouldIncludeCompoundHash() => false;

  @override
  WireCompoundHash compoundHash() =>
      const WireCompoundHash(posts: <String>[], hashes: <String>['']);
}

/// The contract; [create] builds the provider under test over the given fake server.
void runListenProviderContract(
  ListenProvider Function(FakeServerActions server) create,
) {
  late FakeServerActions server;
  late ListenProvider provider;

  setUp(() {
    server = FakeServerActions();
    provider = create(server);
  });

  test('a server listen returns no events at start', () {
    expect(
      provider.startListening(
        QuerySpec.defaultAt(Path('/a')),
        null,
        _EmptyHash(),
        (_) => <Event>[],
      ),
      isEmpty,
    );
  });

  test('a default listen goes out untagged with the wire path', () {
    provider.startListening(
      QuerySpec.defaultAt(Path('/users/ada')),
      null,
      _EmptyHash(),
      (_) {
        return <Event>[];
      },
    );
    final ServerCall call = server.callsOf('listen').single;
    expect(call.spec!.path, '/users/ada');
    expect(call.spec!.queryIdentifier, 'default');
    expect(call.tag, isNull);
  });

  test('a tagged listen carries the tag number and the query object', () {
    final QuerySpec query = QuerySpec(
      Path('/users'),
      QueryParams.defaultParams.limitToLast(3),
    );
    provider.startListening(
      query,
      const Tag(4),
      _EmptyHash(),
      (_) => <Event>[],
    );
    final ServerCall call = server.callsOf('listen').single;
    expect(call.tag, 4);
    expect(call.spec!.queryObject, <String, Object?>{'l': 3, 'vf': 'r'});
  });

  test('ok completes with null; a failure completes with the mapped error', () {
    final List<DatabaseError?> results = <DatabaseError?>[];
    final QuerySpec a = QuerySpec.defaultAt(Path('/a'));
    final QuerySpec b = QuerySpec.defaultAt(Path('/b'));
    List<Event> record(DatabaseError? error) {
      results.add(error);
      return <Event>[];
    }

    provider.startListening(a, null, _EmptyHash(), record);
    provider.startListening(b, null, _EmptyHash(), record);
    server.respondToListen(a.toListenSpec());
    server.respondToListen(
      b.toListenSpec(),
      status: 'permission_denied',
      data: 'no',
    );
    expect(results.first, isNull);
    expect(results.last!.code, DatabaseErrorCode.permissionDenied);
  });

  test('stopListening sends unlisten with the same tag', () {
    final QuerySpec query = QuerySpec(
      Path('/users'),
      QueryParams.defaultParams.limitToLast(3),
    );
    provider.startListening(
      query,
      const Tag(2),
      _EmptyHash(),
      (_) => <Event>[],
    );
    provider.stopListening(query, const Tag(2));
    expect(server.callsOf('unlisten').single.tag, 2);
    expect(server.activeListens, isEmpty);
  });
}
