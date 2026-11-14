// Schema migration 19: the canonical ids of the stored targets are computed
// again. They used to contain the toString() of the values of a query and
// are now the ids of the JS SDK (see canonifyValue), so a cache that was
// written before still finds its targets.

import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_purpose.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';
import 'mock/database_mock.dart';

final LocalSerializer _serializer = LocalSerializer(
  RemoteSerializer(DatabaseId.forDatabase('projectId', 'other')),
);

void main() {
  late String name;
  late DatabaseMock db;
  late SQLiteSchema schema;

  setUp(() async {
    name = 'firebase/firestore/local/sqlite_schema_canonical_ids_test.db';
    DatabaseMock.deleteDatabaseFiles(name);
    db = await DatabaseMock.create(name)
      ..renamePath = false;
    schema = SQLiteSchema(db);
  });

  tearDown(() {
    db.close();
    DatabaseMock.deleteDatabaseFiles(name);
  });

  Future<void> insertTarget(int targetId, String canonicalId, Query query) {
    final QueryData queryData = QueryData(
      query.toTarget(),
      targetId,
      targetId,
      QueryPurpose.listen,
    );
    return db.execute(
      'INSERT INTO targets (target_id, canonical_id, target_proto) '
      'VALUES (?, ?, ?)',
      <Object>[
        targetId,
        canonicalId,
        _serializer.encodeQueryData(queryData).writeToBuffer(),
      ],
    );
  }

  Future<Map<int, String>> canonicalIds() async => <int, String>{
    for (final Map<String, dynamic> row in await db.query(
      'SELECT target_id, canonical_id FROM targets ORDER BY target_id',
    ))
      row['target_id'] as int: row['canonical_id'] as String,
  };

  test('the canonical ids of stored targets are computed again', () async {
    await schema.runMigrations(0, 18);
    // The ids as version 18 wrote them.
    await insertTarget(
      2,
      'rooms|f:at <= Timestamp {\n  seconds=60,\n  nanoseconds=3000,\n}'
      '|ob:atasc__name__asc',
      query('rooms').filter(filter('at', '<=', const Timestamp(60, 3000))),
    );
    await insertTarget(
      4,
      'rooms|f:owner == DocumentKey {\n  path=users/eros,\n}|ob:__name__asc',
      query('rooms').filter(filter('owner', '==', ref('users/eros'))),
    );
    await insertTarget(6, 'rooms|f:|ob:__name__asc', query('rooms'));
    // A document target.
    await insertTarget(8, 'rooms/eros|f:|ob:__name__asc', query('rooms/eros'));
    // A row that can not be decoded keeps its id.
    await db.execute(
      'INSERT INTO targets (target_id, canonical_id, target_proto) '
      'VALUES (?, ?, ?)',
      <Object>[
        10,
        'broken',
        blob(<int>[0xff, 0xff, 0xff]).bytes,
      ],
    );

    await schema.runMigrations(18, 19);

    final Map<int, String> expected = <int, String>{
      2: 'rooms|f:at<=time(60,3000)|ob:atasc,__name__asc',
      4: 'rooms|f:owner==users/eros|ob:__name__asc',
      6: 'rooms|f:|ob:__name__asc',
      8: 'rooms/eros|f:|ob:__name__asc',
      10: 'broken',
    };
    expect(await canonicalIds(), expected);

    // The migration can run again.
    await schema.runMigrations(18, 19);
    expect(await canonicalIds(), expected);
  });
}
