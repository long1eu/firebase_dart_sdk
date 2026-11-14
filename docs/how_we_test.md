# How we test

This page lists the test suites of the repository, how to run them, what they found, and what
they do not cover. Commands are run from the repository root unless a directory is named.

The counts below were measured on 2026-11-14 at commit `88a8f1a0` (macOS arm64, Dart 3.11.5,
Firestore emulator v1.22.0), except where a source is named. Counts change with every commit; CI
has the current ones.

## Summary

| Suite | What it runs against | Tests | How to run |
|---|---|---|---|
| Unit, `cloud_firestore_dart` | nothing (in memory and SQLite) | 5,882 run, 498 skipped | `./tool/test_all.sh` |
| Unit, `firebase_app_dart` | nothing | 39 | `./tool/test_all.sh` |
| Unit, `firebase_auth_providers_dart` | fakes; 17 tests need the Auth emulator | 67 run, 17 skipped | `./tool/test_all.sh` |
| Integration over gRPC | Standard edition emulator | 887 run, 21 skipped | `./tool/test_integration.sh standard` |
| Integration over WebChannel | Standard edition emulator | 882 run, 26 skipped | `./tool/test_integration.sh standard --transport=webchannel` |
| Integration over WebChannel with long polling | Standard edition emulator | 882 run, 26 skipped | `./tool/test_integration.sh standard --transport=webchannel-longpolling` |
| Enterprise edition | Enterprise edition emulator | 447 run, 86 skipped | `./tool/test_integration.sh enterprise` |
| Browser | Chrome, dart2wasm and dart2js, against the emulator | 54 per compiler: 53 pass, 1 skipped (source: [platforms guide](guides/platforms.md)) | `./tool/test_browser.sh both` |
| Production verification kit | a real Firestore database (opt-in), or the emulator | 15 checks; latest production run: 13 passed, 2 skipped | `tool/verify_production/run.sh` |

The skipped tests are skipped with a reason that the test runner prints. 361 of the 498 skipped
unit tests are pipeline cases of the JS SDK: most of them are the same cases as the Android tests
that run in their place, and the others need real-time pipelines, which the Dart SDK does not
have. 75 of the 86 skipped Enterprise tests need real-time pipelines too. On the web
transport five more integration tests are skipped than over gRPC, for limits of the emulator's
WebChannel endpoint.

## The suites

### Unit tests

`./tool/test_all.sh` runs, for each of the three packages, `dart pub get`, `dart analyze lib` and
the tests (for `cloud_firestore_dart` only `test/unit`), then `dart pub get` and `dart analyze` for
each example in `examples/` (their tests need an emulator, see below). In
`cloud_firestore/cloud_firestore_dart`, `dart test test/unit -j 2` runs the Firestore unit suite
alone.

The Firestore unit tests by area (tests run, at the commit above):

| Area (`test/unit/...`) | Tests |
|---|---|
| `firebase/firestore/pipeline`: pipelines, expression evaluation | 1,764 |
| `firebase/firestore/local`: local store, SQLite and memory persistence, schema migrations | 902 |
| `firebase/firestore`: the public API | 639 |
| `firebase/firestore/spec`: the spec tests of the JS and Android SDKs | 544 |
| `firebase/firestore/remote`: serializer, streams, watch, web transport | 474 |
| `firebase/firestore/core`: query engine, views, sync engine | 405 |
| `firebase/firestore/model`: values, documents, mutations | 379 |
| `firebase/firestore/bundle` | 217 |
| other areas (collections, util, index, lite, auth, aggregation, fuzz, property, api) | 558 |

Most of these are ported from the unit tests of the Android and JS SDKs, with the upstream test
names. The **spec tests** are the JSON spec files that the JS and Android SDKs share (in
`test/res/json`): each one drives the sync engine through a scripted sequence of user actions and
watch messages and checks every snapshot. They run on memory and on SQLite persistence.

`test/unit/api` keeps the public API stable: a golden listing of each public library, and a
check that every Dart snippet of the READMEs and guides compiles.

### Integration tests

`test/integration` runs against the Firestore emulator. The same suite runs over the three
transports of the client: gRPC (the Dart VM), and the web transport (REST and WebChannel, as the
JS SDK) with streaming and with long polling, still on the VM. Start the emulator with
`./tool/start_emulator.sh`; the web transport runs use a private emulator on port 8090 that the
script starts itself. [`tool/README.md`](../tool/README.md) has the details.

`test/integration_enterprise` runs against the emulator in Enterprise edition (port 8181):
the BSON value types and Pipelines, mostly ported from the integration tests of the Android and
JS SDKs.

### Example apps

Each package in [`examples/`](../examples/README.md) (an HTTP server, a command-line tool, a Cloud
Run job) has tests that run it against the Firestore emulator and are skipped without one: in the
example's directory, `dart pub get`, then `FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart test`.
`tool/test_all.sh` only analyzes them, and CI does not run their tests.

### Browser tests

`./tool/test_browser.sh both` runs `test/browser` in Chrome, compiled with dart2wasm and with
dart2js, against a private emulator: the web transport, the SQLite cache in IndexedDB and OPFS,
reloads, crashes of the storage, Firestore Lite. CI runs them on dart2wasm when a change touches
what they cover, and on both compilers every night.

### Property and fuzz tests

Seeded random tests that check an invariant over many generated cases, and print the seed and
the shortest failing case when one fails:

- `test/unit/property`: value order, serializers, canonical ids, and agreement between query
  filters and the cache index (35 tests).
- In `test/unit/firebase/firestore/core`: the view under random writes, acknowledgements,
  reconnects, existence filters and limbo resolutions (`held_back_view_property_test.dart`,
  `view_listeners_property_test.dart`), and two clients that share one SQLite cache
  (`shared_cache_write_ownership_property_test.dart`).
- In the integration suites: queries, the query cache, value order and mutations, compared with
  the emulator (`property_*_test.dart`).
- `test/unit/fuzz`: hostile input for the bundle reader, the proto decoder, the web transport and
  other parsers (54 tests).

`PROPERTY_SCALE=<n>` runs n times as many cases and `PROPERTY_SEED=<seed>` repeats one. CI runs
them at the default scale; the nightly workflow runs them at `PROPERTY_SCALE=20`.

### Chaos and soak tests

`test/integration/firebase/firestore/chaos` puts a TCP proxy between the clients and the
emulator that cuts, stalls and delays connections, and checks that no write is lost or applied
twice where that is avoidable, that listeners end in sync with the backend, and that terminate
and restart work while the network fails. They are part of the integration suite.

- `soak_chaos_test.dart`: several clients do random operations on the same documents while their
  connections fail at random; then the network is restored and every client must show the state
  of the backend. `CHAOS_SOAK_SECONDS` sets the length (4 s by default), `CHAOS_SOAK_SEED`
  repeats a run.
- `scale_soak_test.dart`: opt-in with `SCALE_SOAK_SECONDS`; worker isolates with several clients
  each. The nightly workflow runs it for two minutes with two isolates of three clients.

### Production verification kit

`tool/verify_production` runs 15 named checks against a real Firestore database, with the
user's own credentials and only after an explicit `--yes`. It writes below one document of its
own and deletes what it wrote. It answers questions the emulator cannot, for example whether
production applies a re-sent write twice after a lost acknowledgement.

It was run against a production database in Standard edition. In its latest run 13 checks
passed and 2 were skipped: one needs an Enterprise edition database, the other a Web API key
with anonymous sign-in. An earlier run found one bug of the SDK, described below. The result of
each check is in [`tool/verify_production/README.md`](../tool/verify_production/README.md).

### Other checks

- `./tool/check_size.sh`: Firestore Lite compiled to JavaScript stays small and does not pull in
  the sync engine.
- `dart analyze` in CI on the lowest supported Dart SDK (3.8.0) and on stable, and the formatting
  check (`dart format --output=none --set-exit-if-changed lib example`) on 3.8.0 only.
- Migration tests open SQLite caches written by older versions, including a cache written by the
  published `cloud_firestore_vm` 0.0.7.

## CI

`.github/workflows/ci.yml` runs on every pull request and every push to `main`: the unit suites
on Dart 3.8.0 and on stable, the integration suite over the three transports, the Enterprise
suites, the browser suite on dart2wasm (when a change touches it) and the size check.
`.github/workflows/nightly.yml` runs the browser suite on both compilers, the scale soak, the
property tests at a larger scale, the unit suite in a Linux amd64 container, and the tests that
need the Firebase Auth emulator.

## Bugs these tests found

Three examples from the revival, with the commit that fixed each one.

**A listener could lose a document for good** (`26f66d45`). After an existence filter mismatch
the client resets a target and listens to it again; its documents go through limbo resolution.
When a resolution confirmed a document before the backend had sent the target again, the view
concluded that the backend does not return the document and dropped it. It did not come back,
and the snapshot was reported as in sync. Found by the property test of the view
(`held_back_view_property_test.dart`, seed 21045094 at `PROPERTY_SCALE=10`), which drives one
client through random writes, acknowledgements, reconnects, target resets, existence filters and
limbo resolutions against a fake backend. The fix only draws that conclusion once the target is
CURRENT on the current watch stream.

**An old write could replace a newer one on the web transport** (`077ced97`). When the client
closed a write stream (`disableNetwork()`, a credential change, an idle stream), the WebChannel
session of that stream went on sending what it had queued, retrying a failed request after
100 ms and 1 s. The client meanwhile sent the same writes and newer ones on its next stream, so
the old session could deliver its copy last, and the backend kept the older value. Found by the
chaos soak test on the web transports; `writes_chaos_test.dart` now reproduces it
deterministically. The session now ends when the stream is closed, as in the JS SDK.

**Stored query ids depended on debug output** (`c124d45b`). The canonical id of a query, the key
under which the SQLite cache stores the query's results, was built from the `toString()` of the
values in its filters. For a timestamp or document reference filter that was a multi-line debug
dump, so any change to those `toString()` methods would have made existing caches miss their
stored queries. This one was found by reviewing user-visible messages, not by a failing test; the
fix builds the ids with the strings of the JS SDK, migrates stored ids (SQLite schema 19), and
added tests that pin the ids (`query_canonical_id_test.dart`, `canonical_id_property_test.dart`)
and an integration test that a restarted client reuses its cached queries
(`target_reuse_test.dart`).

The production verification kit also found one: `-0.0` read over the web transport came back as
`0.0`, because production sends it as the JSON number `-0`, which `jsonDecode` reads as the
integer 0. The emulator itself stores `-0` as `0`, so no emulator test could tell the SDK's loss
of the sign from the emulator's.

## What is not tested

- Production Firestore beyond the verification kit: no run of the integration suite against a
  real project, no Enterprise edition database, no long-running load.
- Firebase Auth user sign-in against the real service (only against the Auth emulator).
- Browsers other than Chrome; Windows; Flutter apps on devices.

[features and limits](guides/features.md) lists the known gaps of the SDK itself.
