# Spike: what a Realtime Database client would take

> **Status.** Scoping only, written on 2026-11-21. No code was written and nothing was run against a database. The
> sizes are line counts of source at the commits named below; the effort figures are estimates.

**The answer.** A Realtime Database client is about twice the size of the Auth client and a sixth of the Firestore
port, and nothing in this repository was ever written for it: there is no legacy code to start from. A port of the
JS SDK's `@firebase/database` (about 21,400 lines of TypeScript without tests) comes to an estimated 25 to 40 agent
days for parity with the JS SDK, of which the largest share is the sync tree (local events, queries, transactions). Storage,
the other missing product with a pure-Dart precedent here, is about a quarter of that. A pure-Dart Realtime
Database client already exists (`firebase_dart` of appsup-dart, BSD-3-Clause, 11,050 lines), and this repository's
README already points users to it. Build it only when a user needs it in the same stack as `cloud_firestore_dart`
(one app, one Auth client, one App Check provider); otherwise keep pointing to `firebase_dart`.

## What was measured

| Source | Commit | Lines (without tests) | Tests |
|---|---|---|---|
| JS SDK `packages/database/src` | firebase-js-sdk `a086865` (2026-11-20) | 21,416: `core` 15,630, `api` 3,337, `realtime` 2,086 | 3,978 lines in `packages/database/test` |
| appsup-dart `firebase_dart`, `lib/src/database` | `912beb1` (2026-11-13), version 2.0.0-dev.9 | 11,050 | 8,886 lines in the package's tests (all products) |
| JS SDK `packages/storage/src` | `a086865` | 6,382 | not counted |
| This repository, `firebase_storage_dart/lib` (2019 code) | `532e89a` | 4,247 | 792 lines |
| This repository, `firebase_auth_providers_dart/lib` | `532e89a` | 7,453 | (for scale) |
| This repository, `cloud_firestore_dart/lib` | `532e89a` | 94,592 | (for scale) |

The counts are `wc -l` of the `.ts` or `.dart` files, comments and blank lines included.

## Legacy code in this repository

None for the Realtime Database. `git log --all` has no path with `database` in it other than Firestore's
(`database_collection`, `database_id`, `database_info`). The 2019 project ported Firestore, Auth and Storage only.

Pieces of this repository that a client would reuse:

- **Sorted collections.** The JS SDK's `SortedMap` and `ImmutableTree` are a left-leaning red-black tree, the same
  structure as `cloud_firestore_dart/lib/src/database_collection` (`ImmutableSortedMap`, `LLRBNode`). About 1,150
  lines of the JS core need no new port.
- **Tokens.** `FirebaseApp.authProvider` and `appCheckProvider` of `firebase_app_dart` are what the connection's
  `auth` and `appcheck` requests need, and `FirebaseUserAuth` already feeds them.
- **Transport and platforms.** WebSockets on the VM (`dart:io`) and in the browser, the dart2js and dart2wasm
  builds, and the emulator CI jobs follow the patterns Firestore's web transport set up.
- **The FlutterFire shim pattern.** `firebase_auth_dart_platform` and `cloud_firestore_dart_platform` show how to
  implement a platform interface (`firebase_database_platform_interface`) on top of a pure-Dart client.

## What the JS SDK has, by layer

| Layer | JS files | Lines | What it does |
|---|---|---|---|
| Wire protocol | `realtime/WebSocketConnection.ts`, `Connection.ts`, `TransportManager.ts`, `BrowserPollConnection.ts` | 2,086 | Protocol version 5 over a WebSocket: handshake, host redirects, keep-alive, frames split across messages. Long polling is a browser fallback and is not needed on the VM. |
| Persistent connection | `core/PersistentConnection.ts` | 1,100 | Requests by action code: `q`/`n` listen and unlisten, `p`/`m` put and merge, `o`/`om`/`oc` onDisconnect, `g` get, `auth`/`gauth`/`unauth`, `appcheck`; reconnects with backoff and replays listens and writes. |
| Repo | `core/Repo.ts` | 1,584 | Ties connection, sync tree and events together; transactions (`runTransaction`), server values (`serverTimestamp`, `increment`), `.info/connected`, `goOffline`/`goOnline`. |
| Sync tree and views | `SyncTree.ts`, `SyncPoint.ts`, `WriteTree.ts`, `CompoundWrite.ts`, `view/*` | 5,685 | Local writes on top of server data, event generation (`value`, `child_added`, `child_changed`, `child_moved`, `child_removed`), query filters and limits. |
| Snapshots and data | `snap/*`, `util/*` | 5,604 | The tree of nodes, priorities, ordering by key, value, child or priority, validation of paths and data, push ids. |
| Public API | `api/*` | 3,337 | `ref`, `set`, `update`, `push`, `remove`, `get`, `onValue` and the child events, query constraints, `onDisconnect`, `runTransaction`, `connectDatabaseEmulator`. |

The JS SDK keeps no data on disk: offline it works from memory and loses pending writes when the page closes.
The Android and iOS SDKs add disk persistence (`setPersistenceEnabled`); `firebase_dart` has it too, on Hive.

## How it compares with Storage

The task asked for a comparison with the Storage work. There is no Storage branch on the remote
(`git ls-remote --heads origin`, 2026-11-21), so the comparison is with what migrating Storage would be:
`firebase_storage_dart` is 4,247 lines of 2019 code, 792 lines of tests, outside the migrated and tested set; the JS
`@firebase/storage` is 6,382 lines. Storage is request and response over HTTP (uploads in chunks, resumable
sessions, metadata, list), with no long-lived connection and no local state to merge.

| | Storage | Realtime Database |
|---|---|---|
| JS source | 6,382 lines | 21,416 lines |
| Code in this repository | 4,247 lines from 2019, untested | none |
| Connection | HTTP requests | one WebSocket per database, with reconnect and replay |
| Local state | none | server data plus pending writes, merged into events |
| Emulator | Storage emulator | Database emulator (WebSocket protocol, rules) |
| Estimate | 6 to 10 agent days | 25 to 40 agent days |

## Phases and estimates

An agent day here is what one implementer agent did in a day on the Auth client (`docs/auth_client_assessment.md`
used the same unit). Each phase ends with tests against the Database emulator.

| Phase | What | Estimate |
|---|---|---|
| 1. REST | `get`, `set`, `update`, `remove`, `push` over the REST API (`.json` URLs with the ID token), and `connectDatabaseEmulator`. Useful alone for servers and command line tools. | 2 to 3 days |
| 2. Connection | The WebSocket protocol, auth and App Check tokens, listen and unlisten, put and merge, onDisconnect, server values, reconnect with replay, `.info/connected`. | 5 to 8 days |
| 3. Sync tree | Views and event generation, queries (`orderBy*`, `limitTo*`, `startAt`/`startAfter`/`endAt`/`endBefore`/`equalTo`), local writes on top of server data, transactions. The largest phase. | 12 to 18 days |
| 4. FlutterFire shim | `firebase_database_platform_interface` on top of the client, like the Auth and Firestore shims. | 4 to 6 days |
| 5. Disk persistence (optional) | What Android and iOS have and the JS SDK has not: pending writes and cached data across restarts, on the SQLite and IndexedDB engines Firestore already uses. | 5 to 8 days |

Phases 1 to 4 are JS parity (23 to 35 days, rounded up to 25 to 40 with the CI work). Phase 5 goes beyond it.

## Build, adopt or point

| Option | For | Against |
|---|---|---|
| Port the JS SDK here | One stack with Firestore and Auth (one token source, one App Check, one emulator setup); the same naming as the JS SDK; tests follow the JS tests. | 25 to 40 days, then upkeep with each JS release. |
| Build on `firebase_dart`'s code | 11,050 lines that already work, with disk persistence; BSD-3-Clause is compatible with this repository's Apache-2.0 (keep the notice). | Its dependencies (Hive, quiver, rxdart, sortedmap, openid_client and more) would come along or need replacing; its API and internals follow its own design, not the JS SDK's; it has its own Auth, which would have to be cut out. |
| Keep pointing users to `firebase_dart` | No work. Already in the README and in `docs/why_this_library.md`. | Two Auth clients in an app that uses both libraries. |

**Recommendation.** Keep pointing to `firebase_dart` until a user asks for the Realtime Database next to
`cloud_firestore_dart`. Then start with phase 1 (REST), which is small and useful on its own, and decide on
phases 2 and 3 with that user's needs in hand. Port from the JS SDK rather than from `firebase_dart`, for the
same reasons the Auth client followed the JS SDK: one design to compare against, and the JS tests to port.

## Not checked

- No code was run: no emulator, no real database. The emulator's support for every request of protocol 5 was not
  checked.
- The estimates are not measured; they scale the Auth client's pace by line count and by the extra state the sync
  tree holds.
- `firebase_dart`'s Realtime Database was not run or reviewed beyond its file list, line count and dependencies.
- The JS tests were counted, not read; how many need a browser was not checked.
