// The database names of the integration test instances (test/util/integration_test_util.dart): `dart test -j` runs
// several test files in isolates of one process, each with its own counter. Two files with the same database path
// must still get different files, otherwise the second client takes the primary lease of the first one's cache.

@TestOn('vm')
library;

import 'dart:isolate';

import 'package:test/test.dart';

import '../../util/integration_test_util.dart';

void main() {
  test('names differ between isolates that use the same path', () async {
    final List<String> here = <String>[
      IntegrationTestUtil.newDatabaseName('test'),
      IntegrationTestUtil.newDatabaseName('test'),
    ];
    // Another isolate starts with its own counter at the same value.
    final List<String> there = await Isolate.run(
      () => <String>[
        IntegrationTestUtil.newDatabaseName('test'),
        IntegrationTestUtil.newDatabaseName('test'),
      ],
    );

    expect(here.toSet(), hasLength(2));
    expect(there.toSet(), hasLength(2));
    expect(here.toSet().intersection(there.toSet()), isEmpty);
    for (final String name in <String>[...here, ...there]) {
      expect(name, startsWith('test_'));
      expect(name, endsWith('.db'));
    }
  });
}
