// Every public member of a public library names only types that apps can
// name: types of dart: libraries or other packages, or types that a public
// library of this package exports.
//
// The public libraries are firebase_database_dart.dart, storage_engine.dart and
// testing.dart. Chosen rule: a type exported by any of the three counts as
// reachable from all of them (an app adds the import it needs). A stricter
// per-library rule would add 7 findings today: storage_engine.dart and
// testing.dart name DatabaseLogLevel, DatabasePersistence and FirebaseDatabase,
// which only the main library exports.
//
// Members annotated @internal or @visibleForTesting are skipped; @protected
// members are checked. support/public_api_type_reachability.dart has the full
// rules and the limits of dart:mirrors (record fields and extension types are
// not seen). Built with dart:mirrors, so it runs under `dart test` (JIT) only.
@TestOn('vm')
library;

import 'dart:mirrors';

// Loaded so that the libraries can be found by the mirror system.
// ignore: unused_import
import 'package:firebase_database_dart/firebase_database_dart.dart';
// ignore: unused_import
import 'package:firebase_database_dart/storage_engine.dart';
// ignore: unused_import
import 'package:firebase_database_dart/testing.dart';
import 'package:test/test.dart';

import 'support/public_api_type_reachability.dart';
// ignore: unused_import
import 'support/reachability_fixture/fixture.dart';

/// The findings accepted for now, each exactly as the checker prints it, with
/// a one-line reason above it (from rtdb/from_helper/reports/
/// public_members_internal_types.md where it applies, else "not yet
/// decided"). Empty: every member that the report listed is now @internal or
/// names an exported type.
const List<String> _allowed = <String>[];

const String _ownPrefix = 'package:firebase_database_dart/';

final Map<String, Uri> _libraries = <String, Uri>{
  for (final String library in <String>[
    'firebase_database_dart.dart',
    'storage_engine.dart',
    'testing.dart',
  ])
    library: Uri.parse('$_ownPrefix$library'),
};

void main() {
  test('public members name only exported types', () {
    final List<String> found = findUnexportedTypes(
      libraries: _libraries,
      ownPrefix: _ownPrefix,
    );
    final List<String> added = found
        .where((String f) => !_allowed.contains(f))
        .toList();
    final List<String> gone = _allowed
        .where((String f) => !found.contains(f))
        .toList();
    if (added.isEmpty && gone.isEmpty) {
      return;
    }
    fail(
      <String>[
        if (added.isNotEmpty) ...<String>[
          'Public members that name a type no public library exports. For '
              'each: export the type from a public library, mark the member '
              '@internal, or add the line to _allowed in '
              'test/api/public_api_type_reachability_test.dart with a reason:',
          ...added.map((String f) => '  $f'),
        ],
        if (gone.isNotEmpty) ...<String>[
          'Entries of _allowed that are no longer found; remove them:',
          ...gone.map((String f) => '  $f'),
        ],
      ].join('\n'),
    );
  });

  test('the checker reports only the public member of the fixture that names '
      'an unexported type', () {
    final LibraryMirror fixture = currentMirrorSystem().libraries.values
        .singleWhere(
          (LibraryMirror l) => l.uri.path.endsWith(
            'test/api/support/reachability_fixture/fixture.dart',
          ),
        );
    expect(
      findUnexportedTypes(
        libraries: <String, Uri>{'fixture.dart': fixture.uri},
        ownPrefix: fixture.uri.resolve('.').toString(),
      ),
      <String>[
        'fixture.dart: Exposed.leaks names Hidden '
            '(declared in src/fixture_types.dart)',
      ],
    );
  });
}
