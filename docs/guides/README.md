# Guides

Guides for `cloud_firestore_dart`, the unofficial pure-Dart Cloud Firestore client, its app layer
`firebase_app_dart` and the token providers of `firebase_auth_providers_dart`. The package
READMEs are short landing pages; the API reference is on pub.dev.

1. [Getting started](getting_started.md): install, create the app and the instance, read and
   write, on the Dart VM, in Flutter and on the web.
2. [Queries, data and the API](queries_and_data.md): aggregations, OR queries, vector search,
   typed converters, bundles and snapshot JSON, and how the API compares with FlutterFire and
   the JS SDK.
3. [Transactions and the lifecycle](transactions_and_lifecycle.md): retries, read-only
   transactions, and what `terminate()` does to work in progress.
4. [Offline persistence and cache settings](offline_persistence.md): memory and persistent
   caches, SQLite on the VM, IndexedDB or OPFS on the web, protecting the cache files, cache indexes,
   connectivity.
5. [Several clients on one cache](multiple_clients.md): hot restart, background isolates and
   second processes; the primary lease and what a secondary client does.
6. [Authentication and App Check](authentication.md): signed-in users, service accounts,
   Application Default Credentials, the Auth emulator, App Check tokens.
7. [Pipelines (preview, Enterprise only)](pipelines.md): server-side queries made of stages and
   expressions.
8. [Firestore Lite](lite.md): the client without cache and listeners, one request per call.
9. [Platforms](platforms.md): the Dart VM on macOS, Linux and Windows, Flutter, and the web.
10. [The emulator and testing](emulator_and_testing.md): connecting to the emulator, mock users,
    tests with `package:test`, the Enterprise edition differences, and the test suites of this
    repository.
11. [Configuring the FirebaseApp](firebase_app.md): options, application ids for desktop and
    servers, platform dependencies.
12. [Features and limits](features.md): the full feature list, what is not done and the known
    gaps.
13. [Migrating from the `_vm` packages](../migrating_from_vm_packages.md): from
    `cloud_firestore_vm` and `firebase_core_vm` 0.0.x, with before and after code.
14. [Parity with the Firebase JS SDK](../parity.md): every area compared with the JS SDK,
    feature by feature, with the test that covers it and a list of the known limitations.
15. [Coming from FlutterFire](migrating_from_flutterfire.md): when to use this package instead
    of the FlutterFire `cloud_firestore` plugin and when not to, the setup differences, the API
    side by side, and running both in one app.
16. [Flutter](flutter.md): creating the client before `runApp`, `StreamBuilder` and snapshot
    metadata, the SQLite cache per platform, connectivity, the app lifecycle, and what was tried on
    which platform.
17. [The web](web.md): using the client in a browser (experimental): transports, caches, the one-tab
    limit, CORS, bundle size, dart2js and dart2wasm.
18. [Servers, jobs and command-line tools](server.md): credentials per environment, the memory
    cache, one instance per process, listeners and transactions in workers, graceful shutdown,
    containers, and what this client is not compared with the Admin SDK.
19. [Cookbook](cookbook.md): short recipes for common tasks (pagination, counters, aggregations,
    imports and deletes, transactions, offline state, vector search, JSON export), each with a
    runnable program.
20. [Error handling](error_handling.md): the error types, every error code with its cause and
    whether the client retries it, writes while offline, listener errors, transaction retries.
21. [Troubleshooting](troubleshooting.md): symptoms, causes and fixes, turning on logging and
    reading the log tags, and what to put in a bug report.
22. [Performance and cache tuning](performance.md): how queries are answered from the cache, cache
    indexes, cache size and garbage collection, listeners, batches, bundles, with measurements.
23. [For AI coding agents](for_ai_agents.md): packages, imports, minimal programs, FlutterFire and
    JS names mapped to this client, and the rules, on one page.

Every Dart snippet in these guides is compiled against the current API by
`cloud_firestore/cloud_firestore_dart/test/unit/api/readme_snippets_test.dart`, except the blocks
marked `dart flutter`, which are taken from `examples/flutter_notes` and checked there by
`flutter analyze`.
