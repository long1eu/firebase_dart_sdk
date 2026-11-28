## 0.1.0

Unreleased.

- `DataConnect` for a `FirebaseApp` and a `ConnectorConfig`: `executeQuery`, `executeMutation` and typed
  `QueryRef` and `MutationRef`, with GraphQL errors and partial data, Auth and App Check tokens, the emulator
  and `close()`.
- gRPC on the Dart VM and REST on the web.
- `QueryRef.subscribe()` emits only the results this instance fetched; server-pushed updates and the
  entity cache are not part of 0.1.0.
- `package:firebase_data_connect_dart/flutterfire.dart`: the symbols code from `firebase dataconnect:sdk:generate`
  uses, and `dart run firebase_data_connect_dart:rewrite_generated <directory>`, which points generated code at it
  so that it runs on the VM without Flutter.
