// The checks the browser opener runs before it uses a cache: a sqlite3
// package whose IndexedDB file system can lose acknowledged writes (3.4.0 to
// 3.5.2), and a sqlite3.wasm that is missing or of another version.
//
// The expected verdict comes from the sqlite3 version in pubspec.lock, so the
// same file proves the check on every version: run it after a temporary
// `dependency_overrides: sqlite3: <version>` with that version's sqlite3.wasm
// in this folder (see README.md). Optional: other_sqlite3.wasm, the build of
// another sqlite3 release, for the version mismatch test.
//
//   dart test -p chrome -c dart2js test/browser/setup_checks_test.dart

@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart_sqlite/cloud_firestore_dart_sqlite.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

int _names = 0;
String newName(String prefix) =>
    '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_names++}';

Future<String?> fetchText(String file) async {
  try {
    final web.Response response = await web.window
        .fetch(Uri.base.resolve(file).toString().toJS)
        .toDart;
    return response.ok ? (await response.text().toDart).toDart : null;
  } catch (_) {
    return null;
  }
}

/// The sqlite3 version in pubspec.lock, e.g. `[3, 5, 2]`.
Future<List<int>?> lockedSqlite3() async {
  final String? lock = await fetchText('../../pubspec.lock');
  if (lock == null) {
    return null;
  }
  final RegExpMatch? match = RegExp(
    r'\n  sqlite3:\n(?:    .*\n)*?    version: "(\d+)\.(\d+)\.(\d+)"',
  ).firstMatch(lock);
  if (match == null) {
    return null;
  }
  return <int>[for (int i = 1; i <= 3; i++) int.parse(match.group(i)!)];
}

bool unsafe(List<int> v) =>
    v[0] == 3 && (v[1] == 4 || (v[1] == 5 && v[2] <= 2));

/// A WebAssembly module that compiles but that no sqlite3 package can load:
/// it imports a function `dart.not_a_sqlite3_import`, and exports what the
/// builds of one major line export ([memory]: 3.x, otherwise `_initialize`:
/// 2.x).
String fakeWasmUrl({required bool memory}) {
  List<int> name(String s) => <int>[s.length, ...s.codeUnits];
  List<int> section(int id, List<int> body) => <int>[id, body.length, ...body];
  final List<int> bytes = <int>[
    0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00, // magic, version 1
    ...section(1, <int>[1, 0x60, 0, 0]), // one type: () -> ()
    ...section(2, <int>[
      1,
      ...name('dart'),
      ...name('not_a_sqlite3_import'),
      0,
      0,
    ]),
    if (memory) ...section(5, <int>[1, 0, 1]), // one memory of one page
    ...section(7, <int>[
      1,
      if (memory) ...<int>[...name('memory'), 2, 0] else ...<int>[
        ...name('_initialize'),
        0,
        0,
      ],
    ]),
  ];
  final web.Blob blob = web.Blob(
    <JSAny>[Uint8List.fromList(bytes).toJS].toJS,
    web.BlobPropertyBag(type: 'application/wasm'),
  );
  return web.URL.createObjectURL(blob);
}

Future<Database> open(OpenDatabase opener) =>
    opener(newName('check'), version: 1);

Matcher setupProblem(SqliteWebSetupProblem problem, [Pattern? message]) =>
    isA<SqliteWebSetupException>()
        .having((SqliteWebSetupException e) => e.problem, 'problem', problem)
        .having(
          (SqliteWebSetupException e) => e.message,
          'message',
          message == null ? anything : contains(message),
        );

void main() {
  String? skip;
  List<int>? version;

  setUpAll(() async {
    skip = await fetchText('sqlite3.wasm') == null
        ? 'test/browser/sqlite3.wasm is missing'
        : null;
    version = await lockedSqlite3();
    skip ??= version == null ? 'sqlite3 is not in pubspec.lock' : null;
  });

  test('IndexedDB opens with a safe sqlite3 and is refused with 3.4.0 to '
      '3.5.2', () async {
    if (skip != null) {
      markTestSkipped(skip!);
      return;
    }
    print('sqlite3 ${version!.join('.')} from pubspec.lock');
    if (unsafe(version!)) {
      await expectLater(
        open(sqliteOpener()),
        throwsA(
          setupProblem(
            SqliteWebSetupProblem.unsafeSqlite3,
            'acceptIndexedDbWriteLoss',
          ),
        ),
      );
      // The lock was released: the opt-in opens the same name at once.
      final Database db = await open(
        sqliteOpener(acceptIndexedDbWriteLoss: true),
      );
      db.close();
    } else {
      final Database db = await open(sqliteOpener());
      await db.execute('CREATE TABLE t (x)');
      await db.execute('INSERT INTO t VALUES (1)');
      expect(await db.query('SELECT x FROM t'), <Object>[
        <String, Object?>{'x': 1},
      ]);
      db.close();
    }
  });

  test('the opt-in opens with every version', () async {
    if (skip != null) {
      markTestSkipped(skip!);
      return;
    }
    final Database db = await open(
      sqliteOpener(acceptIndexedDbWriteLoss: true),
    );
    await db.execute('CREATE TABLE t (x)');
    db.close();
  });

  test(
    'openWithMemoryFallback rethrows the refusal instead of falling back',
    () async {
      if (skip != null) {
        markTestSkipped(skip!);
        return;
      }
      final FirebaseApp app = FirebaseApp.withOptions(
        const FirebaseOptions(
          apiKey: 'demo-key',
          appId: '1:1234567890:dart:browser',
          projectId: 'demo-test',
        ),
        name: newName('setup-check'),
      );
      final Settings settings = Settings(
        cacheSettings: PersistentCacheSettings(),
      ).withEmulator('127.0.0.1', 8090);
      try {
        if (unsafe(version!)) {
          await expectLater(
            openWithMemoryFallback(
              app: app,
              openDatabase: sqliteOpener(),
              settings: settings,
            ),
            throwsA(setupProblem(SqliteWebSetupProblem.unsafeSqlite3)),
          );
          // Every operation of the instance reports it.
          final FirebaseFirestore failed = FirebaseFirestore.instanceFor(
            app: app,
          );
          await expectLater(
            failed.collection('c').doc('d').get(),
            throwsA(isA<SqliteWebSetupException>()),
          );
          await failed.terminate();
        } else {
          final FirebaseFirestore firestore = await openWithMemoryFallback(
            app: app,
            openDatabase: sqliteOpener(),
            settings: settings,
          );
          expect(firestore.persistentCacheIndexManager, isNotNull);
          await firestore.terminate();
          await firestore.clearPersistence();
        }
      } finally {
        await app.delete();
      }
    },
  );

  test('a missing sqlite3.wasm is named', () async {
    await expectLater(
      open(sqliteOpener(sqlite3Wasm: Uri.parse('no-such-sqlite3.wasm'))),
      throwsA(setupProblem(SqliteWebSetupProblem.wasmMissing, 'HTTP 404')),
    );
  });

  test('a file that is not WebAssembly is named', () async {
    // The page itself: what a server that answers every path with the page
    // sends for a missing sqlite3.wasm.
    await expectLater(
      open(sqliteOpener(sqlite3Wasm: Uri.parse('../../pubspec.yaml'))),
      throwsA(
        setupProblem(SqliteWebSetupProblem.wasmMissing, 'not WebAssembly'),
      ),
    );
  });

  test('a sqlite3.wasm that the package cannot load is a version mismatch, '
      'with its major line', () async {
    await expectLater(
      open(sqliteOpener(sqlite3Wasm: Uri.parse(fakeWasmUrl(memory: false)))),
      throwsA(
        setupProblem(SqliteWebSetupProblem.wasmVersionMismatch, 'sqlite3 2.x'),
      ),
    );
    await expectLater(
      open(sqliteOpener(sqlite3Wasm: Uri.parse(fakeWasmUrl(memory: true)))),
      throwsA(
        setupProblem(SqliteWebSetupProblem.wasmVersionMismatch, 'sqlite3 3.x'),
      ),
    );
  });

  test('the sqlite3.wasm of another release is a version mismatch', () async {
    if (await fetchText('other_sqlite3.wasm') == null) {
      markTestSkipped('test/browser/other_sqlite3.wasm is missing');
      return;
    }
    await expectLater(
      open(sqliteOpener(sqlite3Wasm: Uri.parse('other_sqlite3.wasm'))),
      throwsA(setupProblem(SqliteWebSetupProblem.wasmVersionMismatch)),
    );
  });
}
