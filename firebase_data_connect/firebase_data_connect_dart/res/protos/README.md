# Data Connect protos

The `.proto` files in this folder are byte-for-byte copies of the protos of the Data Connect iOS SDK:

- Source: https://github.com/firebase/data-connect-ios-sdk, folder `Protos/`, commit f06f9e3.
- Copied on 2026-11-28.
- Files: `connector_service.proto`, `graphql_error.proto`, `graphql_response_extensions.proto`, and the
  vendored `google/api/field_behavior.proto` and `google/rpc/code.proto` that they import. The well-known
  types (`google/protobuf/*.proto`) come from the include directory of `protoc` and are not copied.
- Not copied: `connector_stream_service.proto` (no consumer in 0.1.0), Android's `sdk.proto` and
  `emulator_service.proto`.

Why the iOS copy: each file says it is adapted from the emulator's API
(`// Adapted from third_party/firebase/dataconnect/emulator/server/api/<file>`), with the package edits that
the iOS `Protos/Readme.md` lists. It is a superset of the Android copy, and its `GraphqlErrorExtensions`
fields are the ones the emulator sends in its REST error bodies.

Cross-check: the Android copy at
https://github.com/firebase/firebase-android-sdk, folder
`firebase-dataconnect/src/main/proto/google/firebase/dataconnect/proto/`, commit 2cfdd03. Its field
numbers agree with these files, so the two copies are wire-compatible; it lacks the error-extension
fields after `file` and the `extensions` field of `ExecuteMutationResponse`.

Generated Dart code: `tool/gen_protos.sh` writes `lib/src/proto/` from these files (messages only, no
service stubs). Only `lib/src/transport/grpc/` imports it.

Drift check: `tool/check_data_connect_protos.sh` (run by hand, not in CI) starts the emulator, runs
`grpcurl -plaintext 127.0.0.1:<port> describe` for `google.firebase.dataconnect.v1.ConnectorService` and
its message types, reduces both sides to sorted `Message.field = number` lines and diffs them. It reports
and changes nothing.
