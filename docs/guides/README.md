# Guides

Guides for `cloud_firestore_dart`, the unofficial pure-Dart Cloud Firestore client, and its app
layer `firebase_app_dart`. The API reference is on pub.dev; the
[package README](../../cloud_firestore/cloud_firestore_dart/README.md) has the status, the
feature list and the details of each area.

1. [Getting started](getting_started.md): install, create the app and the instance, read and
   write, on the Dart VM, in Flutter and on the web.
2. [Offline persistence and cache settings](offline_persistence.md): memory and persistent
   caches, SQLite on the VM, IndexedDB on the web, protecting the cache files, deleting the
   cache.
3. [Several clients on one cache](multiple_clients.md): hot restart, background isolates and
   second processes; the primary lease and what a secondary client does.
4. [Pipelines (preview, Enterprise only)](pipelines.md): server-side queries made of stages and
   expressions.
5. [Firestore Lite](lite.md): the client without cache and listeners, one request per call.
6. [The emulator and testing](emulator_and_testing.md): connecting to the emulator, mock users,
   tests with `package:test`.
7. [Migrating from the `_vm` packages](../migrating_from_vm_packages.md): from
   `cloud_firestore_vm` and `firebase_core_vm` 0.0.x, with before and after code.

Every Dart snippet in these guides is compiled against the current API by
`cloud_firestore/cloud_firestore_dart/test/unit/api/readme_snippets_test.dart`.
