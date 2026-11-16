/// The dedicated worker of the OPFS storage, as a library.
///
/// `dart run cloud_firestore_dart_sqlite:setup_web` compiles an entry point
/// that calls `runOpfsWorker` to JavaScript; you only need this library to
/// build the worker another way:
///
/// ```dart
/// import 'package:cloud_firestore_dart_sqlite/opfs_worker.dart';
///
/// void main() => runOpfsWorker();
/// ```
///
/// Compile it with `dart compile js -O2`, also when the page itself is
/// compiled with dart2wasm.
library;

export 'src/web/sqlite_opfs_worker.dart' show isTransientError, runOpfsWorker;
