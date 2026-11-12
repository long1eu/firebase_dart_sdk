// File created by
// Lung Razvan <long1eu>
// on 05/10/2018

import '../local/persistence_test_helpers.dart';
import 'spec_runner.dart';
import 'spec_skip_list.dart';

/// Runs the upstream JSON spec tests on the SQLite persistence (the `useEagerGCForMemory` config is ignored, as
/// upstream).
void main() {
  registerSpecTests(
    variant: 'sqlite',
    getPersistence: (_, String name) => createSQLitePersistence(
      'firebase/firestore/spec/sqlite_spec_test_${Uri.encodeQueryComponent(name)}',
    ),
    excludedTags: sqliteExcludedTags,
  );
}
