// Opens the IndexedDB database that the JS SDK wrote (writer.js, same origin) and decodes one remote document entry
// and the pending mutation batches into the model classes of cloud_firestore_dart, using its LocalSerializer.
// Only reads; the database is opened at its current version so nothing is upgraded.
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;
import 'package:fixnum/fixnum.dart';
import 'package:web/web.dart' as web;

final StringBuffer out = StringBuffer();
void log(String m) {
  out.writeln(m);
  web.document.body!.textContent = out.toString();
}

Future<T> request<T extends JSAny?>(web.IDBRequest r) {
  final Completer<T> c = Completer<T>();
  r.onsuccess = ((web.Event _) => c.complete(r.result as T)).toJS;
  r.onerror = ((web.Event _) => c.completeError(
    'IDB error ${r.error?.name}',
  )).toJS;
  return c.future;
}

/// The value as a Dart JSON tree: JSON.stringify in JS, jsonDecode in Dart (what an importer would do with the
/// structured-clone values).
Object? toJson(JSAny? v) {
  final JSObject json = web.window.getProperty<JSObject>('JSON'.toJS);
  return jsonDecode(json.callMethod<JSString>('stringify'.toJS, v).toDart);
}

Future<List<JSAny?>> getAll(web.IDBDatabase db, String store) async {
  final web.IDBTransaction tx = db.transaction(store.toJS, 'readonly');
  final JSArray<JSAny?> all = await request<JSArray<JSAny?>>(
    tx.objectStore(store).getAll(),
  );
  return all.toDart;
}

Future<void> main() async {
  try {
    final JSArray<web.IDBDatabaseInfo> dbs =
        await (web.window.indexedDB.databases()).toDart;
    final List<String> names = <String>[
      for (final web.IDBDatabaseInfo i in dbs.toDart) '${i.name}@v${i.version}',
    ];
    log('databases: $names');
    const String dbName = 'firestore/[DEFAULT]/demo-idb/main';
    final web.IDBDatabase db = await request<web.IDBDatabase>(
      web.window.indexedDB.open(dbName),
    );
    log('opened $dbName version ${db.version}');
    final List<String> stores = <String>[
      for (int i = 0; i < db.objectStoreNames.length; i++)
        db.objectStoreNames.item(i)!,
    ];
    log('stores: $stores');

    final LocalSerializer serializer = LocalSerializer(
      RemoteSerializer(DatabaseId.forProject('demo-idb')),
    );

    // Remote documents: the cached bundle document.
    for (final JSAny? e in await getAll(db, 'remoteDocumentsV14')) {
      final Map<String, Object?> row = toJson(e)! as Map<String, Object?>;
      log(
        'remoteDoc row keys: ${row.keys.toList()} readTime=${row['readTime']} hasCommitted=${row['hasCommittedMutations']}',
      );
      final proto.MaybeDocument m = proto.MaybeDocument();
      if (row['document'] != null) {
        m.document = proto.Document()
          ..mergeFromProto3Json(row['document'], ignoreUnknownFields: false);
      } else if (row['noDocument'] != null) {
        m.noDocument = proto.NoDocument()
          ..name =
              'projects/demo-idb/databases/(default)/documents/${(row['noDocument'] as Map)['path'].join('/')}'
          ..readTime = (proto.Timestamp()
            ..seconds = Int64(
              ((row['noDocument'] as Map)['readTime'] as Map)['seconds'] as int,
            )
            ..nanos =
                ((row['noDocument'] as Map)['readTime'] as Map)['nanoseconds']
                    as int);
      }
      m.hasCommittedMutations = row['hasCommittedMutations'] == true;
      final MaybeDocument doc = serializer.decodeMaybeDocument(m);
      log('DECODED remote doc: $doc');
    }

    // Mutation batches.
    for (final JSAny? e in await getAll(db, 'mutations')) {
      final Map<String, Object?> row = toJson(e)! as Map<String, Object?>;
      log(
        'mutation row keys: ${row.keys.toList()} user=${row['userId']} batch=${row['batchId']}',
      );
      final proto.WriteBatch wb = proto.WriteBatch()
        ..batchId = row['batchId']! as int
        ..localWriteTime = (rpcMillis(row['localWriteTimeMs']! as int));
      for (final Object? w
          in (row['baseMutations'] as List<Object?>? ?? <Object?>[])) {
        wb.baseWrites.add(
          proto.Write()..mergeFromProto3Json(w, ignoreUnknownFields: false),
        );
      }
      for (final Object? w in row['mutations']! as List<Object?>) {
        wb.writes.add(
          proto.Write()..mergeFromProto3Json(w, ignoreUnknownFields: false),
        );
      }
      final MutationBatch batch = serializer.decodeMutationBatch(wb);
      log('DECODED batch: $batch');
    }
    document.title = 'ok: ${out.toString().replaceAll('\n', ' | ')}';
  } catch (e, st) {
    log('ERROR $e\n$st');
    document.title = 'error: ${out.toString().replaceAll('\n', ' | ')}';
  }
}

proto.Timestamp rpcMillis(int ms) {
  final Timestamp t = Timestamp.fromMillisecondsSinceEpoch(ms);
  return RemoteSerializer(DatabaseId.forProject('demo-idb')).encodeTimestamp(t);
}

web.Document get document => web.document;
