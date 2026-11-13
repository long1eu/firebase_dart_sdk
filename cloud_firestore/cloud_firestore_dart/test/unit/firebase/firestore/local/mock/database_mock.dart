// The SQLite database of the tests: `package:sqlite3` on a file on the VM, its
// WebAssembly build in a browser.
export '../../../../../util/sqlite3_database.dart'
    if (dart.library.js_interop) '../../../../../util/sqlite3_database_web.dart';
