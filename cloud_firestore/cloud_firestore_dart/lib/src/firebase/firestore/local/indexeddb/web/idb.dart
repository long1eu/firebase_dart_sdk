/// Small helpers over the IndexedDB API of `package:web`, shared by the IndexedDB engine (`IndexedDbPersistence`) and
/// the import of a JS SDK cache (`js_sdk_database_web.dart`). Web only.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

@JS('JSON.stringify')
external JSString? _stringify(JSAny? value);

@JS('JSON.parse')
external JSAny? _parse(JSString text);

/// [value] as a JSON tree: the structured-clone values of IndexedDB through `JSON.stringify` and `jsonDecode`. The JS
/// SDK stores proto3 JSON, plain numbers, strings, booleans and arrays, which survive this unchanged (a `Uint8Array`
/// does not: read it with its own conversion).
Object? idbToDart(JSAny? value) {
  if (value == null) {
    return null;
  }
  final JSString? json = _stringify(value);
  return json == null ? null : jsonDecode(json.toDart);
}

/// The JS value of the JSON tree [tree] (maps, lists, strings, numbers, booleans and null), through `jsonEncode` and
/// `JSON.parse`. Numbers come out as JS numbers whatever their Dart type (`1.0` is `1`, as in JS).
JSAny? idbToJs(Object? tree) =>
    tree == null ? null : _parse(jsonEncode(tree).toJS);

/// The length of `JSON.stringify(value)`: the size the JS SDK accounts for a document (`dbDocumentSize`).
int idbJsonLength(JSAny? value) => _stringify(value)?.toDart.length ?? 0;

/// An IndexedDB key of strings, numbers (doubles included: the JS SDK bounds its ranges with `Infinity`) and arrays of
/// them.
JSAny idbKey(Object key) {
  if (key is String) {
    return key.toJS;
  } else if (key is int) {
    return key.toJS;
  } else if (key is double) {
    return key.toJS;
  } else if (key is List) {
    return <JSAny?>[for (final Object? item in key) idbKey(item!)].toJS;
  }
  throw ArgumentError.value(key, 'key', 'Not a valid IndexedDB key');
}

/// The name and message of [error].
String idbDescribe(web.DOMException? error) =>
    error == null ? 'unknown error' : '${error.name}: ${error.message}';

/// A request of IndexedDB failed (the `error` event of the request or of a cursor).
class IdbRequestError implements Exception {
  IdbRequestError(this.name, this.message);

  factory IdbRequestError.of(web.IDBRequest request) {
    final web.DOMException? error = request.error;
    return IdbRequestError(
      error?.name ?? 'UnknownError',
      error?.message ?? 'unknown error',
    );
  }

  /// The name of the `DOMException`, e.g. `ConstraintError` or `QuotaExceededError`.
  final String name;
  final String message;

  @override
  String toString() => 'IndexedDB request failed: $name: $message';
}

/// The result of [request], or an [IdbRequestError]. The future completes in the `success` event of the request, so
/// that code awaiting it still runs while the transaction is active.
Future<JSAny?> idbRequest(web.IDBRequest request) {
  final Completer<JSAny?> completer = Completer<JSAny?>();
  request.onsuccess = ((web.Event _) => completer.complete(
    request.result,
  )).toJS;
  request.onerror = ((web.Event _) => completer.completeError(
    IdbRequestError.of(request),
  )).toJS;
  return completer.future;
}

/// Calls [visit] with every position of the cursor that [request] opened, synchronously in the success event of each
/// step, so that the transaction stays active, until [visit] returns false or the cursor is exhausted. [visit] may
/// call `delete` or `update` on the cursor (not `continue`: this does).
Future<void> idbForEach(
  web.IDBRequest request,
  bool Function(web.IDBCursor cursor) visit,
) {
  final Completer<void> completer = Completer<void>();
  request.onsuccess = ((web.Event _) {
    if (completer.isCompleted) {
      return;
    }
    final JSAny? result = request.result;
    if (result == null) {
      completer.complete();
      return;
    }
    final web.IDBCursor cursor = result as web.IDBCursor;
    try {
      if (visit(cursor)) {
        cursor.continue_();
      } else {
        completer.complete();
      }
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
    }
  }).toJS;
  request.onerror = ((web.Event _) {
    if (!completer.isCompleted) {
      completer.completeError(IdbRequestError.of(request));
    }
  }).toJS;
  return completer.future;
}

/// Completes when [transaction] committed, fails with a [StateError] when it aborted.
Future<void> idbCommitted(web.IDBTransaction transaction) {
  final Completer<void> completer = Completer<void>();
  transaction.oncomplete = ((web.Event _) => completer.complete()).toJS;
  transaction.onabort = ((web.Event _) {
    if (!completer.isCompleted) {
      completer.completeError(
        StateError(
          'IndexedDB transaction aborted: ${idbDescribe(transaction.error)}',
        ),
      );
    }
  }).toJS;
  return completer.future;
}
