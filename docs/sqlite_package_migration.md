# Hand-over: from "copy the file" to `cloud_firestore_dart_sqlite`

For the coordinator, not for users. Branch `wave/sqlite` adds the package
`cloud_firestore/cloud_firestore_dart_sqlite` (0.1.0, not published). This file lists every
place that tells the reader to copy `example/sqlite_database.dart`, `sqlite_database_web.dart`
or `sqlite_opfs_worker.dart`, with the old passage and the text that replaces it. It was written
against `origin/main` at `eb33218a`; the API names (`Firestore.instanceFor`, `FirestoreSettings`,
`PersistentCacheSettings`, ...) are the ones of that commit, so adapt them to `wave/dart-api`
when it lands. Nothing here was applied.

## Before you apply it

1. **The snippet test.** `cloud_firestore_dart/test/unit/api/readme_snippets_test.dart` copies
   every ```` ```dart ```` block of the guides into `test/readme/readme_snippets.dart` and
   analyzes it there. It rewrites `import 'sqlite_database.dart';` to the example file. Once a
   guide imports `package:cloud_firestore_dart_sqlite/cloud_firestore_dart_sqlite.dart`,
   `cloud_firestore_dart` needs the new package as a dev dependency:

   ```yaml
   # cloud_firestore/cloud_firestore_dart/pubspec.yaml, dev_dependencies (sorted)
     # Only for test/readme: the guides import the SQLite opener from it. Local development
     # resolves it from ../cloud_firestore_dart_sqlite through pubspec_overrides.yaml.
     cloud_firestore_dart_sqlite: ^0.1.0
   ```

   ```yaml
   # cloud_firestore/cloud_firestore_dart/pubspec_overrides.yaml, dependency_overrides
     cloud_firestore_dart_sqlite:
       path: ../cloud_firestore_dart_sqlite
   ```

   Pub allows the cycle (the new package depends on `cloud_firestore_dart`, which would
   dev-depend on it). Until the package is on pub.dev, `cloud_firestore_dart` resolves only with
   the path override (not tried here): publish `cloud_firestore_dart_sqlite` first.

   The generated file must not import both `example/sqlite_database.dart` and the package: both
   define `sqliteOpener` (positional `Directory` in the example, named `directory:` in the
   package), which is an ambiguous import. Convert every guide in one change, then regenerate
   with `UPDATE_GOLDEN=1 dart test test/unit/api/readme_snippets_test.dart`.

2. **`sqlite3` 3.x in `cloud_firestore_dart`'s own tests.** Nothing to do now: the package's
   tests and examples keep their copies and `sqlite3: ^2.7.3`. A dev dependency on the new
   package allows `sqlite3` 3.x, but `cloud_firestore_dart` pins `^2.7.3` itself, so pub keeps
   2.9.4 there (and the pinned `sqlite3.wasm` stays right).

3. **Optional:** add the new README to the snippet test (`_fixedReadmes` in
   `readme_snippets_test.dart`: `'../cloud_firestore_dart_sqlite/README.md': 'sqliteReadme'`).
   Its Linux override block imports `package:sqlite3/open.dart`, which only exists in 2.x and
   would not analyze against 3.x: fence it as ```` ```dart before ```` (the fence the test skips)
   if you add the README.

The common replacement, used below:

- **Dependency:** `dart pub add cloud_firestore_dart_sqlite` (Flutter: `flutter pub add
  cloud_firestore_dart_sqlite`). No `sqlite3`, no `sqlite3_flutter_libs`.
- **Import:** `import 'package:cloud_firestore_dart_sqlite/cloud_firestore_dart_sqlite.dart';`
- **VM call:** `sqliteOpener(directory: '<path>')` instead of `sqliteOpener(Directory('<path>'))`.
- **Web call:** `sqliteOpener()` (IndexedDB) or `sqliteOpener(opfsWorker:
  Uri.parse('sqlite_opfs_worker.js'))` instead of `sqliteWebOpener(sqlite3Wasm:
  Uri.parse('sqlite3.wasm'), ...)`; `sqlite3.wasm` next to the page is the default.
- **Web files:** `dart run cloud_firestore_dart_sqlite:setup_web web` compiles the worker into
  `web/` and prints the `curl` line for `sqlite3.wasm`.

## 1. `docs/guides/offline_persistence.md`

### "SQLite on the Dart VM", first paragraph and block

Old (from "The package does not open SQLite files itself" to the end of the first ```` ```dart ````
block):

> The package does not open SQLite files itself, so that you choose the binding. You pass a
> function that opens a database. A complete one for `package:sqlite3` is
> [`example/sqlite_database.dart`](...): copy it into your app and add `sqlite3: ^2.7.3` to your
> dependencies (in a Flutter app also `sqlite3_flutter_libs: ^0.5.0`, which bundles the native
> library). The opener uses `package:sqlite3/open.dart`, which `sqlite3` 3.x no longer has, so
> stay on 2.x for now.
>
> ```dart
> import 'dart:io';
>
> import 'sqlite_database.dart'; // copied from the package's example/ folder
>
> final Directory directory = Directory('/home/ada/.local/share/my_app');
> final Firestore firestore = Firestore.instanceFor(
>   app: app,
>   openDatabase: sqliteOpener(directory),
>   settings: FirestoreSettings(cacheSettings: PersistentCacheSettings()),
> );
> ```

New:

````markdown
The package does not open SQLite files itself, so that you choose the binding. You pass a
function that opens a database. The companion package
[`cloud_firestore_dart_sqlite`](../../cloud_firestore/cloud_firestore_dart_sqlite/) has one on top
of `package:sqlite3`, for the VM, Flutter and the browser:

```shell
dart pub add cloud_firestore_dart_sqlite
```

```dart
import 'package:cloud_firestore_dart_sqlite/cloud_firestore_dart_sqlite.dart';

final Firestore firestore = Firestore.instanceFor(
  app: app,
  openDatabase: sqliteOpener(directory: '/home/ada/.local/share/my_app'),
  settings: FirestoreSettings(cacheSettings: PersistentCacheSettings()),
);
```

It works with `sqlite3` 2.7.3 to 3.x. With 3.x (Dart 3.10 and later) `sqlite3` bundles SQLite
itself and nothing else is needed; with 2.x a Flutter app adds `sqlite3_flutter_libs: ^0.5.0`
and a Linux server needs `libsqlite3.so`. Its README has the details per platform.
````

Same section, the paragraph after the block: replace "call the callbacks in the order the example
does" with "call the callbacks in the order the opener of `cloud_firestore_dart_sqlite` does"
(the rest stays).

### "SQLite page cache"

Old:

> (`sqlite3_flutter_libs`) and 2000 pages (8 MB) in the library of macOS. The example opener takes
> `pageCacheMb` to change it:
>
> ```dart
> final Directory directory = Directory('/home/ada/.local/share/my_app');
> final OpenDatabase opener = sqliteOpener(directory, pageCacheMb: 32);
> ```

New:

````markdown
(`sqlite3` 3.x and `sqlite3_flutter_libs`) and 2000 pages (8 MB) in the library of macOS.
`sqliteOpener` takes `pageCacheMb` to change it:

```dart
final OpenDatabase opener = sqliteOpener(
  directory: '/home/ada/.local/share/my_app',
  pageCacheMb: 32,
);
```
````

### "On the web", first two paragraphs and both blocks

Old: from "The cache is in memory by default. To keep it across page loads, copy" to the end of
the second ```` ```dart ```` block (the one with `opfsWorker: Uri.parse('sqlite_opfs_worker.js')`).

New:

````markdown
The cache is in memory by default. To keep it across page loads, use the same
`cloud_firestore_dart_sqlite` package and serve the `sqlite3.wasm` file of the `sqlite3` version
your app resolves next to your page. One command prints where to get it:

```shell
dart run cloud_firestore_dart_sqlite:setup_web web
```

```dart
import 'package:cloud_firestore_dart_sqlite/cloud_firestore_dart_sqlite.dart';

// IndexedDB: SQLite runs in the page on a copy of the whole database in memory.
final Firestore firestore = Firestore.instanceFor(
  app: app,
  openDatabase: sqliteOpener(), // loads sqlite3.wasm next to the page
);
```

To keep the database out of memory, pass the URL of the OPFS worker, which the same command
compiled to `web/sqlite_opfs_worker.js`. SQLite then runs in that dedicated worker on a file in
the origin private file system (OPFS) and reads what it needs. No cross-origin isolation headers
are needed; a browser without synchronous OPFS access in workers falls back to IndexedDB, and
the first OPFS open of a cache that is in IndexedDB moves it, pending writes included.

```dart
import 'package:cloud_firestore_dart_sqlite/cloud_firestore_dart_sqlite.dart';

final Firestore firestore = Firestore.instanceFor(
  app: app,
  openDatabase: sqliteOpener(opfsWorker: Uri.parse('sqlite_opfs_worker.js')),
);
```
````

Same section, the "One tab at a time" bullet: replace "the `openWithMemoryFallback` helper of the
example waits" with "`openWithMemoryFallback` of `cloud_firestore_dart_sqlite` waits".

## 2. `docs/guides/flutter.md`

### "Install"

Old:

> ```shell
> flutter pub add cloud_firestore_dart firebase_app_dart path_provider rxdart
> flutter pub add sqlite3:^2.7.3 sqlite3_flutter_libs:^0.5.40   # the cache on disk
> flutter pub add connectivity_plus                              # optional, see Connectivity
> ```
>
> Copy [`example/sqlite_database.dart`](...) of the package into your `lib/`. It is written for
> `package:sqlite3` 2.x, so keep `sqlite3` on 2.x and `sqlite3_flutter_libs` on 0.5.x, which
> bundles the native SQLite library with the app. `sqlite3` 3.x bundles the library itself and
> has a different loading API; the opener has not been ported to it.

New:

````markdown
```shell
flutter pub add cloud_firestore_dart firebase_app_dart path_provider rxdart
flutter pub add cloud_firestore_dart_sqlite                    # the cache on disk
flutter pub add connectivity_plus                              # optional, see Connectivity
```

`cloud_firestore_dart_sqlite` brings `sqlite3`. On Flutter 3.38 or later pub picks `sqlite3`
3.x, which bundles SQLite with the app through a build hook: add nothing else, and remove
`sqlite3_flutter_libs` if you had it. On an older Flutter pub picks `sqlite3` 2.x; then also add
`sqlite3_flutter_libs: ^0.5.40`, which bundles the native library.
````

### "Create the app and the instance before `runApp`", the code block

The block is a copy of `examples/flutter_notes/lib/firestore_setup.dart`. Change the import line
`import 'sqlite_database.dart';` (if the block shows it) to
`import 'package:cloud_firestore_dart_sqlite/cloud_firestore_dart_sqlite.dart';`, and

> ```dart
>     openDatabase: sqliteOpener(Directory('${directory.path}/firestore')),
> ```

to

```dart
    openDatabase: sqliteOpener(directory: '${directory.path}/firestore'),
```

### "The SQLite cache on each platform"

Old: the paragraph starting "Without `openDatabase` the cache is in memory" and the table under
it (header `| Platform | Library that `package:sqlite3` 2.x loads |`, four rows).

New:

```markdown
Without `openDatabase` the cache is in memory and gone when the app stops. With `sqliteOpener` of
`cloud_firestore_dart_sqlite` it is one SQLite file per app name, project and database, in the
directory you pass (the example uses `getApplicationSupportDirectory()` plus `/firestore`). Where
the SQLite library comes from:

| Platform | `sqlite3` 3.x (Flutter 3.38 and later) | `sqlite3` 2.x |
| --- | --- | --- |
| Android | bundled by the build hook of `sqlite3` | `libsqlite3.so` bundled by `sqlite3_flutter_libs` |
| iOS, macOS | bundled by the build hook | the framework bundled by `sqlite3_flutter_libs`; the system library if it is missing |
| Windows | bundled by the build hook | `sqlite3.dll` bundled by `sqlite3_flutter_libs`, else `winsqlite3.dll` of Windows |
| Linux | bundled by the build hook | the library bundled by `sqlite3_flutter_libs`, else the system `libsqlite3.so` |
```

The paragraph after the table stays, except "Only the macOS row was tried with this example."
which becomes "Only macOS was tried with this example, with `sqlite3` 2.x." (the example app has
not been rebuilt with the package; see section 9).

### "What was tried where", rows Windows and Web

Old Windows cell: "Not tested, not built. `sqlite3.dll` must ship with the app
(`sqlite3_flutter_libs` does that); `clearPersistence()` fails while another handle has the file
open". New: "Not tested, not built. `sqlite3` 3.x bundles SQLite (with 2.x, `sqlite3_flutter_libs`
does); `clearPersistence()` fails while another handle has the file open".

Old Web cell ends with "`sqlite_database.dart` uses `dart:ffi` and does not compile for the web;
use `example/sqlite_database_web.dart` there ([Offline persistence on the web](...))". New
ending: "`sqliteOpener` of `cloud_firestore_dart_sqlite` compiles for the web too and keeps the
cache in IndexedDB or OPFS there; pass no directory on the web (`directory: kIsWeb ? null :
...`) and see [Offline persistence on the web](offline_persistence.md#on-the-web)".

## 3. `docs/guides/web.md`

### "Choosing a cache"

Table rows: `sqliteWebOpener(sqlite3Wasm: ...)` becomes `sqliteOpener()`, and
`sqliteWebOpener(sqlite3Wasm: ..., opfsWorker: ...)` becomes `sqliteOpener(opfsWorker: ...)`.

Old: from "The persistent caches are not part of the package API: copy" to the end of the
```` ```dart ```` block after the `dart compile js` block.

New:

````markdown
The persistent caches come from the companion package `cloud_firestore_dart_sqlite`. Add it, and
let its setup command compile the OPFS worker into your web directory and print where to get the
`sqlite3.wasm` file of the `sqlite3` version you resolve:

```sh
dart pub add cloud_firestore_dart_sqlite
dart run cloud_firestore_dart_sqlite:setup_web web
```

The worker is JavaScript also when the page itself uses dart2wasm. Run the command again when
`cloud_firestore_dart_sqlite` or `sqlite3` changes version.

```dart
import 'package:cloud_firestore_dart_sqlite/cloud_firestore_dart_sqlite.dart';

final Firestore firestore = Firestore.instanceFor(
  app: app,
  openDatabase: sqliteOpener(opfsWorker: Uri.parse('sqlite_opfs_worker.js')),
  settings: FirestoreSettings(cacheSettings: PersistentCacheSettings()),
);
```
````

### "One tab at a time"

Old: "The example opener has a helper that waits for a first cache-only operation and falls back
to a memory cache:" and the block

> ```dart
> import 'sqlite_database_web.dart'; // copied from the package's example/ folder
>
> final Firestore firestore = await openWithMemoryFallback(
>   app: app,
>   sqlite3Wasm: Uri.parse('sqlite3.wasm'),
>   settings: FirestoreSettings(cacheSettings: PersistentCacheSettings()),
> );
> ```

New:

````markdown
`openWithMemoryFallback` of `cloud_firestore_dart_sqlite` waits for a first cache-only
operation and falls back to a memory cache:

```dart
import 'package:cloud_firestore_dart_sqlite/cloud_firestore_dart_sqlite.dart';

final Firestore firestore = await openWithMemoryFallback(
  app: app,
  openDatabase: sqliteOpener(),
  settings: FirestoreSettings(cacheSettings: PersistentCacheSettings()),
);
// Null with a memory cache: this tab did not get the persistent one.
final bool persistent = firestore.persistentCacheIndexManager != null;
```
````

### "dart2js or dart2wasm"

Old: "the example opener works around a slowness of `sqlite3` 2.9.4 under dart2wasm". New: "the
opener works around a slowness of `sqlite3` 2.9.4 under dart2wasm (fixed in `sqlite3` 3.8)".

## 4. `docs/guides/multiple_clients.md`, "In practice"

Old:

> ```dart
> import 'dart:io';
>
> import 'sqlite_database.dart'; // copied from the package's example/ folder
>
> final Directory directory = Directory('/home/ada/.local/share/my_app');
>
> // In the background isolate: the same project, another app name, another cache file.
> final FirebaseApp worker = FirebaseApp.withOptions(app.options, name: 'background-sync');
> final Firestore workerFirestore = Firestore.instanceFor(
>   app: worker,
>   openDatabase: sqliteOpener(directory),
> );
> ```

New:

```dart
import 'package:cloud_firestore_dart_sqlite/cloud_firestore_dart_sqlite.dart';

// In the background isolate: the same project, another app name, another cache file.
final FirebaseApp worker = FirebaseApp.withOptions(app.options, name: 'background-sync');
final Firestore workerFirestore = Firestore.instanceFor(
  app: worker,
  openDatabase: sqliteOpener(directory: '/home/ada/.local/share/my_app'),
);
```

## 5. `docs/guides/platforms.md`

### "The Dart VM and Flutter", the Linux and Windows bullets

Old Linux bullet: "Linux: `package:sqlite3` 2.x loads `libsqlite3.so`, ... The opener in
`example/sqlite_database.dart` falls back to `libsqlite3.so.0`."

New:

```markdown
- Linux: with `sqlite3` 3.x (Dart 3.10 and later) `cloud_firestore_dart_sqlite` uses the SQLite
  that the build hook of `sqlite3` bundles (prebuilt, glibc 2.24 or later); `dart build cli`
  puts it next to the program, `dart compile exe` does not and then needs the system library.
  `sqlite3` 2.x loads `libsqlite3.so`, which only the development package installs
  (`libsqlite3-dev` on Debian and Ubuntu); with just the runtime package (`libsqlite3-0`) it fails
  with "Failed to load dynamic library 'libsqlite3.so'". The README of
  `cloud_firestore_dart_sqlite` has a three-line override that falls back to `libsqlite3.so.0`.
```

Old Windows bullet start: "Windows: `package:sqlite3` loads `sqlite3.dll`, which Windows does not
ship: put it next to the executable or on the `PATH` (`sqlite3_flutter_libs` bundles it in a
Flutter app)." New start: "Windows: `sqlite3` 3.x bundles SQLite; 2.x loads `sqlite3.dll` from
next to the executable or the `PATH` and, from 2.7.5, falls back to `winsqlite3.dll` of Windows
(not tried here)." The rest of the bullet (`LockFileEx`, `clearPersistence`) stays.

### "The web (experimental)", first bullet

Old: "To keep it across page loads, pass the `OpenDatabase` of [`example/sqlite_database_web.dart`]
(...) (copy the file into your app): SQLite compiled to WebAssembly by `package:sqlite3`." New:
"To keep it across page loads, pass `sqliteOpener()` of `cloud_firestore_dart_sqlite`: SQLite
compiled to WebAssembly by `package:sqlite3`."

Old (OPFS sub-bullet): "**OPFS** (the origin private file system), when you also copy
[`example/sqlite_opfs_worker.dart`](...), compile it with `dart compile js` and pass its URL as
`opfsWorker`." New: "**OPFS** (the origin private file system), when you pass the URL of the
worker that `dart run cloud_firestore_dart_sqlite:setup_web web` compiles as `opfsWorker`."

Old: "`openWithMemoryFallback` in that file does this." New: "`openWithMemoryFallback` of the
package does this."

Old (dart2wasm sub-bullet end): "Use the opener as it is in `example/`; an older copy without
`_ReadCopyFileSystem` is that slow." New: "`cloud_firestore_dart_sqlite` keeps that workaround;
`sqlite3` 3.8 fixed the slowness itself."

## 6. `docs/guides/migrating_from_flutterfire.md`

### "Dependencies"

Old: "For a persistent cache in a Flutter app, add `sqlite3` (2.x) and `sqlite3_flutter_libs`
(see below)." New: "For a persistent cache in a Flutter app, add `cloud_firestore_dart_sqlite`
(see below)."

### "Persistence"

Old:

> For a disk cache in a Flutter app, copy `example/sqlite_database.dart` from the package into the
> app, add `sqlite3: ^2.7.3` and `sqlite3_flutter_libs: ^0.5.0` (the opener does not work with
> `sqlite3` 3.x yet), and pass a directory from `path_provider`:
>
> ```dart
> import 'dart:io';
>
> import 'sqlite_database.dart'; // copied from the package's example/ folder
>
> final Directory cacheDirectory = Directory('<the application support directory>');
> final Firestore persistent = Firestore.instanceFor(
>   app: app,
>   openDatabase: sqliteOpener(cacheDirectory),
>   settings: FirestoreSettings(cacheSettings: PersistentCacheSettings()),
> );
> ```

New:

````markdown
For a disk cache in a Flutter app, add `cloud_firestore_dart_sqlite` and pass a directory from
`path_provider` (on Flutter 3.38 and later nothing else; on older ones also
`sqlite3_flutter_libs: ^0.5.0`):

```dart
import 'package:cloud_firestore_dart_sqlite/cloud_firestore_dart_sqlite.dart';

final String cacheDirectory = '<the application support directory>';
final Firestore persistent = Firestore.instanceFor(
  app: app,
  openDatabase: sqliteOpener(directory: cacheDirectory),
  settings: FirestoreSettings(cacheSettings: PersistentCacheSettings()),
);
```
````

## 7. `docs/guides/for_ai_agents.md`

### "Which package for what", the disk cache row

Old: `| A disk cache on the VM or in Flutter | `sqlite3: ^2.7.3` (and `sqlite3_flutter_libs: ^0.5.0` in Flutter) | copy `example/sqlite_database.dart` of `cloud_firestore_dart` into the app |`

New: `| A disk cache (VM, Flutter, web) | `cloud_firestore_dart_sqlite: ^0.1.0` | `package:cloud_firestore_dart_sqlite/cloud_firestore_dart_sqlite.dart` |`

### "A Flutter app with the SQLite cache"

Old: the shell block with `'sqlite3:^2.7.3' 'sqlite3_flutter_libs:^0.5.0'`, the paragraph "Pin
`sqlite3` to 2.x: ... so this program is not for the web)." and, in the ```` ```dart flutter ````
block, `import 'dart:io';`, `import 'sqlite_database.dart'; // copied from cloud_firestore_dart's
example/ folder` and `openDatabase: sqliteOpener(directory),`.

New shell block and paragraph:

````markdown
```shell
flutter pub add cloud_firestore_dart firebase_app_dart path_provider cloud_firestore_dart_sqlite
```

`cloud_firestore_dart_sqlite` brings `sqlite3`; on Flutter 3.38 or later that is 3.x, which
bundles SQLite itself. On an older Flutter add `sqlite3_flutter_libs: ^0.5.0` too. Do not copy
any opener file.
````

In the block: drop `import 'dart:io';` if nothing else uses it (the block still uses `Directory`
from `getApplicationSupportDirectory()`, so keep it), replace the copied import with
`import 'package:cloud_firestore_dart_sqlite/cloud_firestore_dart_sqlite.dart';`, and replace
`openDatabase: sqliteOpener(directory),` with
`openDatabase: sqliteOpener(directory: '${directory.path}/firestore'),`.

### The paragraph after that block

Old: "For the web, use a memory cache or the opener in `example/sqlite_database_web.dart` (see
[Offline persistence](offline_persistence.md#on-the-web))." New: "For the web, use a memory cache
or `sqliteOpener()` without a directory, with `sqlite3.wasm` next to the page (see
[Offline persistence](offline_persistence.md#on-the-web))."

### "This, not that", the persistence row

`openDatabase: sqliteOpener(dir)` becomes `openDatabase: sqliteOpener(directory: dir)` (package
`cloud_firestore_dart_sqlite`).

### "Rules", items 6 and 7

Old 6 (end): "The package has no SQLite binding of its own: copy `example/sqlite_database.dart`
(VM, Flutter) or `example/sqlite_database_web.dart` (web)." New: "The SQLite opener is in the
companion package `cloud_firestore_dart_sqlite` (`sqliteOpener`, VM, Flutter and web); never copy
the old `example/sqlite_database*.dart` files."

Old 7: "`package:firebase_auth_providers_dart/adc.dart`, the copied `sqlite_database.dart` (also
`dart:ffi`), and any `Platform.environment` you read." New:
"`package:firebase_auth_providers_dart/adc.dart` and any `Platform.environment` you read.
`cloud_firestore_dart_sqlite` compiles everywhere (conditional imports)."

### "Where to look next", two rows

Old: `| A disk cache, offline reads and writes | `offline_persistence.dart`, `sqlite_database.dart` |`
and `| The web cache | `sqlite_database_web.dart` |`. New:
`| A disk cache, offline reads and writes | `offline_persistence.dart`; the opener: `cloud_firestore_dart_sqlite` |`
and `| The web cache | the README of `cloud_firestore_dart_sqlite` |`.

## 8. `skills/cloud-firestore-dart/reference/setup.md`

### "Dependencies"

Old:

> ```shell
> dart pub add cloud_firestore_dart firebase_app_dart
> dart pub add firebase_auth_providers_dart          # signed-in users or server credentials
> dart pub add 'sqlite3:^2.7.3'                      # only for a disk cache on the VM
> ```
>
> In Flutter, for a disk cache:
>
> ```shell
> flutter pub add cloud_firestore_dart firebase_app_dart path_provider \
>   'sqlite3:^2.7.3' 'sqlite3_flutter_libs:^0.5.0'
> ```
>
> `sqlite3` must stay on 2.x: ... For the web the opener is `example/sqlite_database_web.dart` in
> the same folder.

New:

````markdown
```shell
dart pub add cloud_firestore_dart firebase_app_dart
dart pub add firebase_auth_providers_dart          # signed-in users or server credentials
dart pub add cloud_firestore_dart_sqlite           # only for a disk cache
```

In Flutter, for a disk cache:

```shell
flutter pub add cloud_firestore_dart firebase_app_dart path_provider cloud_firestore_dart_sqlite
```

The opener is `sqliteOpener({String? directory, int? pageCacheMb, Uri? sqlite3Wasm,
Uri? opfsWorker, ...})` from
`package:cloud_firestore_dart_sqlite/cloud_firestore_dart_sqlite.dart`; it compiles on the VM,
in Flutter and on the web. Do not copy opener files. With Dart older than 3.10 (Flutter older
than 3.38) pub resolves `sqlite3` 2.x: then a Flutter app also adds
`sqlite3_flutter_libs: ^0.5.0`.
````

### "Flutter with the SQLite cache"

In the block: `import 'sqlite_database.dart'; // the copied opener` becomes
`import 'package:cloud_firestore_dart_sqlite/cloud_firestore_dart_sqlite.dart';` and
`openDatabase: sqliteOpener(directory),` becomes
`openDatabase: sqliteOpener(directory: '${directory.path}/firestore'),`.

## 9. The example apps

### `examples/flutter_notes`

- `pubspec.yaml`: replace

  ```yaml
    # sqlite_database.dart is written for the 2.x API of package:sqlite3
    # (package:sqlite3/open.dart). sqlite3_flutter_libs bundles the native
    # library with the app; its 0.5.x releases go with sqlite3 2.x.
    sqlite3: ^2.7.3
    sqlite3_flutter_libs: ^0.5.40
  ```

  with `  cloud_firestore_dart_sqlite: ^0.1.0` (in sorted order after `cloud_firestore_dart`).
  The examples resolve every package from pub.dev (they have no `pubspec_overrides.yaml`), so
  this only resolves once 0.1.0 is published; before that it needs a `pubspec_overrides.yaml`
  with `cloud_firestore_dart_sqlite: {path: ../../cloud_firestore/cloud_firestore_dart_sqlite}`.
  Flutter 3.44.9 then resolves `sqlite3` 3.x; the app must be rebuilt and tried on macOS again.
- Delete `lib/sqlite_database.dart`.
- `lib/firestore_setup.dart`: `import 'sqlite_database.dart';` becomes
  `import 'package:cloud_firestore_dart_sqlite/cloud_firestore_dart_sqlite.dart';`, and
  `openDatabase: sqliteOpener(Directory('${directory.path}/firestore')),` becomes
  `openDatabase: sqliteOpener(directory: '${directory.path}/firestore'),`.
- `README.md`, "Notes", the first bullet ("`sqlite_database.dart` is written for `package:sqlite3`
  2.x ... the opener has not been ported to 3.x.") becomes: "- The SQLite cache comes from
  `cloud_firestore_dart_sqlite`, which resolves `sqlite3` 3.x here: SQLite is bundled by its build
  hook on every platform, no `sqlite3_flutter_libs`."

### `examples/web_app`

- `pubspec.yaml`: add `cloud_firestore_dart_sqlite: ^0.1.0` (resolves once published, as for
  `flutter_notes` above). Keep `sqlite3: 2.9.4` pinned (the checksum in the README is that build's),
  but change the comment to: "Pinned: the sqlite3.wasm file next to the page must be the build of
  this exact version (see README.md)."
- Delete `lib/sqlite_database_web.dart` and `web/sqlite_opfs_worker.dart`.
- `web/main.dart`: `import 'package:web_app/sqlite_database_web.dart';` becomes
  `import 'package:cloud_firestore_dart_sqlite/cloud_firestore_dart_sqlite.dart';`, and

  ```dart
        final Firestore firestore = await openWithMemoryFallback(
          app: app,
          sqlite3Wasm: Uri.parse('sqlite3.wasm'),
          opfsWorker: cache == CacheChoice.opfs
              ? Uri.parse('sqlite_opfs_worker.js')
              : null,
          settings: settings.copyWith(cacheSettings: PersistentCacheSettings()),
        );
  ```

  becomes

  ```dart
        final Firestore firestore = await openWithMemoryFallback(
          app: app,
          openDatabase: sqliteOpener(
            opfsWorker: cache == CacheChoice.opfs
                ? Uri.parse('sqlite_opfs_worker.js')
                : null,
          ),
          settings: settings.copyWith(cacheSettings: PersistentCacheSettings()),
        );
  ```

- `README.md`, "Build and run": replace

  ```sh
  # The worker of the OPFS cache (always JavaScript, also for a dart2wasm page).
  dart compile js -O2 -o build/web/sqlite_opfs_worker.js web/sqlite_opfs_worker.dart
  ```

  with

  ```sh
  # The worker of the OPFS cache (always JavaScript, also for a dart2wasm page). It also prints
  # the URL of the sqlite3.wasm below.
  dart run cloud_firestore_dart_sqlite:setup_web build/web
  ```

- `README.md`, "Files": drop the rows of `lib/sqlite_database_web.dart` and
  `web/sqlite_opfs_worker.dart` and the paragraph "When you update `cloud_firestore_dart`, copy
  the two files again ...". The sizes table stays valid (the worker is the same code: the setup
  command produced a 185,379-byte `sqlite_opfs_worker.js` with `sqlite3` 2.9.4, the size in the
  table).

## 10. Shared lists

### Root `README.md`, "Packages" table, a fourth row

```markdown
| `cloud_firestore_dart_sqlite` | `cloud_firestore/cloud_firestore_dart_sqlite` | The SQLite offline cache for `cloud_firestore_dart` on the VM, in Flutter and in the browser (`sqliteOpener`) |
```

And in "License": "`cloud_firestore_dart`, `firebase_app_dart`, `firebase_auth_providers_dart`
and `cloud_firestore_dart_sqlite` are licensed under the Apache License 2.0".

### `docs/guides/README.md`, first paragraph

Old: "Guides for `cloud_firestore_dart`, the unofficial pure-Dart Cloud Firestore client, its app
layer `firebase_app_dart` and the token providers of `firebase_auth_providers_dart`." New: "Guides
for `cloud_firestore_dart`, the unofficial pure-Dart Cloud Firestore client, its app layer
`firebase_app_dart`, the token providers of `firebase_auth_providers_dart` and the SQLite cache
of `cloud_firestore_dart_sqlite`."

### `AGENTS.md`, the package table

Add `| `cloud_firestore_dart_sqlite` | `cloud_firestore/cloud_firestore_dart_sqlite` |` and change
"Maintained, tested and published (version 0.1.1, Dart `^3.8.0`):" to say that
`cloud_firestore_dart_sqlite` is at 0.1.0 (once published).

### `llms.txt`

Under "## Packages" add:

```markdown
- [cloud_firestore_dart_sqlite README](https://raw.githubusercontent.com/long1eu/firebase_dart_sdk/main/cloud_firestore/cloud_firestore_dart_sqlite/README.md): the SQLite offline cache (`sqliteOpener`) for the VM, Flutter and the browser
```

Under "## Examples" replace the `sqlite_database.dart` line with:

```markdown
- [cloud_firestore_dart_sqlite example](https://raw.githubusercontent.com/long1eu/firebase_dart_sdk/main/cloud_firestore/cloud_firestore_dart_sqlite/example/main.dart): a SQLite cache on disk, written, reopened and read offline
```

### `tool/test_all.sh`

Packages are a fixed list (`PACKAGES=(...)`, `name|dir|test path`; an empty test path means
`test/`). Add after the `cloud_firestore_dart` line:

```bash
  "cloud_firestore_dart_sqlite|cloud_firestore/cloud_firestore_dart_sqlite|"
```

`dart test test` there runs the VM tests; the emulator test skips itself without
`FIRESTORE_EMULATOR_HOST` and the browser test is `@TestOn('browser')`. With `sqlite3` 3.x the
first `dart test` runs the build hook of `sqlite3`, which downloads the SQLite library for the
host from GitHub (cached in `.dart_tool`), so CI needs network access there. The browser test
needs `sqlite3.wasm` of the version in that package's `pubspec.lock` (3.9.1): see
`test/browser/README.md` of the package; `tool/build_web_test_assets.sh` would need a section
for it with a pinned checksum (GitHub shows
`sha256:e7451780e78c56ff864fe9317a0fbcd6aeb2e8de3beba7f5efd963202f7ec3d9` for the
`sqlite3.wasm` asset of `sqlite3-3.9.1`; not downloaded or checked here).

## 11. Other places that mention the copied files

Not among the eight, same treatment when you get there:

- `docs/guides/troubleshooting.md`: "SQLite library not found (Linux, Windows)" (the fix becomes
  "use `cloud_firestore_dart_sqlite` with `sqlite3` 3.x, which bundles SQLite; with 2.x install
  `libsqlite3-dev` or use the override in its README"), "A second browser tab cannot use the
  cache" (`openWithMemoryFallback` of `cloud_firestore_dart_sqlite`), and "database is locked"
  ("With the opener of `cloud_firestore_dart_sqlite`, which reports ...").
- `docs/guides/server.md`, "Containers": the `libsqlite3` bullet. With `sqlite3` 3.x, `dart build
  cli` bundles `libsqlite3.so` in `bundle/lib/`; `dart compile exe` does not (not tried in a
  container).
- `docs/ARCHITECTURE.md` line 162 ("the SQLite-on-IndexedDB opener of `example/...`").
- `skills/cloud-firestore-dart/SKILL.md` (workflow step 1 pins `sqlite3` 2.x; rule at line 80),
  `reference/api_map.md` and `reference/offline_and_errors.md` (the cache table).
- `docs/migrating_from_vm_packages.md` line 209.
- `cloud_firestore_dart/example/README.md` (the three rows) and the doc comment of `OpenDatabase`
  in `lib/src/firebase/firestore/util/database.dart` ("See `example/sqlite_database.dart`"): see
  the report for the proposed wording; both are in the published package, so they change with
  its next release.
