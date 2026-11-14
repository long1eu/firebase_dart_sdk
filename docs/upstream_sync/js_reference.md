# JS SDK reference point

The rest of this folder tracks the sync of the port with the **Android** SDK. This file records the
version of the **Firebase JS SDK** that the port was last compared against, so that the next
comparison can start from there.

| | |
|---|---|
| Package | `@firebase/firestore` **4.20.0** (in Firebase JS SDK 13.3.0) |
| Repository | https://github.com/firebase/firebase-js-sdk |
| Commit | `c03d2aa` (HEAD of `main` on 2026-11-12) |
| Compared on | 2026-11-13 and 2026-11-14 |
| Result | [`docs/parity.md`](../parity.md) (feature matrix and known limitations) |

## What was compared

- Every entry of `packages/firestore/CHANGELOG.md` from 4.0.0 to 4.20.0 that changes behaviour
  (not build, bundling, dependencies or TypeScript typings).
- Every commit under `packages/firestore/src` from 2025-05-13 to 2026-11-12 (18 months).
- For each: whether the port has the change, with a test, or why it does not apply. Small missing
  fixes were ported with their upstream tests; the rest are listed in `docs/parity.md`.

Ported since then from that comparison: `experimentalLongPollingOptions.timeoutSeconds`
(`FirestoreSettings.experimentalLongPollingOptions`) and the online state on WebChannel connect
(JS 4.6.1, `onConnected` / `ConnectedEvent`).

## How to compare next time

1. Update a clone of the JS SDK (a shallow clone is enough if it reaches back to the commit above):
   `git fetch --shallow-since=2026-11-01 origin main`.
2. Read the new entries of `packages/firestore/CHANGELOG.md` above `## 4.20.0`.
3. List the new source commits: `git log c03d2aa..origin/main -- packages/firestore/src`.
   Skip formatting, docs, build and typing-only commits; read the diff of the rest.
4. For each behaviour change, find the Dart counterpart under
   `cloud_firestore/cloud_firestore_dart/lib/src/firebase/firestore/` (the port mirrors the
   Android layout; the JS file names map to it closely: `remote/watch_change.ts` is
   `remote/watch_change_aggregator.dart`, `remote/persistent_stream.ts` is
   `remote/datastore/base_stream.dart`, `platform/browser/webchannel_connection.ts` is
   `remote/datastore/web/web_channel_transport.dart` and `web_channel.dart`).
5. Port the upstream tests with the upstream test names. Spec tests come as JSON: regenerate
   `test/res/json/*_spec_test.json` from the JS spec tests and run the spec runner.
6. Update `docs/parity.md` and this file (version, commit, date).

The closure WebChannel that the JS SDK uses is not in the JS repository: it comes from
`google/closure-net` at the commit pinned in `packages/webchannel-wrapper/package.json`, as a
minified bundle (`firebase/webchannel_blob_es2018.js`). Behaviour of the WebChannel protocol
(query parameters such as `CI`, `AID` and `TO`, duplicate array handling) was checked there.
