import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/js_sdk_import/js_sdk_importer.dart';

/// Imports the cache of the official Firebase JS SDK into the cache of [firestore], once, so that a web app that used
/// the JS SDK with persistence can switch to this SDK on the same browser profile without losing its pending writes.
///
/// **Experimental**: the API and the behaviour may change in a minor version.
///
/// It reads the IndexedDB database the JS SDK keeps for the same app and database,
/// `firestore/<app name>/<project id>[.<database id>]/main` (the app name is `[DEFAULT]` for the default app; pass
/// [jsAppName] when the JS app had another name than [FirebaseFirestore.app]), and imports:
///
/// - the pending writes of every user, in their order, with their local write times, into the mutation queues of
///   this cache, whatever it is (memory or SQLite). The documents the app reads locally include them, and they are
///   sent to the backend when the client is online. Each imported write is then removed from the JS database;
/// - with [includeDocuments], the cached documents with their versions and read times, the first time only, so that
///   the first start offline after the switch still shows data. A document that this cache holds in a newer version
///   is kept.
///
/// Targets, resume tokens, index configuration, bundles and named queries are not imported: listeners read their
/// results from the backend again.
///
/// Call it once at every start of the app, right after creating [firestore] and before any write: it runs on the
/// queue of the client, in order with the operations of the app. When there is nothing left to import it only opens
/// the JS database, and when there is no JS database it returns [JsSdkCacheImportStatus.noJsDatabase]. On other
/// platforms than the web it does nothing and returns [JsSdkCacheImportStatus.notOnWeb].
///
/// A crash at any point, followed by a restart and another call, neither loses a pending write nor imports one twice:
/// the cache records what it imported in the transaction that adds the writes, and the next call finishes their
/// removal from the JS database. With a memory cache that record, like the writes, lasts as long as the page: a write
/// imported into a memory cache is lost when the page closes before the backend acknowledged it, like every other
/// write made with a memory cache.
///
/// It throws a [JsSdkCacheImportException] and imports nothing when:
///
/// - a JS tab may still use the database ([JsSdkCacheImportRefusal.jsClientActive]): the JS SDK's primary lease
///   was refreshed less than 5 seconds ago, or one of its clients refreshed its metadata less than 30 minutes ago and
///   did not mark itself as closed. A JS tab and a page of this SDK can not share the cache; close the JS tabs (a tab
///   that closes normally marks itself) or wait;
/// - the database has a schema version this SDK does not read
///   ([JsSdkCacheImportRefusal.unsupportedSchemaVersion]): versions 5 to 18 are read (the pending writes have been
///   stored in the same shape since version 5; the cached documents are read from version 13 on);
/// - this cache already holds pending writes of a user who has pending writes in the JS database
///   ([JsSdkCacheImportRefusal.pendingWritesInCache]): the imported writes are older and would be sent after them.
///   This happens when the app wrote before calling this function;
/// - a pending write can not be read ([JsSdkCacheImportRefusal.unreadableWrites]).
///
/// The JS database is never deleted: call [deleteJsSdkCache] when the app no longer needs it.
Future<JsSdkCacheImportResult> importJsSdkCache(
  FirebaseFirestore firestore, {
  bool includeDocuments = true,
  String? jsAppName,
}) {
  return runJsSdkCacheImport(
    firestore,
    includeDocuments: includeDocuments,
    jsAppName: jsAppName,
  );
}

/// Deletes the IndexedDB database of the official Firebase JS SDK for the app and database of [firestore] (see
/// [importJsSdkCache]). Returns false when there is none, or on other platforms than the web.
///
/// **Experimental**: the API and the behaviour may change in a minor version.
///
/// Throws a [JsSdkCacheImportException] when a JS tab may still use the database
/// ([JsSdkCacheImportRefusal.jsClientActive]), and when it holds pending writes that [importJsSdkCache] did not
/// import ([JsSdkCacheImportRefusal.pendingWritesNotImported]) unless [discardPendingWrites] is true.
Future<bool> deleteJsSdkCache(
  FirebaseFirestore firestore, {
  bool discardPendingWrites = false,
  String? jsAppName,
}) {
  return runJsSdkCacheDelete(
    firestore,
    discardPendingWrites: discardPendingWrites,
    jsAppName: jsAppName,
  );
}

/// What [importJsSdkCache] did.
///
/// **Experimental**.
enum JsSdkCacheImportStatus {
  /// Not on the web: there is no JS SDK cache to import.
  notOnWeb,

  /// There is no database of the JS SDK for this app and database.
  noJsDatabase,

  /// The JS database holds nothing left to import.
  nothingToImport,

  /// Pending writes or documents were imported.
  imported,
}

/// Why [importJsSdkCache] or [deleteJsSdkCache] refused to run.
///
/// **Experimental**.
enum JsSdkCacheImportRefusal {
  /// A tab of the JS SDK may still use the database.
  jsClientActive,

  /// The database has a schema version that this SDK does not read.
  unsupportedSchemaVersion,

  /// This cache holds pending writes of a user who also has pending writes in the JS database.
  pendingWritesInCache,

  /// A pending write of the JS database could not be read.
  unreadableWrites,

  /// The JS database holds pending writes that were not imported (from [deleteJsSdkCache]).
  pendingWritesNotImported,
}

/// The error of [importJsSdkCache] and [deleteJsSdkCache] when they refuse to run. Nothing was imported or deleted.
///
/// **Experimental**.
final class JsSdkCacheImportException implements Exception {
  const JsSdkCacheImportException(this.reason, this.message);

  /// Why it refused.
  final JsSdkCacheImportRefusal reason;

  /// What was found, and what to do.
  final String message;

  @override
  String toString() => 'JsSdkCacheImportException(${reason.name}): $message';
}

/// The result of [importJsSdkCache].
///
/// **Experimental**.
final class JsSdkCacheImportResult {
  const JsSdkCacheImportResult({
    required this.status,
    required this.databaseName,
    this.users = 0,
    this.batches = 0,
    this.documents = 0,
    this.skipped = const <String>[],
  });

  /// What was done.
  final JsSdkCacheImportStatus status;

  /// The name of the JS SDK's IndexedDB database that was looked for.
  final String databaseName;

  /// The number of users whose pending writes were imported.
  final int users;

  /// The number of write batches imported (one per `set`, `update`, `delete` or committed `WriteBatch` of the app).
  final int batches;

  /// The number of cached documents imported (documents this cache held in the same or a newer version are not
  /// counted).
  final int documents;

  /// What was not imported, and why, one line each.
  final List<String> skipped;

  @override
  String toString() =>
      'JsSdkCacheImportResult(${status.name}, $databaseName, users: $users, batches: $batches, '
      'documents: $documents, skipped: $skipped)';
}
