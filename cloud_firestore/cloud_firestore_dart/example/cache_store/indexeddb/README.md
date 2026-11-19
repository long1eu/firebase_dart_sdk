# A cache store on IndexedDB, for the web

`indexeddb_cache_store.dart` implements `CacheStore` of
`package:cloud_firestore_dart/cache_store.dart` (experimental) on IndexedDB, through
`package:web` and `dart:js_interop`: one database with one object store, `entries`, whose keys
are the binary keys of the SDK and whose values are its byte arrays.

IndexedDB orders binary keys (array buffers and their views) by their unsigned bytes, a shorter
key first when it is a prefix of the other: the order the store contract asks for. So:

- **`get`** is one `get` in a read-only IndexedDB transaction.
- **`scan`** is a key range (`IDBKeyRange.bound(start, end, false, true)`): forward, `getAllKeys`
  and `getAll` with the limit as their count, two requests of one transaction; in reverse, a
  cursor that walks back from the end (`getAll` has no direction).
- **`write`** is one read-write transaction with `durability: 'strict'`: its puts and deletes
  are committed whole or not at all, and on disk before the future completes.

IndexedDB commits a transaction by itself as soon as no request is pending when the event loop
turns, so a transaction cannot stay open while the SDK awaits other work. The store does not
need one: the SDK keeps the writes of each of its own transactions in memory, reads through them,
and hands them to the store in one `write` when the transaction commits.

The store answers a `versionchange` (another page that deletes the database) by closing its
connection. Like every `CacheStore`, it holds the cache of one Firestore instance at a time:
two tabs of the same app need two database names, or a lock of the app's own (for example
`navigator.locks`), since the SDK does not coordinate tabs over a `CacheStore`.

`main.dart` writes offline, terminates the instance, starts a new one over the same database and
reads the pending writes back; reload the page and the writes of the earlier loads are still
there. It needs no emulator and no project:

```sh
dart compile js -o example/cache_store/indexeddb/main.dart.js example/cache_store/indexeddb/main.dart
python3 -m http.server -d example/cache_store/indexeddb 8000   # then open http://localhost:8000
```

The checks of `package:cloud_firestore_dart/cache_store_testing.dart` run on this store in
Chrome, compiled with dart2js and with dart2wasm, in
`test/browser/web_cache_store_indexeddb_test.dart`, with the end-to-end case of `main.dart`
(through `tool/test_browser.sh`).
